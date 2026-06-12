import 'dart:async';
import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../services/sheets_service.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

class AppProvider extends ChangeNotifier {
  List<Fair> _fairs = [];
  Fair? _currentFair;
  List<Client> _clients = [];
  List<String> _hangars = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSync;
  StreamSubscription? _pendingSubscription;
  Timer? _autoSyncTimer;
  Map<String, int> _pendingCounts = {}; // clientId → open pending count

  List<Fair> get fairs => _fairs;
  Fair? get currentFair => _currentFair;
  String get currentFairName => _currentFair?.name ?? 'Pendências';
  List<Client> get clients => _clients;
  List<String> get hangars => _hangars;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;
  Map<String, int> get pendingCounts => _pendingCounts;

  /// Total open pending items across all stands of a hangar (reactive).
  int openPendingForHangar(String hangar) {
    var sum = 0;
    for (final c in getClientsByHangar(hangar)) {
      sum += _pendingCounts[c.rowId] ?? 0;
    }
    return sum;
  }

  Client? clientById(String rowId) {
    for (final c in _clients) {
      if (c.rowId == rowId) return c;
    }
    return null;
  }

  Future<void> init() async {
    // Sync fairs from Firestore so all devices share the same fair list
    try {
      final remote = await FirestoreService.getFairs();
      for (final m in remote) {
        final id = m['id'] as int?;
        final mode = (m['mode'] as String?) ?? 'producao';
        final sheetMode = (m['sheetMode'] as String?) ?? 'individual';
        final fair = Fair(
          id: id,
          name: m['name'] as String,
          spreadsheetId: m['spreadsheetId'] as String,
          sheetName: m['sheetName'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          mode: mode,
          sheetMode: sheetMode,
        );
        await DatabaseService.upsertFairById(fair);
        // Keep local mode in sync with the cloud (upsert ignores existing rows)
        if (id != null) await DatabaseService.updateFairMode(id, mode);
      }
    } catch (_) {
      // Firestore unavailable — continue with local fairs only
    }
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
  }

  Future<void> selectFair(Fair fair) async {
    _currentFair = fair;
    _lastSync = null;
    _error = null;
    _setLoading(true);
    await _loadLocal();
    _startPendingStream(fair.name);
    _setLoading(false);
    _restartAutoSync(fair);
  }

  void _restartAutoSync(Fair fair) {
    _autoSyncTimer?.cancel();
    if (fair.isProduction) {
      _autoSyncTimer =
          Timer.periodic(const Duration(minutes: 10), (_) {
        if (_currentFair != null && !_isLoading) syncFromSheets();
      });
    }
  }

  void _startPendingStream(String fairName) {
    _pendingSubscription?.cancel();
    _pendingSubscription = FirestoreService.streamPendingByFair(fairName)
        .listen((items) async {
      for (final item in items) {
        await DatabaseService.upsertPendingFromFirestore(item);
      }
      if (_currentFair != null) {
        _pendingCounts =
            await DatabaseService.getAllPendingCounts(_currentFair!.id!);
      }
      notifyListeners();
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _pendingSubscription?.cancel();
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> loadFromLocal() async {
    if (_currentFair == null) return;
    _setLoading(true);
    await _loadLocal();
    _setLoading(false);
  }

  Future<void> syncFromSheets() async {
    if (_currentFair == null) return;
    _error = null;
    _setLoading(true);
    try {
      if (_currentFair!.isMestra) {
        await _syncMasterSheet();
      } else if (_currentFair!.isMestraChild) {
        await _syncMestraChildSheet();
      } else {
        await _syncIndividualSheet();
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _setLoading(false);
    }
  }

  /// Standard individual-sheet sync (original behavior + new-client detection).
  Future<void> _syncIndividualSheet() async {
    final existingIds =
        await DatabaseService.getExistingClientRowIds(_currentFair!.id!);

    final sheetClients = await SheetsService.fetchClients(
      spreadsheetId: _currentFair!.spreadsheetId,
      sheetName: _currentFair!.sheetName,
      fairId: _currentFair!.id!,
    );

    _preserveCompletion(sheetClients, _clients);

    final newClients =
        sheetClients.where((c) => !existingIds.contains(c.rowId)).toList();

    await DatabaseService.upsertClients(sheetClients);

    _notifyNewClients(newClients, _currentFair!.name);

    await _loadLocal();
    _lastSync = DateTime.now();
  }

  /// Syncs a mestra (parent) sheet: groups clients by FEIRA column, auto-creates
  /// derived fairs, upserts clients, and refreshes the fair list.
  Future<void> _syncMasterSheet() async {
    final grouped = await SheetsService.fetchClientsGroupedByFair(
      spreadsheetId: _currentFair!.spreadsheetId,
      sheetName: _currentFair!.sheetName,
    );

    for (final entry in grouped.entries) {
      final feiraNome = entry.key;
      final tempClients = entry.value;

      final derivedId = await DatabaseService.findOrCreateDerivedFair(
        name: feiraNome,
        spreadsheetId: _currentFair!.spreadsheetId,
        sheetName: _currentFair!.sheetName,
      );

      // Assign real fairId / rowId
      final finalClients = tempClients.map((c) {
        final rowNum = c.rowId.split('_').last;
        return c.reidentify(derivedId, '${derivedId}_$rowNum');
      }).toList();

      final existingIds =
          await DatabaseService.getExistingClientRowIds(derivedId);

      final localClients =
          await DatabaseService.getClients(fairId: derivedId);
      _preserveCompletion(finalClients, localClients);

      final newClients =
          finalClients.where((c) => !existingIds.contains(c.rowId)).toList();

      await DatabaseService.upsertClients(finalClients);

      _notifyNewClients(newClients, feiraNome);

      // Push derived fair to Firestore so other devices see it
      try {
        await FirestoreService.saveFair(
          derivedId, feiraNome,
          _currentFair!.spreadsheetId, _currentFair!.sheetName,
          DateTime.now().toIso8601String(),
          mode: 'producao', sheetMode: 'mestra_child',
        );
      } catch (_) {}
    }

    _fairs = await DatabaseService.getFairs();
    await _loadLocal();
    _lastSync = DateTime.now();
  }

  /// Syncs a mestra_child fair: re-reads the master sheet and updates only
  /// the clients that belong to this derived fair name.
  Future<void> _syncMestraChildSheet() async {
    final grouped = await SheetsService.fetchClientsGroupedByFair(
      spreadsheetId: _currentFair!.spreadsheetId,
      sheetName: _currentFair!.sheetName,
    );

    final tempClients = grouped[_currentFair!.name];
    if (tempClients == null || tempClients.isEmpty) {
      throw Exception(
          'Nenhum cliente encontrado para "${_currentFair!.name}" '
          'na planilha mestra.');
    }

    final fairId = _currentFair!.id!;
    final finalClients = tempClients.map((c) {
      final rowNum = c.rowId.split('_').last;
      return c.reidentify(fairId, '${fairId}_$rowNum');
    }).toList();

    final existingIds = await DatabaseService.getExistingClientRowIds(fairId);
    _preserveCompletion(finalClients, _clients);

    final newClients =
        finalClients.where((c) => !existingIds.contains(c.rowId)).toList();

    await DatabaseService.upsertClients(finalClients);

    _notifyNewClients(newClients, _currentFair!.name);

    await _loadLocal();
    _lastSync = DateTime.now();
  }

  /// Copies isCompleted / completedAt from previously loaded local clients onto
  /// the freshly fetched sheet clients (prevents overwriting local check-offs).
  void _preserveCompletion(List<Client> sheetClients, List<Client> localClients) {
    final localMap = {for (final c in localClients) c.rowId: c};
    for (final c in sheetClients) {
      final local = localMap[c.rowId];
      if (local != null) {
        c.isCompleted = local.isCompleted;
        c.completedAt = local.completedAt;
      }
    }
  }

  /// Fire-and-forget: writes sync_events documents for truly new clients so the
  /// Cloud Function can send push notifications to their producer/consultant.
  void _notifyNewClients(List<Client> newClients, String fairName) {
    for (final nc in newClients) {
      if (nc.produtor.isEmpty && nc.atendimento.isEmpty) continue;
      FirestoreService.writeSyncEvent(
        clientId: nc.rowId,
        clientName: nc.nome,
        fairName: fairName,
        producerName: nc.produtor,
        consultantName: nc.atendimento,
      );
    }
  }

  Future<void> _loadLocal() async {
    if (_currentFair == null) return;
    _clients = await DatabaseService.getClients(fairId: _currentFair!.id!);
    _hangars = await DatabaseService.getHangars(fairId: _currentFair!.id!);
    _pendingCounts =
        await DatabaseService.getAllPendingCounts(_currentFair!.id!);
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  List<Client> getClientsByHangar(String hangar) {
    final list =
        (hangar == 'Externos' || hangar == 'Todos os Stands')
            ? _clients.where((c) => c.hangar.isEmpty).toList()
            : _clients.where((c) => c.hangar == hangar).toList();
    return list..sort((a, b) => a.local.compareTo(b.local));
  }

  Future<void> markClientCompleted(Client client, bool completed) async {
    await DatabaseService.updateClientStatus(client.rowId, completed);
    client.isCompleted = completed;
    client.completedAt = completed ? DateTime.now() : null;
    notifyListeners();
  }

  Future<PendingItem> addPendingItem(PendingItem item) async {
    // 1. Save to local SQLite
    final sqliteId = await DatabaseService.insertPendingItem(item);

    // 2. Save to Firestore (shared cloud)
    String? firestoreId;
    try {
      firestoreId = await FirestoreService.savePendingItem(
          item, _currentFair?.name ?? 'Desconhecida');
      await DatabaseService.updatePendingFirestoreId(sqliteId, firestoreId);
    } catch (_) {
      // Firestore save failed — item is still saved locally
    }

    return PendingItem(
      id: sqliteId,
      firestoreId: firestoreId,
      clientId: item.clientId,
      clientName: item.clientName,
      producerName: item.producerName,
      local: item.local,
      hangar: item.hangar,
      team: item.team,
      responsible: item.responsible,
      description: item.description,
      photoUrls: item.photoUrls,
      origem: item.origem,
      createdBy: item.createdBy,
      createdAt: item.createdAt,
    );
  }

  /// Edits the description and photos of a pending item (local + cloud).
  Future<void> editPendingItem(int sqliteId,
      {String? firestoreId,
      required String description,
      required List<String> photoUrls}) async {
    await DatabaseService.updatePendingContent(
        sqliteId, description, photoUrls);
    // Fire-and-forget: queued offline by Firestore, syncs on reconnect.
    if (firestoreId != null && firestoreId.isNotEmpty) {
      FirestoreService.updatePendingContent(firestoreId, description, photoUrls)
          .catchError((_) {});
    }
    notifyListeners();
  }

  Future<void> resolveItem(int sqliteId, {String? firestoreId, String? by}) async {
    await DatabaseService.resolvePendingItem(sqliteId, resolvedBy: by);
    if (firestoreId != null) {
      FirestoreService.resolveItem(firestoreId, resolvedBy: by)
          .catchError((_) {});
    }
    notifyListeners();
  }

  /// Attendant approves an organizer request → becomes a normal pending.
  Future<void> approveOrganizerItem(int sqliteId, {String? firestoreId}) async {
    await DatabaseService.approveOrganizerItem(sqliteId);
    if (firestoreId != null && firestoreId.isNotEmpty) {
      FirestoreService.approveOrganizerItem(firestoreId).catchError((_) {});
    }
    if (_currentFair != null) {
      _pendingCounts =
          await DatabaseService.getAllPendingCounts(_currentFair!.id!);
    }
    notifyListeners();
  }

  /// Attendant rejects an organizer request → finalized with a reason.
  Future<void> rejectOrganizerItem(int sqliteId,
      {String? firestoreId, String reason = '', String by = ''}) async {
    await DatabaseService.rejectOrganizerItem(sqliteId, reason: reason, by: by);
    if (firestoreId != null && firestoreId.isNotEmpty) {
      FirestoreService.rejectOrganizerItem(firestoreId, reason: reason, by: by)
          .catchError((_) {});
    }
    notifyListeners();
  }

  Future<void> markItemAwaitingValidation(int sqliteId, {String? firestoreId}) async {
    await DatabaseService.markItemAwaitingValidation(sqliteId);
    if (firestoreId != null) {
      FirestoreService.markAwaitingValidation(firestoreId).catchError((_) {});
    }
    notifyListeners();
  }

  Future<void> validateItem(int sqliteId, {String? firestoreId}) async {
    await DatabaseService.resolvePendingItem(sqliteId);
    if (firestoreId != null) {
      FirestoreService.resolveItem(firestoreId).catchError((_) {});
    }
    notifyListeners();
  }

  Future<void> validateItemByFirestoreId(String firestoreId, {String? by}) async {
    await DatabaseService.resolvePendingItemByFirestoreId(firestoreId,
        resolvedBy: by);
    FirestoreService.resolveItem(firestoreId, resolvedBy: by).catchError((_) {});
    notifyListeners();
  }

  Future<Fair> addFair(
      String name, String spreadsheetId, String sheetName,
      {String sheetMode = 'individual'}) async {
    final fair = Fair(
      name: name,
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
      createdAt: DateTime.now(),
      sheetMode: sheetMode,
    );
    final id = await DatabaseService.insertFair(fair);
    final newFair = Fair(
        id: id,
        name: fair.name,
        spreadsheetId: fair.spreadsheetId,
        sheetName: fair.sheetName,
        createdAt: fair.createdAt,
        sheetMode: sheetMode);
    // Push to Firestore so other devices see it
    try {
      await FirestoreService.saveFair(
          id, fair.name, fair.spreadsheetId, fair.sheetName,
          fair.createdAt.toIso8601String(),
          sheetMode: sheetMode);
    } catch (_) {}
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
    return newFair;
  }

  /// Toggles a fair between 'producao' and 'manutencao' (event open to exhibitors).
  Future<void> setFairMode(Fair fair, String mode) async {
    if (fair.id == null) return;
    await DatabaseService.updateFairMode(fair.id!, mode);
    try {
      await FirestoreService.saveFair(
        fair.id!,
        fair.name,
        fair.spreadsheetId,
        fair.sheetName,
        fair.createdAt.toIso8601String(),
        mode: mode,
        sheetMode: fair.sheetMode,
      );
    } catch (_) {}
    if (_currentFair?.id == fair.id) {
      _currentFair = _currentFair!.copyWith(mode: mode);
      _restartAutoSync(_currentFair!);
    }
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
  }

  Future<void> deleteFair(int id) async {
    await DatabaseService.deleteFair(id);
    try {
      await FirestoreService.deleteFairFromCloud(id);
    } catch (_) {}
    if (_currentFair?.id == id) {
      _currentFair = null;
      _clients = [];
      _hangars = [];
    }
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
  }
}
