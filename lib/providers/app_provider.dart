import 'dart:async';
import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../services/sheets_service.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class AppProvider extends ChangeNotifier {
  List<Fair> _fairs = [];
  Fair? _currentFair;
  List<Client> _clients = [];
  List<String> _hangars = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSync;
  DateTime? _lastAutoSync;
  DateTime? _lastGlobalSync;
  StreamSubscription? _pendingSubscription;
  StreamSubscription? _fairsSubscription;
  StreamSubscription? _circularSubscription;
  bool _circularInitialized = false;
  String? _lastCircularId;
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
  DateTime? get lastAutoSync => _lastAutoSync;
  DateTime? get lastGlobalSync => _lastGlobalSync;
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
    _startFairsStream();
    _startCircularStream();
  }

  /// Listens to Firestore fair changes so mode updates propagate to all devices.
  void _startFairsStream() {
    _fairsSubscription?.cancel();
    _fairsSubscription = FirestoreService.streamFairs().listen((maps) async {
      bool changed = false;
      for (final m in maps) {
        final id = m['id'] as int?;
        if (id == null) continue;
        final mode = (m['mode'] as String?) ?? 'producao';
        // Find local fair and check if mode changed
        final local = _fairs.firstWhere((f) => f.id == id,
            orElse: () => Fair(id: -1, name: '', spreadsheetId: '',
                sheetName: '', createdAt: DateTime.now()));
        if (local.id == -1 || local.mode != mode) {
          await DatabaseService.updateFairMode(id, mode);
          changed = true;
        }
      }
      if (changed) {
        _fairs = await DatabaseService.getFairs();
        // Keep current fair in sync too
        if (_currentFair != null) {
          final updated = _fairs.firstWhere(
              (f) => f.id == _currentFair!.id,
              orElse: () => _currentFair!);
          if (updated.mode != _currentFair!.mode) {
            _currentFair = updated;
            _restartAutoSync(_currentFair!);
          }
        }
        notifyListeners();
      }
    }, onError: (_) {});
  }

  void _startCircularStream() {
    _circularSubscription?.cancel();
    _circularInitialized = false;
    _circularSubscription = FirestoreService.streamAvisos().listen((list) {
      if (!_circularInitialized) {
        _circularInitialized = true;
        _lastCircularId = list.isNotEmpty ? list.first['id'] as String? : null;
        return;
      }
      if (list.isEmpty) return;
      final latest = list.first;
      final newId = latest['id'] as String?;
      if (newId == _lastCircularId) return;
      _lastCircularId = newId;
      final title = (latest['title'] as String?) ?? 'Aviso';
      final body = (latest['body'] as String?) ?? '';
      NotificationService.messengerKey.currentState?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: const Color(0xFF1E3A5F),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📢 $title',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            if (body.isNotEmpty)
              Text(body,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ));
    }, onError: (_) {});
  }

  Future<void> selectFair(Fair fair) async {
    _currentFair = fair;
    // Carry over the global sync timestamp so HangarListScreen shows it
    _lastSync = _lastGlobalSync;
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
        if (_currentFair != null && !_isLoading) {
          syncFromSheets().then((_) {
            _lastAutoSync = DateTime.now();
            notifyListeners();
          });
        }
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
    _fairsSubscription?.cancel();
    _circularSubscription?.cancel();
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

  /// Syncs all non-child fairs at once. Called from the main screen.
  Future<void> syncAllFairs() async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    final savedFair = _currentFair;
    final errors = <String>[];
    try {
      final snapshot = List<Fair>.of(_fairs);
      for (final fair in snapshot) {
        // mestra_child fairs are covered when their parent mestra syncs
        if (fair.sheetMode == 'mestra_child') continue;
        _currentFair = fair;
        try {
          if (fair.isMestra) {
            await _syncMasterSheet();
          } else {
            await _syncIndividualSheet();
          }
        } catch (e) {
          errors.add('${fair.name}: ${e.toString().replaceFirst("Exception: ", "")}');
        }
      }
      _fairs = await DatabaseService.getFairs();
      _lastGlobalSync = DateTime.now();
      _lastSync = _lastGlobalSync;
      if (errors.isNotEmpty) _error = errors.join('\n');
    } finally {
      _currentFair = savedFair;
      if (savedFair != null) await _loadLocal();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Standard individual-sheet sync (original behavior + new-client detection).
  Future<void> _syncIndividualSheet() async {
    final existingClients =
        await DatabaseService.getClients(fairId: _currentFair!.id!);
    final existingMap = {for (final c in existingClients) c.rowId: c};

    final sheetClients = await SheetsService.fetchClients(
      spreadsheetId: _currentFair!.spreadsheetId,
      sheetName: _currentFair!.sheetName,
      fairId: _currentFair!.id!,
      fairName: _currentFair!.name,
    );

    _preserveCompletion(sheetClients, existingClients);

    _notifyAssignments(sheetClients, existingMap, _currentFair!.name);

    await DatabaseService.upsertClients(sheetClients);

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

    final masterName = _currentFair!.name.toLowerCase().trim();
    final masterSheet = _currentFair!.sheetName.toLowerCase().trim();

    // Names that belong to the master itself and must never become derived fairs.
    bool _isMasterName(String name) {
      final n = name.toLowerCase().trim();
      return n == masterName ||
          n == masterSheet ||
          n.contains(masterName) ||
          n.contains(masterSheet);
    }

    for (final entry in grouped.entries) {
      final feiraNome = entry.key;
      final tempClients = entry.value;

      if (_isMasterName(feiraNome)) continue;

      final derivedId = await DatabaseService.findOrCreateDerivedFair(
        name: feiraNome,
        spreadsheetId: _currentFair!.spreadsheetId,
        sheetName: _currentFair!.sheetName,
      );

      // Assign real fairId / rowId, keeping the already-computed firestoreId
      final finalClients = tempClients.map((c) {
        final rowNum = c.rowId.split('_').last;
        return c.reidentify(derivedId, '${derivedId}_$rowNum');
      }).toList();

      final localClients =
          await DatabaseService.getClients(fairId: derivedId);
      final existingMap = {for (final c in localClients) c.rowId: c};

      _preserveCompletion(finalClients, localClients);

      _notifyAssignments(finalClients, existingMap, feiraNome);

      await DatabaseService.upsertClients(finalClients);

      // Push derived fair metadata to Firestore — mode is intentionally
      // omitted so that mode changes set via setFairMode() survive syncs.
      await FirestoreService.saveDerivedFairMetadata(
        derivedId, feiraNome,
        _currentFair!.spreadsheetId, _currentFair!.sheetName,
        DateTime.now().toIso8601String(),
      );
    }

    // Clean up any stale derived fairs whose names match the master itself —
    // these were created before the filter existed and should be deleted.
    final allFairs = await DatabaseService.getFairs();
    for (final df in allFairs) {
      if (df.sheetMode != 'mestra_child') continue;
      if (df.spreadsheetId != _currentFair!.spreadsheetId) continue;
      if (df.sheetName != _currentFair!.sheetName) continue;
      if (!_isMasterName(df.name)) continue;
      await DatabaseService.deleteFair(df.id!);
      try { await FirestoreService.deleteFairFromCloud(df.id!); } catch (_) {}
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
    }).toList(); // firestoreId is already set on each client from fetchClientsGroupedByFair

    final existingClients = await DatabaseService.getClients(fairId: fairId);
    final existingMap = {for (final c in existingClients) c.rowId: c};

    _preserveCompletion(finalClients, existingClients);

    _notifyAssignments(finalClients, existingMap, _currentFair!.name);

    await DatabaseService.upsertClients(finalClients);

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

  /// Fire-and-forget: writes sync_events for any client that just received a
  /// producer or consultant assignment (including brand-new clients).
  /// Only the newly assigned party is included so the other side isn't
  /// re-notified if they were already set.
  void _notifyAssignments(
      List<Client> sheetClients,
      Map<String, Client> existingMap,
      String fairName) {
    // Secondary index by firestoreId to handle rowId shifts (e.g. master sheet rows reordered)
    final existingByFirestoreId = <String, Client>{};
    for (final c in existingMap.values) {
      if (c.firestoreId.isNotEmpty) existingByFirestoreId[c.firestoreId] = c;
    }

    for (final nc in sheetClients) {
      final existing = existingMap[nc.rowId] ??
          (nc.firestoreId.isNotEmpty ? existingByFirestoreId[nc.firestoreId] : null);
      final isNewClient = existing == null;
      final newProducer =
          (isNewClient || existing!.produtor.isEmpty) && nc.produtor.isNotEmpty;
      final newConsultant =
          (isNewClient || existing.atendimento.isEmpty) && nc.atendimento.isNotEmpty;
      if (newProducer || newConsultant) {
        FirestoreService.writeSyncEvent(
          clientId: nc.firestoreId,
          clientName: nc.nome,
          fairName: fairName,
          producerName: newProducer ? nc.produtor : '',
          consultantName: newConsultant ? nc.atendimento : '',
        );
      }
      if (isNewClient) {
        FirestoreService.writeNewClientBroadcast(
          clientId: nc.firestoreId,
          clientName: nc.nome,
          fairName: fairName,
        );
      }
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

  Future<void> archiveFair(Fair fair) async {
    if (fair.id == null) return;
    await DatabaseService.archiveFair(fair.id!);
    await FirestoreService.archiveFairInCloud(fair.id!, true);
    if (_currentFair?.id == fair.id) {
      _currentFair = null;
      _clients = [];
      _hangars = [];
    }
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
  }

  Future<void> restoreFair(Fair fair) async {
    if (fair.id == null) return;
    await DatabaseService.restoreFair(fair.id!);
    await FirestoreService.archiveFairInCloud(fair.id!, false);
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
  }
}
