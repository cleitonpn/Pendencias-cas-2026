import 'dart:async';
import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../services/sheets_service.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../utils/fair_key.dart';

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

  /// Verdadeiro quando a última tentativa de carregar as feiras da nuvem
  /// falhou. Sem isso a falha era invisível e o app seguia com a lista vazia.
  bool _fairsLoadFailed = false;
  bool get fairsLoadFailed => _fairsLoadFailed;

  Future<void> init() async {
    // Sync fairs from Firestore so all devices share the same fair list
    try {
      final remote = await FirestoreService.getFairs();
      for (final m in remote) {
        final id = m['id'] as int?;
        final mode = (m['mode'] as String?) ?? 'producao';
        final sheetMode = (m['sheetMode'] as String?) ?? 'individual';
        final remoteArchived = m['archived'] == true;
        final fair = Fair(
          id: id,
          name: m['name'] as String,
          spreadsheetId: m['spreadsheetId'] as String,
          sheetName: m['sheetName'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          mode: mode,
          sheetMode: sheetMode,
          autoApprove: m['autoApprove'] == true,
        );
        await DatabaseService.upsertFairById(fair);
        if (id != null) {
          await DatabaseService.updateFairMode(id, mode);
          await DatabaseService.updateFairAutoApprove(
              id, m['autoApprove'] == true);
          // Sync archived state so all devices see the same list
          if (remoteArchived) {
            await DatabaseService.archiveFair(id);
          } else {
            await DatabaseService.restoreFair(id);
          }
        }
      }
      _fairsLoadFailed = false;
    } catch (_) {
      // Firestore indisponível: segue com o que houver local, mas registra a
      // falha — antes ela sumia e o app ficava com a lista vazia para sempre,
      // já que init() só roda na splash.
      _fairsLoadFailed = true;
    }
    _fairs = await DatabaseService.getFairs();
    await _refreshIgnoredFairs();
    notifyListeners();
    _startFairsStream();
    _startCircularStream();
  }

  /// Recarrega a lista de feiras da nuvem. Usado quando o app está sem feiras
  /// — normalmente por uma falha de rede no arranque.
  Future<void> _reloadFairsFromCloud() async {
    try {
      final remote = await FirestoreService.getFairs();
      for (final m in remote) {
        final id = m['id'] as int?;
        if (id == null) continue;
        await DatabaseService.upsertFairById(Fair(
          id: id,
          name: (m['name'] as String?) ?? '',
          spreadsheetId: (m['spreadsheetId'] as String?) ?? '',
          sheetName: (m['sheetName'] as String?) ?? '',
          createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
              DateTime.now(),
          mode: (m['mode'] as String?) ?? 'producao',
          sheetMode: (m['sheetMode'] as String?) ?? 'individual',
          autoApprove: m['autoApprove'] == true,
        ));
      }
      _fairs = await DatabaseService.getFairs();
      _fairsLoadFailed = false;
    } catch (_) {
      _fairsLoadFailed = true;
    }
  }

  /// Listens to Firestore fair changes so mode, archive, and deletion propagate to all devices.
  void _startFairsStream() {
    _fairsSubscription?.cancel();
    _fairsSubscription = FirestoreService.streamFairs().listen((maps) async {
      bool changed = false;
      final remoteIds = maps.map((m) => m['id'] as int?).whereType<int>().toSet();

      for (final m in maps) {
        final id = m['id'] as int?;
        if (id == null) continue;
        final mode = (m['mode'] as String?) ?? 'producao';
        final remoteArchived = m['archived'] == true;
        // Fair is in _fairs only if it's not archived locally
        final local = _fairs.firstWhere((f) => f.id == id,
            orElse: () => Fair(id: -1, name: '', spreadsheetId: '',
                sheetName: '', createdAt: DateTime.now()));
        final locallyArchived = local.id == -1; // not in active list → archived or unknown
        if (local.id == -1 || local.mode != mode) {
          await DatabaseService.updateFairMode(id, mode);
          changed = true;
        }
        if (locallyArchived != remoteArchived) {
          if (remoteArchived) {
            await DatabaseService.archiveFair(id);
          } else {
            await DatabaseService.restoreFair(id);
          }
          changed = true;
        }
      }

      // Detect fairs deleted from Firestore and remove them locally too.
      for (final local in List<Fair>.from(_fairs)) {
        if (local.id != null && !remoteIds.contains(local.id)) {
          await DatabaseService.deleteFair(local.id!);
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

  /// Liga/desliga a aprovação automática de uma feira (nuvem + local).
  Future<void> setFairAutoApprove(int fairId, bool value) async {
    await DatabaseService.updateFairAutoApprove(fairId, value);
    try {
      await FirestoreService.setFairAutoApprove(fairId, value);
    } catch (_) {}
    _fairs = await DatabaseService.getFairs();
    if (_currentFair?.id == fairId) {
      _currentFair = _currentFair!.copyWith(autoApprove: value);
    }
    notifyListeners();
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

    // Pull the shared check-off state in the background so a device that never
    // marked anything locally still shows the real "X/N concluídos".
    if (fair.id != null) {
      _syncClientCompletion(fair.id!).then((_) {
        if (_currentFair?.id == fair.id) _loadLocal();
      }).catchError((_) {});
    }
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
        // Isolado por item: sem isto, um único registro problemático abortava
        // o laço e derrubava a sincronização inteira — em silêncio, já que a
        // exceção é assíncrona e o onError do stream não a captura.
        try {
          await DatabaseService.upsertPendingFromFirestore(item);
        } catch (_) {}
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
      // Num aparelho recém-instalado a lista pode estar vazia: init() roda uma
      // única vez na splash e, se o Firestore falhar lá, nada mais a recarrega.
      // O laço abaixo então não fazia nada e o botão parecia morto — daí a
      // necessidade de entrar como admin para popular o banco antes.
      if (_fairs.isEmpty) {
        await _reloadFairsFromCloud();
      }
      final snapshot = List<Fair>.of(_fairs);
      if (snapshot.isEmpty) {
        _error = 'Não foi possível carregar a lista de feiras. '
            'Verifique a conexão e tente de novo.';
        return;
      }
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
    // Remove clients whose rows were deleted from the spreadsheet.
    final activeRowIds = sheetClients.map((c) => c.rowId).toSet();
    await DatabaseService.deleteStaleClients(_currentFair!.id!, activeRowIds);

    await _syncClientCompletion(_currentFair!.id!);
    await _loadLocal();
    _lastSync = DateTime.now();
  }

  /// Nomes de feira que o admin mandou não trazer mais da planilha mestra.
  Set<String> _ignoredFairKeys = {};
  Set<String> get ignoredFairKeys => _ignoredFairKeys;

  Future<void> _refreshIgnoredFairs() async {
    try {
      _ignoredFairKeys = await FirestoreService.getIgnoredFairKeys();
    } catch (_) {
      // Sem a lista, o certo é NÃO recriar às cegas o que pode estar
      // excluído. Mantém a última lista conhecida.
    }
  }

  /// Apaga a feira derivada com este nome, aqui e na nuvem.
  Future<void> _removeLocalDerivedFair(String name) async {
    final key = fairKey(name);
    for (final f in await DatabaseService.getFairs()) {
      if (f.sheetMode != 'mestra_child' || fairKey(f.name) != key) continue;
      await DatabaseService.deleteFair(f.id!);
      try {
        await FirestoreService.deleteFairFromCloud(f.id!);
      } catch (_) {
        // A exclusão local já basta para ela sumir da tela; a da nuvem tenta
        // de novo no próximo sync.
      }
    }
  }

  /// Deixa de trazer esta feira da planilha mestra, em todos os aparelhos.
  Future<void> ignoreFair(String name) async {
    await FirestoreService.ignoreFair(name);
    await _refreshIgnoredFairs();
    await _removeLocalDerivedFair(name);
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
  }

  /// Volta a trazer uma feira ignorada. Ela reaparece no próximo sync.
  Future<void> unignoreFair(String key) async {
    await FirestoreService.unignoreFair(key);
    await _refreshIgnoredFairs();
    notifyListeners();
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

    // Sem isto, excluir uma feira que vem da mestra não durava: o sync lê a
    // coluna FEIRA e recria tudo o que estiver lá, então ela reaparecia na
    // sincronização seguinte.
    await _refreshIgnoredFairs();

    for (final entry in grouped.entries) {
      final feiraNome = entry.key;
      final tempClients = entry.value;

      if (_isMasterName(feiraNome)) continue;

      if (_ignoredFairKeys.contains(fairKey(feiraNome))) {
        // Pode ter sido ignorada em outro aparelho depois de já existir aqui.
        await _removeLocalDerivedFair(feiraNome);
        continue;
      }

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
      final activeIds = finalClients.map((c) => c.rowId).toSet();
      await DatabaseService.deleteStaleClients(derivedId, activeIds);

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
    if (_currentFair?.id != null) {
      await _syncClientCompletion(_currentFair!.id!);
    }
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
    final activeIds = finalClients.map((c) => c.rowId).toSet();
    await DatabaseService.deleteStaleClients(fairId, activeIds);

    await _syncClientCompletion(fairId);
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
    final now = completed ? DateTime.now() : null;
    await DatabaseService.updateClientStatus(client.rowId, completed);
    client.isCompleted = completed;
    client.completedAt = now;
    notifyListeners();

    // Publish to the shared cloud state so every device sees the same total.
    // Fire-and-forget: the local check-off must never depend on connectivity.
    if (client.firestoreId.isNotEmpty) {
      FirestoreService.setClientCompleted(
        clientFirestoreId: client.firestoreId,
        fairId: client.fairId,
        completed: completed,
        completedAt: now,
        completedBy: _completionAuthor,
        fairName: _currentFair?.name ?? '',
      ).catchError((_) {});
    }
  }

  /// Best-effort label of who checked the stand off, for the cloud record.
  String get _completionAuthor => 'Administrador';

  /// Reconciles the local check-offs with the shared cloud state.
  ///
  /// * a stand marked in the cloud is applied locally (so a second device no
  ///   longer shows 0/N while the field device shows 213/N);
  /// * a stand marked only locally is pushed up (backfills check-offs made
  ///   before this sync existed, and recovers writes made while offline).
  Future<void> _syncClientCompletion(int fairId) async {
    Map<String, ClientStatus> cloud = const {};
    var reachedCloud = false;
    try {
      cloud = await FirestoreService.getClientStatuses(fairId);
      reachedCloud = true;
    } catch (_) {
      // offline — keep whatever is local
    }
    if (!reachedCloud) return;

    final locals = await DatabaseService.getClients(fairId: fairId);
    final toBackfill = <ClientCompletionRecord>[];

    for (final c in locals) {
      if (c.firestoreId.isEmpty) continue;
      final remote = cloud[c.firestoreId];

      if (remote == null) {
        // Local-only check-off: queue it to be published.
        if (c.isCompleted) {
          toBackfill.add(ClientCompletionRecord(
            clientFirestoreId: c.firestoreId,
            completedAt: c.completedAt,
            completedBy: _completionAuthor,
          ));
        }
        continue;
      }

      if (remote.completed != c.isCompleted) {
        await DatabaseService.updateClientStatusByFirestoreId(
            fairId, c.firestoreId, remote.completed, remote.completedAt);
      }
    }

    // Awaited batched write — the previous version fired one unawaited write
    // per stand, so most of them were lost if the app was backgrounded before
    // they flushed (only part of the check-offs reached the other devices).
    if (toBackfill.isNotEmpty) {
      try {
        await FirestoreService.backfillClientCompletions(
          toBackfill,
          fairId: fairId,
          fairName: _currentFair?.name ?? '',
        );
      } catch (_) {
        // Stays local; the next sync retries because the cloud record is
        // still missing for these stands.
      }
    }
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

  /// Full edit: updates team, responsible, description and photos.
  Future<void> editPendingItemFull(
    int sqliteId, {
    String? firestoreId,
    required String team,
    required String responsible,
    required String description,
    required List<String> photoUrls,
  }) async {
    await DatabaseService.updatePendingFull(
      sqliteId,
      team: team,
      responsible: responsible,
      description: description,
      photoUrls: photoUrls,
    );
    if (firestoreId != null && firestoreId.isNotEmpty) {
      FirestoreService.updatePendingFull(
        firestoreId,
        team: team,
        responsible: responsible,
        description: description,
        photoUrls: photoUrls,
      ).catchError((_) {});
    }
    notifyListeners();
  }

  Future<void> resolveItem(int sqliteId,
      {String? firestoreId,
      String? by,
      String? note,
      List<String>? photoUrls}) async {
    await DatabaseService.resolvePendingItem(sqliteId,
        resolvedBy: by, resolutionNote: note, resolutionPhotoUrls: photoUrls);
    if (firestoreId != null) {
      FirestoreService.resolveItem(firestoreId,
              resolvedBy: by,
              resolutionNote: note,
              resolutionPhotoUrls: photoUrls)
          .catchError((_) {});
    }
    notifyListeners();
  }

  /// Attendant approves an organizer request → becomes a normal pending.
  Future<void> approveOrganizerItem(int sqliteId,
      {String? firestoreId, String note = ''}) async {
    await DatabaseService.approveOrganizerItem(sqliteId, note: note);
    if (firestoreId != null && firestoreId.isNotEmpty) {
      FirestoreService.approveOrganizerItem(firestoreId, note: note)
          .catchError((_) {});
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

  Future<void> validateItemByFirestoreId(String firestoreId,
      {String? by, String? note, List<String>? photoUrls}) async {
    await DatabaseService.resolvePendingItemByFirestoreId(firestoreId,
        resolvedBy: by);
    if (note != null && note.isNotEmpty ||
        photoUrls != null && photoUrls.isNotEmpty) {
      await DatabaseService.setResolutionNoteByFirestoreId(firestoreId,
          note: note, photoUrls: photoUrls);
    }
    FirestoreService.resolveItem(firestoreId,
            resolvedBy: by, resolutionNote: note, resolutionPhotoUrls: photoUrls)
        .catchError((_) {});
    notifyListeners();
  }

  /// Resolves every item in [items] in sequence.  Items loaded from SQLite
  /// always have a local id; the Firestore update is fire-and-forget.
  Future<void> batchValidateItems(List<PendingItem> items,
      {String by = 'Administrador',
      String? note,
      List<String>? photoUrls}) async {
    for (final item in items) {
      if (item.id != null) {
        await DatabaseService.resolvePendingItem(item.id!,
            resolvedBy: by, resolutionNote: note, resolutionPhotoUrls: photoUrls);
        if (item.firestoreId != null && item.firestoreId!.isNotEmpty) {
          FirestoreService.resolveItem(item.firestoreId!,
                  resolvedBy: by,
                  resolutionNote: note,
                  resolutionPhotoUrls: photoUrls)
              .catchError((_) {});
        }
      } else if (item.firestoreId != null && item.firestoreId!.isNotEmpty) {
        await DatabaseService.resolvePendingItemByFirestoreId(item.firestoreId!,
            resolvedBy: by);
        await DatabaseService.setResolutionNoteByFirestoreId(item.firestoreId!,
            note: note, photoUrls: photoUrls);
        FirestoreService.resolveItem(item.firestoreId!,
                resolvedBy: by,
                resolutionNote: note,
                resolutionPhotoUrls: photoUrls)
            .catchError((_) {});
      }
    }
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

  /// Exclui a feira. Com [alsoIgnore], ela também para de ser trazida da
  /// planilha mestra — sem isso o sync a recria pelo nome.
  ///
  /// Devolve null quando deu tudo certo, ou o motivo da falha. Antes o erro da
  /// nuvem era engolido: a feira sumia da tela, continuava lá, e voltava no
  /// arranque seguinte sem que ninguém soubesse por quê.
  Future<String?> deleteFair(int id, {bool alsoIgnore = false}) async {
    final fair = _fairs.where((f) => f.id == id).toList();
    final name = fair.isEmpty ? '' : fair.first.name;

    String? problema;
    await DatabaseService.deleteFair(id);
    try {
      await FirestoreService.deleteFairFromCloud(id);
      if (alsoIgnore && name.isNotEmpty) {
        await FirestoreService.ignoreFair(name);
        await _refreshIgnoredFairs();
      }
    } catch (e) {
      problema = 'A feira saiu deste aparelho, mas não foi possível removê-la '
          'da nuvem. Ela pode voltar ao sincronizar. '
          'Confira a conexão e tente de novo.';
    }
    if (_currentFair?.id == id) {
      _currentFair = null;
      _clients = [];
      _hangars = [];
    }
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
    return problema;
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
