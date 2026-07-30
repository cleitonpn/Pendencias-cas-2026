import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pending_item.dart';
import '../models/montage_update.dart';
import '../models/freight_request.dart';
import '../models/meeting.dart';
import '../models/client.dart';
import '../utils/client_fingerprint.dart';
import 'admin_api.dart';
import 'cloud_writes.dart';
import '../utils/organizer_fairs.dart';
import '../utils/fair_key.dart';

class FirestoreService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─── PINs: leitura e escrita pelo servidor ────────────────────────────────
  //
  // As coleções de PIN não são mais acessíveis pelo cliente (ver
  // firestore.rules). Os métodos abaixo mantêm as mesmas assinaturas de antes
  // para que a tela de Configurações continue igual, mas por dentro falam com
  // a função `manageUsers`, que exige sessão de administrador.
  //
  // A tela pede a lista de nomes e depois o PIN de cada um, um por um. Sem
  // este cache seriam dezenas de chamadas de função por abertura de tela.

  static final Map<String, List<Map<String, dynamic>>> _userCache = {};

  static Future<List<Map<String, dynamic>>> _listUsers(String role) async {
    final users = await AdminApi.list(role);
    _userCache[role] = users;
    return users;
  }

  static Map<String, dynamic>? _cachedUser(String role, String name) {
    for (final u in _userCache[role] ?? const <Map<String, dynamic>>[]) {
      if (u['name'] == name) return u;
    }
    return null;
  }

  static Future<T?> _userField<T>(String role, String name, String field) async {
    // Só busca se o papel ainda não foi carregado. A tela mistura nomes vindos
    // da planilha com os que têm PIN cadastrado, então "não achou" é comum e
    // não pode virar uma nova chamada de função a cada nome.
    if (!_userCache.containsKey(role)) await _listUsers(role);
    final v = _cachedUser(role, name)?[field];
    return v is T ? v : null;
  }

  static Future<void> _setUser(String role, String name,
      {String? pin, Map<String, dynamic>? extra}) async {
    await AdminApi.set(role, name, pin: pin, extra: extra);
    _userCache.remove(role);
  }

  static Future<void> _removeUser(String role, String name) async {
    await AdminApi.remove(role, name);
    _userCache.remove(role);
  }

  static Future<List<String>> _listNames(String role) async {
    final users = await _listUsers(role);
    final names = users
        .map((u) => (u['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort();
    return names;
  }

  /// Descarta os PINs em memória — chamado ao sair da tela de Configurações.
  static void clearUserCache() => _userCache.clear();

  // ─── Montage updates (fotos de andamento da montagem) ────────────────────────

  static Future<void> saveMontageUpdate({
    required String clientId,
    required String fairName,
    required String photoUrl,
    required String createdBy,
  }) async {
    // Fire-and-forget: Firestore enfileira offline e envia ao reconectar.
    _db.collection('montage_updates').add({
      'clientId': clientId,
      'fairName': fairName,
      'photoUrl': photoUrl,
      'createdBy': createdBy,
      'createdAt': DateTime.now().toIso8601String(),
    }).ignore();
  }

  static Future<List<MontageUpdate>> getMontageUpdates(String clientId) async {
    final snap = await _db
        .collection('montage_updates')
        .where('clientId', isEqualTo: clientId)
        .get();
    final list = snap.docs
        .map((d) => MontageUpdate.fromFirestore(d.id, d.data()))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Returns the set of producer names who sent at least one montage photo
  /// today (local date) for the given fair.
  static Future<Set<String>> getMontageProducersToday(String fairName) async {
    final todayPrefix =
        DateTime.now().toIso8601String().substring(0, 10); // "YYYY-MM-DD"
    try {
      final snap = await _db
          .collection('montage_updates')
          .where('fairName', isEqualTo: fairName)
          .get();
      return snap.docs
          .where((d) =>
              ((d.data()['createdAt'] as String?) ?? '').startsWith(todayPrefix))
          .map((d) => (d.data()['createdBy'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  // ─── Pending Items ───────────────────────────────────────────────────────────

  static Future<String> savePendingItem(
      PendingItem item, String fairName) async {
    final doc = _db.collection('pending_items').doc();
    // Fire-and-forget: the doc id is generated client-side, so we can return it
    // immediately. Firestore's offline cache queues the write and retries when
    // the connection returns — so creating a pending works offline in the field.
    final payload = <String, dynamic>{
      'fairName': fairName,
      'clientId': item.clientId,
      'clientName': item.clientName,
      'producerName': item.producerName,
      'consultantName': item.consultantName,
      'local': item.local,
      'hangar': item.hangar,
      'team': item.team,
      'responsible': item.responsible,
      'description': item.description,
      'photoUrls': item.photoUrls,
      'origem': item.origem,
      'createdBy': item.createdBy,
      'resolvedBy': '',
      'approvalStatus': item.approvalStatus,
      'rejectionReason': '',
      'approvalNote': '',
      'resolutionNote': '',
      'resolutionPhotoUrls': <String>[],
      'isResolved': false,
      'awaitingValidation': false,
      'createdAt': item.createdAt.toIso8601String(),
      'resolvedAt': null,
    };
    // A criação do chamado é o dado mais importante do app: se ela não subir,
    // ninguém em campo fica sabendo do serviço. Sai sem bloquear, mas a falha
    // entra na fila de retentativa em vez de sumir.
    CloudWrites.fireAndForget(
      'abertura da pendência (${item.clientName})',
      () => doc.set(payload),
    );
    return doc.id;
  }

  /// Approves an organizer request (becomes a normal pending).
  static Future<void> approveOrganizerItem(String firestoreId,
      {String note = ''}) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'approvalStatus': 'aprovada',
      if (note.isNotEmpty) 'approvalNote': note,
    });
  }

  /// Rejects an organizer request, finalizing it with a reason.
  static Future<void> rejectOrganizerItem(String firestoreId,
      {String reason = '', String by = ''}) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'approvalStatus': 'recusada',
      'rejectionReason': reason,
      'isResolved': true,
      'resolvedAt': DateTime.now().toIso8601String(),
      if (by.isNotEmpty) 'resolvedBy': by,
    });
  }

  /// Real-time stream of all organizer items awaiting consultant approval,
  /// across every fair. Filters in memory to avoid composite index requirement.
  static Stream<List<PendingItem>> streamAllPendingApprovals() {
    return _db
        .collection('pending_items')
        .where('origem', isEqualTo: 'organizadora')
        .snapshots()
        .map((snap) {
      final items = snap.docs
          .map((d) => PendingItem.fromFirestore(d.id, d.data()))
          .where((item) => item.approvalStatus == 'pendente' && !item.isResolved)
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  /// All requests created by a given organizer (for the "my requests" view).
  static Future<List<PendingItem>> getOrganizerRequests(String createdBy) async {
    final snapshot = await _db
        .collection('pending_items')
        .where('createdBy', isEqualTo: createdBy)
        .get();
    final items = snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  static Future<void> resolveItem(String firestoreId,
      {String? resolvedBy,
      String? resolutionNote,
      List<String>? resolutionPhotoUrls}) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'isResolved': true,
      'resolvedAt': DateTime.now().toIso8601String(),
      if (resolvedBy != null && resolvedBy.isNotEmpty) 'resolvedBy': resolvedBy,
      // Opcionais: só grava quando vieram preenchidos, para não apagar o que
      // já estava lá.
      if (resolutionNote != null && resolutionNote.isNotEmpty)
        'resolutionNote': resolutionNote,
      if (resolutionPhotoUrls != null && resolutionPhotoUrls.isNotEmpty)
        'resolutionPhotoUrls': resolutionPhotoUrls,
    });
  }

  static Future<void> updatePendingContent(
      String firestoreId, String description, List<String> photoUrls) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'description': description,
      'photoUrls': photoUrls,
    });
  }

  /// Full edit: updates team, responsible, description and photos.
  static Future<void> updatePendingFull(
      String firestoreId, {
      required String team,
      required String responsible,
      required String description,
      required List<String> photoUrls,
  }) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'team': team,
      'responsible': responsible,
      'description': description,
      'photoUrls': photoUrls,
    });
  }

  /// Grava nota/fotos de manutenção sem concluir o item — usado quando o
  /// produtor marca como concluída e o chamado ainda vai para validação.
  static Future<void> setResolutionNote(String firestoreId,
      {String? note, List<String>? photoUrls}) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      if (note != null && note.isNotEmpty) 'resolutionNote': note,
      if (photoUrls != null && photoUrls.isNotEmpty)
        'resolutionPhotoUrls': photoUrls,
    });
  }

  static Future<void> markAwaitingValidation(String firestoreId) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'awaitingValidation': true,
    });
  }

  static Future<void> markInProgress(String firestoreId, String by) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'inProgress': true,
      'inProgressBy': by,
    });
  }

  /// Itens que produtor/líder NÃO devem ver: pedidos da organizadora ainda
  /// aguardando aprovação, ou recusados. O SQLite já filtrava isso
  /// (_visibleClause), mas as consultas do Firestore não — por isso um pedido
  /// aparecia para o produtor antes de o admin/consultor aprovar.
  static bool _visibleToField(PendingItem i) =>
      i.approvalStatus != 'pendente' && i.approvalStatus != 'recusada';

  static Future<List<PendingItem>> getItemsByProducer(
      String producerName) async {
    final snapshot = await _db
        .collection('pending_items')
        .where('producerName', isEqualTo: producerName)
        .where('isResolved', isEqualTo: false)
        .get();
    final items = snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .where(_visibleToField)
        .toList();
    items.sort((a, b) {
      final h = a.hangar.compareTo(b.hangar);
      if (h != 0) return h;
      return a.local.compareTo(b.local);
    });
    return items;
  }

  static Future<List<PendingItem>> getAwaitingItemsByClientId(
      String clientId) async {
    final snapshot = await _db
        .collection('pending_items')
        .where('clientId', isEqualTo: clientId)
        .get();
    return snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .where((item) => item.awaitingValidation && !item.isResolved)
        .toList();
  }

  /// Todos os chamados de um stand, para o expositor acompanhar os próprios
  /// pedidos e ver as notas e fotos da manutenção.
  static Future<List<PendingItem>> getItemsByClientId(String clientId) async {
    if (clientId.isEmpty) return [];
    final snapshot = await _db
        .collection('pending_items')
        .where('clientId', isEqualTo: clientId)
        .get();
    final items = snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  // ─── Producer PINs ──────────────────────────────────────────────────────────

  static Future<String?> getProducerPin(String producerName) =>
      _userField<String>('producer', producerName, 'pin');

  static Future<void> setProducerPin(String producerName, String pin) =>
      _setUser('producer', producerName, pin: pin);

  static Future<void> deleteProducerPin(String producerName) =>
      _removeUser('producer', producerName);

  static Future<List<String>> getProducersWithPins() => _listNames('producer');

  // ─── Consultant PINs ──────────────────────────────────────────────────────────

  static Future<String?> getConsultantPin(String name) =>
      _userField<String>('consultant', name, 'pin');

  static Future<void> setConsultantPin(String name, String pin) =>
      _setUser('consultant', name, pin: pin);

  static Future<void> deleteConsultantPin(String name) =>
      _removeUser('consultant', name);

  static Future<List<String>> getConsultantsWithPins() =>
      _listNames('consultant');

  // ─── Organizer PINs ───────────────────────────────────────────────────────────

  static Future<String?> getOrganizerPin(String name) =>
      _userField<String>('organizer', name, 'pin');

  static Future<void> setOrganizerPin(String name, String pin) =>
      _setUser('organizer', name, pin: pin);

  static Future<void> deleteOrganizerPin(String name) =>
      _removeUser('organizer', name);

  /// Feiras vinculadas a esta organizadora.
  ///
  /// Só a gestão passa por aqui. O portal da organizadora recebe as feiras já
  /// no retorno do login (`verifyPin`) e, quando precisa redescobri-las, usa
  /// `PinService.listUsers`, que não devolve PIN nenhum.
  static Future<List<int>> getOrganizerFairIds(String name) async {
    final list = await _userField<List>('organizer', name, 'fairIds');
    if (list != null) return organizerFairIdsFrom(list, null);
    // Cadastro antigo, de uma feira só.
    return organizerFairIdsFrom(
        null, await _userField<Object>('organizer', name, 'fairId'));
  }

  /// Vincula a organizadora a um conjunto de feiras.
  ///
  /// `fairId` continua sendo gravado com a primeira da lista: os aparelhos que
  /// ainda não atualizaram leem só esse campo, e sem ele a organizadora
  /// perderia o vínculo até trocar de versão.
  static Future<void> setOrganizerFairIds(String name, List<int> ids) =>
      _setUser('organizer', name, extra: {
        'fairIds': ids,
        'fairId': ids.isEmpty ? null : ids.first,
      });

  static Future<List<String>> getOrganizersWithPins() =>
      _listNames('organizer');

  // ─── Team Leader PINs ───────────────────────────────────────────────────────

  static Future<String?> getTeamLeaderPin(String name) =>
      _userField<String>('leader', name, 'pin');

  static Future<String?> getTeamLeaderTeam(String name) =>
      _userField<String>('leader', name, 'team');

  static Future<void> setTeamLeaderPin(
          String name, String pin, String team) =>
      _setUser('leader', name, pin: pin, extra: {'team': team});

  static Future<void> deleteTeamLeaderPin(String name) =>
      _removeUser('leader', name);

  /// Returns list of {name, team} maps, sorted by name.
  static Future<List<Map<String, String>>> getTeamLeadersWithPins() async {
    final users = await _listUsers('leader');
    final list = users
        .map((u) => {
              'name': (u['name'] as String?) ?? '',
              'team': (u['team'] as String?) ?? '',
            })
        .where((e) => e['name']!.isNotEmpty)
        .toList();
    list.sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  // ─── Fairs ──────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFairs() async {
    final snapshot = await _db.collection('fairs').get();
    return snapshot.docs
        .map((d) => {'id': int.tryParse(d.id), ...d.data()})
        .toList();
  }

  /// Real-time stream of all fairs — used to sync mode changes across devices.
  static Stream<List<Map<String, dynamic>>> streamFairs() {
    return _db.collection('fairs').snapshots().map(
      (snap) => snap.docs
          .map((d) => {'id': int.tryParse(d.id), ...d.data()})
          .toList(),
    );
  }

  /// Updates derived (mestra_child) fair metadata WITHOUT touching the mode field,
  /// so that mode changes made via setFairMode() are preserved across syncs.
  static Future<void> saveDerivedFairMetadata(int id, String name,
      String spreadsheetId, String sheetName, String createdAt) async {
    try {
      await _db.collection('fairs').doc(id.toString()).set({
        'id': id,
        'name': name,
        'spreadsheetId': spreadsheetId,
        'sheetName': sheetName,
        'createdAt': createdAt,
        'sheetMode': 'mestra_child',
        // mode field intentionally omitted — preserved by setFairMode()
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> saveFair(int id, String name, String spreadsheetId,
      String sheetName, String createdAt,
      {String mode = 'producao', String sheetMode = 'individual'}) async {
    await _db.collection('fairs').doc(id.toString()).set({
      'name': name,
      'spreadsheetId': spreadsheetId,
      'sheetName': sheetName,
      'createdAt': createdAt,
      'mode': mode,
      'sheetMode': sheetMode,
    });
  }

  /// Reads a single fair document (used by the public stand web page).
  static Future<Map<String, dynamic>?> getFair(int id) async {
    final doc = await _db.collection('fairs').doc(id.toString()).get();
    if (!doc.exists) return null;
    return {'id': id, ...doc.data()!};
  }

  /// Updates only the operating mode of a fair (producao / manutencao).
  static Future<void> setFairMode(int id, String mode) async {
    await _db.collection('fairs').doc(id.toString()).set(
      {'mode': mode},
      SetOptions(merge: true),
    );
  }

  /// Liga/desliga a aprovação automática dos pedidos da organizadora numa
  /// feira. Fica no Firestore para valer em todos os dispositivos e também no
  /// portal web da organizadora.
  static Future<void> setFairAutoApprove(int id, bool value) async {
    await _db.collection('fairs').doc(id.toString()).set(
      {'autoApprove': value},
      SetOptions(merge: true),
    );
  }

  /// Remove a feira da nuvem.
  ///
  /// Deixa o erro subir de propósito: engolir aqui fazia a feira "excluída"
  /// voltar no próximo arranque, porque ela continuava na nuvem e ninguém
  /// ficava sabendo da falha.
  static Future<void> deleteFairFromCloud(int id) =>
      _db.collection('fairs').doc(id.toString()).delete();

  // ─── Feiras ignoradas ─────────────────────────────────────────────────────
  //
  // Excluir uma feira que vem da planilha mestra não adiantava: o sync lê a
  // coluna FEIRA e recria tudo o que estiver lá. A lista abaixo é o que faz a
  // exclusão durar, e fica na nuvem para valer em todos os aparelhos.

  static Future<Set<String>> getIgnoredFairKeys() async {
    final snap = await _db.collection('ignored_fairs').get();
    return snap.docs.map((d) => d.id).toSet();
  }

  static Future<List<Map<String, dynamic>>> getIgnoredFairs() async {
    final snap = await _db.collection('ignored_fairs').get();
    final list = snap.docs
        .map((d) => {'key': d.id, ...d.data()})
        .toList()
      ..sort((a, b) =>
          ((a['name'] as String?) ?? '').compareTo((b['name'] as String?) ?? ''));
    return list;
  }

  static Future<void> ignoreFair(String name, {String by = ''}) async {
    final key = fairKey(name);
    if (key.isEmpty) return;
    await _db.collection('ignored_fairs').doc(key).set({
      'name': name,
      'ignoredAt': DateTime.now().toIso8601String(),
      if (by.isNotEmpty) 'ignoredBy': by,
    });
  }

  static Future<void> unignoreFair(String key) =>
      _db.collection('ignored_fairs').doc(key).delete();

  static Future<void> archiveFairInCloud(int id, bool archived) async {
    try {
      final snap = await _db.collection('fairs').where('id', isEqualTo: id).limit(1).get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({'archived': archived});
      } else {
        // Also try by doc id directly
        await _db.collection('fairs').doc(id.toString()).set({'archived': archived}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  // ─── Client Specs ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getClientSpecs(String clientId) async {
    try {
      final doc = await _db.collection('client_specs').doc(clientId).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  // ─── Sync Events (new-client notifications) ──────────────────────────────────

  /// Writes a transient event document that triggers the `onNewClientSynced`
  /// Cloud Function, which sends FCM notifications to producer + consultant.
  static void writeSyncEvent({
    required String clientId,
    required String clientName,
    required String fairName,
    required String producerName,
    required String consultantName,
  }) {
    if (producerName.isEmpty && consultantName.isEmpty) return;
    // Id determinado pelo conteúdo: a função só dispara na CRIAÇÃO do
    // documento, então gravar de novo a mesma atribuição não notifica outra
    // vez. Antes cada aparelho que sincronizasse mandava a sua, e a mesma
    // atribuição virava três ou quatro notificações.
    final key = [
      fairKey(fairName),
      fairKey(clientId),
      fairKey(producerName),
      fairKey(consultantName),
    ].join('-');
    final ref = _db.collection('sync_events').doc(key);
    final payload = <String, dynamic>{
      'clientId': clientId,
      'clientName': clientName,
      'fairName': fairName,
      'producerName': producerName,
      'consultantName': consultantName,
      'createdAt': DateTime.now().toIso8601String(),
    };
    CloudWrites.fireAndForget(
      'aviso de novo cliente ($clientName)',
      () => ref.set(payload),
    );
  }

  /// Real-time stream of all pending items for a given fair name.
  static Stream<List<PendingItem>> streamPendingByFair(String fairName) {
    return _db
        .collection('pending_items')
        .where('fairName', isEqualTo: fairName)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PendingItem.fromFirestore(d.id, d.data()))
            .toList());
  }

  // ─── Manager PINs ────────────────────────────────────────────────────────────

  static Future<String?> getManagerPin(String name) =>
      _userField<String>('manager', name, 'pin');

  static Future<void> setManagerPin(String name, String pin) =>
      _setUser('manager', name, pin: pin);

  static Future<void> deleteManagerPin(String name) =>
      _removeUser('manager', name);

  static Future<List<String>> getManagersWithPins() => _listNames('manager');

  // ─── Analyst PINs ────────────────────────────────────────────────────────────

  static Future<String?> getAnalystPin(String name) =>
      _userField<String>('analyst', name, 'pin');

  static Future<void> setAnalystPin(String name, String pin) =>
      _setUser('analyst', name, pin: pin);

  static Future<void> deleteAnalystPin(String name) =>
      _removeUser('analyst', name);

  static Future<List<String>> getAnalystsWithPins() => _listNames('analyst');

  // ─── Spec Locking ─────────────────────────────────────────────────────────

  static Future<void> saveClientSpecs(
      String clientId, Map<String, dynamic> specs) async {
    await _db
        .collection('client_specs')
        .doc(clientId)
        .set(specs, SetOptions(merge: true));
  }

  static Future<void> lockClientSpecs(String clientId) async {
    await _db.collection('client_specs').doc(clientId).set(
      {'locked': true, 'lockedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  static Future<void> unlockClientSpecs(String clientId) async {
    await _db.collection('client_specs').doc(clientId).set(
      {'locked': false, 'editRequested': false},
      SetOptions(merge: true),
    );
  }

  /// Consultant requests permission to edit — sets editRequested flag and
  /// writes a spec_edit_requests doc so admins get notified via CF.
  static Future<void> requestSpecEdit(String clientId, String clientName,
      String fairName, String byName) async {
    await _db.collection('client_specs').doc(clientId).set(
      {'editRequested': true},
      SetOptions(merge: true),
    );
    final ref = _db.collection('spec_edit_requests').doc(clientId);
    final payload = <String, dynamic>{
      'clientId': clientId,
      'clientName': clientName,
      'fairName': fairName,
      'requestedBy': byName,
      'requestedAt': DateTime.now().toIso8601String(),
    };
    CloudWrites.fireAndForget(
      'pedido de edição de ficha ($clientName)',
      () => ref.set(payload),
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingSpecEditRequests() async {
    try {
      final snap = await _db.collection('spec_edit_requests').get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> approveSpecEditRequest(String clientId) async {
    await unlockClientSpecs(clientId);
    try {
      await _db.collection('spec_edit_requests').doc(clientId).delete();
    } catch (_) {}
  }

  /// Writes a spec_change_events doc → Cloud Function sends to `admins` topic.
  static void writeSpecChangeEvent({
    required String clientId,
    required String clientName,
    required String fairName,
    required String consultantName,
  }) {
    final payload = <String, dynamic>{
      'clientId': clientId,
      'clientName': clientName,
      'fairName': fairName,
      'consultantName': consultantName,
      'notifyTopic': 'admins',
      'createdAt': DateTime.now().toIso8601String(),
    };
    CloudWrites.fireAndForget(
      'aviso de alteração de ficha ($clientName)',
      () => _db.collection('spec_change_events').add(payload),
    );
  }

  // ─── Analyst Notes ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getAnalystNote(String clientId) async {
    try {
      final doc = await _db.collection('analyst_notes').doc(clientId).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAnalystNote(
      String clientId, String text, String link, String by) async {
    await _db.collection('analyst_notes').doc(clientId).set({
      'text': text,
      'link': link,
      'updatedBy': by,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  // ─── New Client Broadcast ─────────────────────────────────────────────────

  /// Writes to new_client_broadcasts → CF sends to `new_clients` FCM topic.
  /// Uses clientId as the stable document ID so the CF onCreate trigger only
  /// fires once per client, preventing duplicate notifications on every sync.
  static void writeNewClientBroadcast({
    required String clientId,
    required String clientName,
    required String fairName,
  }) {
    final ref = _db.collection('new_client_broadcasts').doc(clientId);
    final payload = <String, dynamic>{
      'clientId': clientId,
      'clientName': clientName,
      'fairName': fairName,
      'notifyTopic': 'new_clients',
      'createdAt': DateTime.now().toIso8601String(),
    };
    CloudWrites.fireAndForget(
      'aviso geral de novo cliente ($clientName)',
      () => ref.set(payload),
    );
  }

  // ─── Admin Users ──────────────────────────────────────────────────────────

  static Future<List<String>> getAdminUsers() => _listNames('admin');

  static Future<String?> getAdminUserPin(String name) =>
      _userField<String>('admin', name, 'pin');

  static Future<void> saveAdminUser(String name, String pin) =>
      _setUser('admin', name, pin: pin);

  static Future<void> deleteAdminUser(String name) =>
      _removeUser('admin', name);

  // ─── Avisos ───────────────────────────────────────────────────────────────

  static Future<void> writeAviso({
    required String title,
    required String body,
    required String createdBy,
    required List<String> targetGroups,
    String targetType = 'groups',
    List<Map<String, dynamic>> targetUsers = const [],
    String fairName = '',
  }) async {
    await _db.collection('avisos').add({
      'title': title,
      'body': body,
      'createdBy': createdBy,
      'targetGroups': targetGroups,
      'targetType': targetType,
      'targetUsers': targetUsers,
      // Guardado para a lista mostrar de qual feira era o aviso; quem recebe
      // é decidido pela lista de pessoas, resolvida no app.
      'fairName': fairName,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteAviso(String docId) async {
    await _db.collection('avisos').doc(docId).delete();
  }

  static Stream<List<Map<String, dynamic>>> streamAvisos() {
    return _db
        .collection('avisos')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList());
  }

  // ─── Espelho dos expositores ──────────────────────────────────────────────
  //
  // A planilha continua sendo a fonte da verdade: o financeiro consulta, o
  // pessoal preenche, e ela atravessa fases do processo que o app não cobre.
  // O que muda é que o resultado da leitura dela deixa de ficar preso ao
  // SQLite de quem sincronizou.
  //
  // Sem este espelho, todo aparelho só sabia dos expositores que ele mesmo
  // baixou. Daí vinham os bugs: "cliente novo" era novo só naquele celular,
  // "quem trabalha nesta feira" dependia de quem tinha sincronizado, e um
  // aparelho recém-instalado não via nada até alguém entrar como admin.
  //
  // A chave do documento é o firestoreId do cliente — a mesma usada em
  // client_status, para os dois lados casarem.

  static CollectionReference<Map<String, dynamic>> get _clientsCol =>
      _db.collection('fair_clients');

  /// Expositores de uma feira, direto da nuvem.
  ///
  /// [fairId] é o id LOCAL da feira neste aparelho: os documentos guardam o
  /// nome da feira, que é estável entre aparelhos, e os clientes voltam já
  /// reidentificados para o id daqui.
  static Future<List<Client>> getFairClients({
    required String fairName,
    required int fairId,
  }) async {
    final snap =
        await _clientsCol.where('fairName', isEqualTo: fairName).get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['fair_id'] = fairId;
      // row_id carrega o id da feira do aparelho que publicou; refaz com o
      // daqui para casar com o que as telas usam.
      final rowNum = (data['row_id'] as String? ?? '').split('_').last;
      data['row_id'] = '${fairId}_$rowNum';
      data['firestore_id'] = d.id;
      return Client.fromMap(data);
    }).toList();
  }

  /// Assinaturas do que já está publicado, por firestoreId.
  ///
  /// Serve para publicar só o que mudou. Uma leitura por sincronização custa
  /// muito menos do que reescrever a planilha inteira toda vez.
  static Future<Map<String, String>> getFairClientFingerprints(
      String fairName) async {
    final snap =
        await _clientsCol.where('fairName', isEqualTo: fairName).get();
    return {
      for (final d in snap.docs)
        d.id: (d.data()['fingerprint'] as String?) ?? '',
    };
  }

  /// Publica os expositores que mudaram e remove os que saíram da planilha.
  ///
  /// Devolve quantos foram gravados e quantos foram removidos.
  static Future<({int written, int removed})> publishFairClients({
    required String fairName,
    required List<Client> clients,
    required Map<String, String> knownFingerprints,
  }) async {
    final agora = DateTime.now().toIso8601String();
    final paraGravar = <Client, String>{};

    for (final c in clients) {
      if (c.firestoreId.isEmpty) continue;
      final fp = clientFingerprint(c);
      if (knownFingerprints[c.firestoreId] == fp) continue;
      paraGravar[c] = fp;
    }

    // Quem sumiu da planilha sai do espelho. Sem isto um expositor removido
    // continuaria aparecendo para sempre em quem lê pela nuvem.
    final vivos = clients.map((c) => c.firestoreId).toSet();
    final paraRemover =
        knownFingerprints.keys.where((id) => !vivos.contains(id)).toList();

    var gravados = 0;
    var removidos = 0;

    // Em lotes: o backfill dos check-offs já ensinou que centenas de
    // gravações soltas se perdem pelo caminho.
    Future<void> commit(List<void Function(WriteBatch)> ops) async {
      for (var i = 0; i < ops.length; i += 400) {
        final fim = (i + 400 < ops.length) ? i + 400 : ops.length;
        final batch = _db.batch();
        for (final op in ops.sublist(i, fim)) {
          op(batch);
        }
        await batch.commit();
      }
    }

    await commit([
      ...paraGravar.entries.map((e) => (WriteBatch b) {
            final data = Map<String, dynamic>.from(e.key.toMap())
              ..remove('is_completed')
              ..remove('completed_at')
              ..['fairName'] = fairName
              ..['fingerprint'] = e.value
              ..['updatedAt'] = agora;
            b.set(_clientsCol.doc(e.key.firestoreId), data);
            gravados++;
          }),
      ...paraRemover.map((id) => (WriteBatch b) {
            b.delete(_clientsCol.doc(id));
            removidos++;
          }),
    ]);

    return (written: gravados, removed: removidos);
  }

  // ─── Reuniões ─────────────────────────────────────────────────────────────

  static Future<String> createMeeting(Meeting m) async {
    final ref = await _db.collection('meetings').add(m.toFirestore());
    return ref.id;
  }

  static Future<void> cancelMeeting(String id) =>
      _db.collection('meetings').doc(id).set(
        {'canceled': true},
        SetOptions(merge: true),
      );

  /// Reuniões mais recentes primeiro. O limite existe para a tela não crescer
  /// sem fim; a filtragem por participante é feita no app.
  static Stream<List<Meeting>> streamMeetings() {
    return _db
        .collection('meetings')
        .orderBy('startsAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Meeting.fromFirestore(d.id, d.data())).toList());
  }

  // ─── Presence ─────────────────────────────────────────────────────────────

  static Future<void> updatePresence({
    required String name,
    required String role,
    required String team,
    required bool online,
  }) async {
    if (name.isEmpty && role.isEmpty) return;
    final key = '${role}_$name'
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    try {
      await _db.collection('presence').doc(key).set({
        'name': name,
        'role': role,
        'team': team,
        'online': online,
        'lastSeen': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> clearPresence(String name, String role) async {
    await updatePresence(name: name, role: role, team: '', online: false);
  }

  static Stream<List<Map<String, dynamic>>> streamPresence() {
    return _db
        .collection('presence')
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList());
  }

  // ─── Gallery ──────────────────────────────────────────────────────────────

  /// Returns all montage photos for [fairName] on [date] (e.g. "2026-06-15").
  static Future<List<Map<String, dynamic>>> getMontagePhotosByDate(
      String fairName, String date) async {
    try {
      final snap = await _db
          .collection('montage_updates')
          .where('fairName', isEqualTo: fairName)
          .get();
      return snap.docs
          .map((d) => d.data())
          .where((d) =>
              ((d['createdAt'] as String?) ?? '').startsWith(date))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Team ────────────────────────────────────────────────────────────────────

  static Future<List<PendingItem>> getPendingItemsByTeam(
      String team) async {
    final snapshot = await _db
        .collection('pending_items')
        .where('team', isEqualTo: team)
        .where('isResolved', isEqualTo: false)
        .get();
    final items = snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .toList();
    items.sort((a, b) {
      final h = a.hangar.compareTo(b.hangar);
      if (h != 0) return h;
      return a.local.compareTo(b.local);
    });
    return items;
  }

  // ─── Logistics Users ──────────────────────────────────────────────────────

  static Future<List<String>> getLogisticsUsers() => _listNames('logistica');

  static Future<String?> getLogisticsUserPin(String name) =>
      _userField<String>('logistica', name, 'pin');

  static Future<void> saveLogisticsUser(String name, String pin) =>
      _setUser('logistica', name, pin: pin);

  static Future<void> deleteLogisticsUser(String name) =>
      _removeUser('logistica', name);

  // ─── Freight Requests ─────────────────────────────────────────────────────

  static Future<void> createFreightRequest(FreightRequest req) async {
    final snap = await _db
        .collection('freight_requests')
        .where('fairId', isEqualTo: req.fairId)
        .get();
    final number = snap.docs.length + 1;
    await _db.collection('freight_requests').add({...req.toMap(), 'number': number});
  }

  static Stream<List<FreightRequest>> streamFreightRequests(int fairId) {
    Query q = _db.collection('freight_requests');
    if (fairId >= 0) q = q.where('fairId', isEqualTo: fairId);
    return q
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => FreightRequest.fromMap(d.id, d.data() as Map<String, dynamic>))
            .toList());
  }

  static Future<void> updateFreightRequestStatus(
      String id, String status, String handledBy,
      {String note = '', String photoUrl = ''}) async {
    final now = DateTime.now().toIso8601String();
    final update = <String, dynamic>{'status': status, 'handledBy': handledBy};
    if (note.isNotEmpty) update['statusNote'] = note;
    if (status == 'agendado') update['scheduledAt'] = now;
    if (status == 'despachado') update['dispatchedAt'] = now;
    if (status == 'finalizado') {
      update['finalizedAt'] = now;
      if (photoUrl.isNotEmpty) update['receiptPhotoUrl'] = photoUrl;
    }
    await _db.collection('freight_requests').doc(id).update(update);
  }

  static Future<void> deleteFreightRequest(String id) async {
    await _db.collection('freight_requests').doc(id).delete();
  }

  static Future<List<FreightRequest>> getFreightRequestsForReport(int fairId) async {
    final snap = await _db
        .collection('freight_requests')
        .where('fairId', isEqualTo: fairId)
        .where('status', isEqualTo: 'finalizado')
        .get();
    return snap.docs
        .map((d) => FreightRequest.fromMap(d.id, d.data() as Map<String, dynamic>))
        .toList();
  }

  // ─── Status de conclusão dos stands (compartilhado entre dispositivos) ───────
  //
  // O check-off de um stand era gravado apenas no SQLite local, então cada
  // aparelho enxergava um total diferente de "concluídos". Estes métodos
  // publicam o status na nuvem para que todos os usuários vejam o mesmo número.

  /// Marks (or unmarks) a client/stand as completed in the shared cloud state.
  /// Document id is the client's stable cross-device key (firestoreId).
  static Future<void> setClientCompleted({
    required String clientFirestoreId,
    required int fairId,
    required bool completed,
    DateTime? completedAt,
    String completedBy = '',
    String fairName = '',
  }) async {
    if (clientFirestoreId.isEmpty) return;
    await _db.collection('client_status').doc(clientFirestoreId).set({
      'fairId': fairId,
      'fairName': fairName,
      'completed': completed,
      'completedAt': completed
          ? (completedAt ?? DateTime.now()).toIso8601String()
          : null,
      'completedBy': completedBy,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Publishes many completion records at once using batched writes.
  ///
  /// The backfill used to fire one unawaited set() per stand; with a few
  /// hundred stands the call returned while most writes were still in flight
  /// and anything not yet flushed was lost when the app was backgrounded.
  /// Batches are awaited, so when this future completes the data is really on
  /// the server. Firestore caps a batch at 500 operations.
  static Future<void> backfillClientCompletions(
    List<ClientCompletionRecord> records, {
    required int fairId,
    String fairName = '',
  }) async {
    const chunkSize = 450;
    for (var i = 0; i < records.length; i += chunkSize) {
      final end = (i + chunkSize < records.length) ? i + chunkSize : records.length;
      final batch = _db.batch();
      for (final r in records.sublist(i, end)) {
        if (r.clientFirestoreId.isEmpty) continue;
        batch.set(
          _db.collection('client_status').doc(r.clientFirestoreId),
          {
            'fairId': fairId,
            'fairName': fairName,
            'completed': true,
            'completedAt':
                (r.completedAt ?? DateTime.now()).toIso8601String(),
            'completedBy': r.completedBy,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  /// Returns the shared completion status for every client of a fair,
  /// keyed by the client's firestoreId.
  static Future<Map<String, ClientStatus>> getClientStatuses(int fairId) async {
    final snap = await _db
        .collection('client_status')
        .where('fairId', isEqualTo: fairId)
        .get();
    final result = <String, ClientStatus>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      result[doc.id] = ClientStatus(
        completed: data['completed'] == true,
        completedAt: data['completedAt'] is String
            ? DateTime.tryParse(data['completedAt'] as String)
            : null,
        completedBy: (data['completedBy'] as String?) ?? '',
      );
    }
    return result;
  }
}

/// One stand to publish during a completion backfill.
class ClientCompletionRecord {
  final String clientFirestoreId;
  final DateTime? completedAt;
  final String completedBy;

  const ClientCompletionRecord({
    required this.clientFirestoreId,
    this.completedAt,
    this.completedBy = '',
  });
}

/// Shared (cloud) completion status of a single stand.
class ClientStatus {
  final bool completed;
  final DateTime? completedAt;
  final String completedBy;

  const ClientStatus({
    required this.completed,
    this.completedAt,
    this.completedBy = '',
  });
}
