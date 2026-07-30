import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../services/firestore_service.dart';
import '../services/sheets_service.dart';
import '../utils/web_portal.dart';
import '../widgets/pending_status.dart';
import '../widgets/resolution_dialog.dart';

/// Portal web para consultor e líder — mesmo nível de acesso e de ação do app
/// Android, para quem usa iPhone.
///
/// Lê tudo do Firestore (e os clientes da planilha), sem SQLite: é o mesmo
/// padrão já provado pelo portal da organizadora, e serve de piloto para a
/// migração da camada de dados.
///
/// A única diferença em relação ao Android é a notificação: iOS não recebe
/// push aqui. No lugar há o sino, que conta em tempo real enquanto a página
/// estiver aberta.
class TeamWebScreen extends StatefulWidget {
  final int? fairId; // vindo de ?f= na URL
  const TeamWebScreen({super.key, this.fairId});

  @override
  State<TeamWebScreen> createState() => _TeamWebScreenState();
}

enum _Step { loading, identify, pickFair, home, error }

enum _Role { consultor, lider }

enum _Filter { atencao, andamento, aguardando, concluidas, todas }

class _TeamWebScreenState extends State<TeamWebScreen> {
  static const _navy = Color(0xFF1E3A5F);
  static const _kRole = 'team_web_role';
  static const _kName = 'team_web_name';
  static const _kTeam = 'team_web_team';
  static const _kFairId = 'team_web_fair';

  static final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  _Step _step = _Step.loading;
  String _errorMsg = '';

  _Role? _role;
  String? _name;
  String _team = '';

  List<String> _consultants = [];
  List<Map<String, String>> _leaders = [];

  final _pinCtrl = TextEditingController();
  String? _pinError;
  bool _busy = false;

  List<Fair> _fairs = [];
  Fair? _fair;

  List<Client> _clients = [];
  final Map<int, List<Client>> _clientCache = {};
  List<PendingItem> _items = [];
  StreamSubscription? _sub;

  _Filter _filter = _Filter.atencao;

  /// Aba: 0 = pendências, 1 = stands. O consultor precisa da lista de
  /// expositores, não só do fluxo de pendências.
  int _tab = 0;
  Client? _openClient;

  /// Quantidade que já estava na tela; serve para destacar o que chegou depois.
  int _seenCount = 0;
  int _newSinceOpen = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pinCtrl.dispose();
    super.dispose();
  }

  // ── Identificação ─────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    try {
      _consultants = await FirestoreService.getConsultantsWithPins();
      _leaders = await FirestoreService.getTeamLeadersWithPins();

      final prefs = await SharedPreferences.getInstance();
      final savedRole = prefs.getString(_kRole);
      final savedName = prefs.getString(_kName);
      if (savedRole != null && savedName != null && savedName.isNotEmpty) {
        final role = savedRole == 'lider' ? _Role.lider : _Role.consultor;
        final known = role == _Role.consultor
            ? _consultants.contains(savedName)
            : _leaders.any((l) => l['name'] == savedName);
        if (known) {
          _role = role;
          _name = savedName;
          _team = prefs.getString(_kTeam) ?? '';
          await _loadFairs(prefs.getInt(_kFairId));
          return;
        }
      }
      _setStep(_Step.identify);
    } catch (e) {
      _fail('Não foi possível carregar. Verifique sua conexão.\n\n$e');
    }
  }

  Future<void> _verifyPin() async {
    if (_name == null) return;
    setState(() {
      _busy = true;
      _pinError = null;
    });
    try {
      final saved = _role == _Role.consultor
          ? await FirestoreService.getConsultantPin(_name!)
          : await FirestoreService.getTeamLeaderPin(_name!);
      if (saved == null || saved.isEmpty) {
        setState(() {
          _busy = false;
          _pinError = 'PIN não configurado. Fale com o administrador.';
        });
        return;
      }
      if (_pinCtrl.text.trim() != saved) {
        setState(() {
          _busy = false;
          _pinError = 'PIN incorreto.';
          _pinCtrl.clear();
        });
        return;
      }

      if (_role == _Role.lider) {
        _team = await FirestoreService.getTeamLeaderTeam(_name!) ?? '';
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRole, _role == _Role.lider ? 'lider' : 'consultor');
      await prefs.setString(_kName, _name!);
      await prefs.setString(_kTeam, _team);
      // Marca o portal para o F5 na URL nua voltar para cá, e não para a
      // organizadora.
      await prefs.setString(kLastWebPortal, kPortalEquipe);

      FirestoreService.updatePresence(
        name: _name!,
        role: _role == _Role.lider ? 'leader' : 'consultant',
        team: _team,
        online: true,
      ).catchError((_) {});

      if (!mounted) return;
      setState(() => _busy = false);
      await _loadFairs(widget.fairId ?? prefs.getInt(_kFairId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pinError = 'Erro ao verificar. Tente de novo.';
      });
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_kRole, _kName, _kTeam, _kFairId, kLastWebPortal]) {
      await prefs.remove(k);
    }
    _sub?.cancel();
    if (!mounted) return;
    setState(() {
      _role = null;
      _name = null;
      _team = '';
      _fair = null;
      _clients = [];
      _items = [];
      _openClient = null;
      _tab = 0;
      _pinCtrl.clear();
      _step = _Step.identify;
    });
  }

  // ── Feira e dados ─────────────────────────────────────────────────────────

  Fair _fairFrom(Map<String, dynamic> m) => Fair(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        spreadsheetId: (m['spreadsheetId'] as String?) ?? '',
        sheetName: (m['sheetName'] as String?) ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
            DateTime.now(),
        mode: (m['mode'] as String?) ?? 'producao',
        autoApprove: m['autoApprove'] == true,
      );

  Future<void> _loadFairs(int? preferredId) async {
    setState(() => _step = _Step.loading);
    try {
      final all = (await FirestoreService.getFairs())
          .map(_fairFrom)
          .where((f) =>
              f.id != null &&
              f.spreadsheetId.isNotEmpty &&
              f.sheetName.isNotEmpty)
          .toList();

      // Só as feiras em que a pessoa realmente tem stand. Sem esta varredura
      // a lista traz todas, inclusive as de outros atendimentos/equipes.
      // Os clientes ficam em cache para a feira abrir instantânea depois.
      final mine = <Fair>[];
      await Future.wait(all.map((f) async {
        try {
          final clients = await SheetsService.fetchClients(
            spreadsheetId: f.spreadsheetId,
            sheetName: f.sheetName,
            fairId: f.id!,
            fairName: f.name,
          );
          if (clients.any(_ownsClient)) {
            _clientCache[f.id!] = clients;
            mine.add(f);
          }
        } catch (_) {
          // Planilha indisponível: a feira fica de fora em vez de derrubar tudo.
        }
      }));
      mine.sort((a, b) => a.name.compareTo(b.name));
      _fairs = mine;

      if (_fairs.isEmpty) {
        _fail('Nenhum stand atribuído a você no momento.\n\n'
            'Verifique com a administração se o seu nome está na planilha.');
        return;
      }
      final preferred = _fairs.where((f) => f.id == preferredId).toList();
      if (preferred.isNotEmpty) {
        await _openFair(preferred.first);
      } else if (_fairs.length == 1) {
        await _openFair(_fairs.first);
      } else {
        _setStep(_Step.pickFair);
      }
    } catch (e) {
      _fail('Não foi possível carregar as feiras.\n\n$e');
    }
  }

  Future<void> _openFair(Fair f) async {
    setState(() {
      _fair = f;
      _step = _Step.loading;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kFairId, f.id!);

      _clients = _clientCache[f.id!] ??
          await SheetsService.fetchClients(
            spreadsheetId: f.spreadsheetId,
            sheetName: f.sheetName,
            fairId: f.id!,
            fairName: f.name,
          );
      _clientCache[f.id!] = _clients;

      _listenPendings(f.name);
      _setStep(_Step.home);
    } catch (e) {
      _fail('Não foi possível carregar os stands desta feira.\n\n$e');
    }
  }

  /// Escuta em tempo real: é o que faz o sino contar sem recarregar.
  void _listenPendings(String fairName) {
    _sub?.cancel();
    _seenCount = 0;
    _newSinceOpen = 0;
    _sub = FirestoreService.streamPendingByFair(fairName).listen((all) {
      if (!mounted) return;
      final mine = all.where(_isMine).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final attention = mine.where(_needsAttention).length;
      setState(() {
        _items = mine;
        if (_seenCount == 0) {
          _seenCount = attention;
        } else if (attention > _seenCount) {
          _newSinceOpen += attention - _seenCount;
          _seenCount = attention;
        } else {
          _seenCount = attention;
        }
      });
    }, onError: (_) {});
  }

  // ── Escopo: o que é "meu" ─────────────────────────────────────────────────

  /// Mesma regra do app Android (team_leader_client_list_screen): o líder
  /// enxerga onde é o responsável daquela equipe no stand. Vidraceiro e
  /// Comunicação Visual não têm coluna na planilha — ali o responsável é fixo,
  /// como no SQL do app.
  bool _leaderOwnsClient(Client c) {
    final n = (_name ?? '').toLowerCase().trim();
    switch (_team.toLowerCase().trim()) {
      case 'elétrica':
      case 'eletrica':
        return c.eletricista.toLowerCase().trim() == n;
      case 'limpeza':
        return c.faxineira.toLowerCase().trim() == n;
      case 'marcenaria':
        return c.marceneiro.toLowerCase().trim() == n;
      case 'tapeçaria':
      case 'tapecaria':
        return c.tapeceiro.toLowerCase().trim() == n;
      default:
        return true; // Vidraceiro / Comunicação Visual
    }
  }

  /// O stand é meu? Consultor pelo atendimento; líder pela coluna da equipe.
  bool _ownsClient(Client c) {
    if (_role == _Role.consultor) {
      return c.atendimento.toLowerCase().trim() ==
          (_name ?? '').toLowerCase().trim();
    }
    return _leaderOwnsClient(c);
  }

  List<Client> get _myClients {
    final list = _clients.where(_ownsClient).toList()
      ..sort((a, b) {
        final h = a.hangar.compareTo(b.hangar);
        if (h != 0) return h;
        return a.local.compareTo(b.local);
      });
    return list;
  }

  Set<String> get _myClientIds => _myClients.map((c) => c.rowId).toSet();

  bool _isMine(PendingItem i) {
    if (_role == _Role.lider) {
      // Líder só vê a própria equipe, e só onde é responsável.
      if (i.team.toLowerCase().trim() != _team.toLowerCase().trim()) {
        return false;
      }
      // Pedido da organizadora ainda não aprovado não vai para o campo.
      if (i.isPendingApproval || i.isRejected) return false;
      return _myClientIds.contains(i.clientId);
    }
    return _myClientIds.contains(i.clientId);
  }

  /// O que precisa de ação de quem está logado — é o número do sino.
  bool _needsAttention(PendingItem i) {
    if (_role == _Role.consultor) return i.isPendingApproval;
    return !i.isResolved && !i.awaitingValidation;
  }

  List<PendingItem> _itemsOf(Client c) =>
      _items.where((i) => i.clientId == c.rowId).toList();

  int _openCountOf(Client c) =>
      _itemsOf(c).where((i) => !i.isResolved).length;

  Client? _clientOf(PendingItem i) {
    for (final c in _clients) {
      if (c.rowId == i.clientId) return c;
    }
    return null;
  }

  // ── Ações ─────────────────────────────────────────────────────────────────

  Future<void> _approve(PendingItem i) async {
    final r = await showResolutionDialog(
      context,
      fairId: _fair!.id!,
      title: 'Aprovar pedido?',
      message: 'A pendência será liberada para o produtor e a equipe. A nota '
          'é opcional e fica visível para a organizadora e o expositor.',
      confirmLabel: 'Aprovar',
      allowPhotos: false,
    );
    if (r == null || !mounted) return;
    try {
      await FirestoreService.approveOrganizerItem(i.firestoreId!, note: r.note);
      _toast('Pedido aprovado.');
    } catch (_) {
      _toast('Falha ao aprovar. Tente de novo.', error: true);
    }
  }

  Future<void> _reject(PendingItem i) async {
    final r = await showResolutionDialog(
      context,
      fairId: _fair!.id!,
      title: 'Recusar pedido?',
      message: 'Explique o motivo. Ele fica visível para a organizadora e o '
          'expositor.',
      confirmLabel: 'Recusar',
      confirmColor: Colors.red,
      allowPhotos: false,
    );
    if (r == null || !mounted) return;
    if (r.note.trim().isEmpty) {
      _toast('Informe o motivo da recusa.', error: true);
      return;
    }
    try {
      await FirestoreService.rejectOrganizerItem(i.firestoreId!,
          reason: r.note, by: _name ?? '');
      _toast('Pedido recusado.');
    } catch (_) {
      _toast('Falha ao recusar. Tente de novo.', error: true);
    }
  }

  Future<void> _take(PendingItem i) async {
    try {
      await FirestoreService.markInProgress(i.firestoreId!, _name ?? '');
      _toast('Marcado como em andamento.');
    } catch (_) {
      _toast('Falha ao marcar. Tente de novo.', error: true);
    }
  }

  Future<void> _conclude(PendingItem i) async {
    final r = await showResolutionDialog(
      context,
      fairId: _fair!.id!,
      title: 'Marcar como concluída?',
      message: 'Vai para validação do administrador. A nota de manutenção e '
          'as fotos do serviço são opcionais e ficam visíveis para a '
          'organizadora e o expositor.',
      confirmLabel: 'Concluir',
    );
    if (r == null || !mounted) return;
    try {
      if (r.note.isNotEmpty || r.photoUrls.isNotEmpty) {
        await FirestoreService.setResolutionNote(i.firestoreId!,
            note: r.note, photoUrls: r.photoUrls);
      }
      await FirestoreService.markAwaitingValidation(i.firestoreId!);
      _toast('Concluída! Aguardando validação.');
    } catch (_) {
      _toast('Falha ao concluir. Tente de novo.', error: true);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setStep(_Step s) => setState(() => _step = s);
  void _fail(String m) => setState(() {
        _errorMsg = m;
        _step = _Step.error;
      });

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  List<PendingItem> _forFilter(_Filter f) {
    switch (f) {
      case _Filter.atencao:
        return _items.where(_needsAttention).toList();
      case _Filter.andamento:
        return _items
            .where((i) => i.inProgress && !i.isResolved && !i.awaitingValidation)
            .toList();
      case _Filter.aguardando:
        return _items
            .where((i) => i.awaitingValidation && !i.isResolved)
            .toList();
      case _Filter.concluidas:
        return _items.where((i) => i.isResolved && !i.isRejected).toList();
      case _Filter.todas:
        return _items;
    }
  }

  List<PendingItem> get _visible => _forFilter(_filter);

  int _countOf(_Filter f) => _forFilter(f).length;

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.loading:
        return const Center(child: CircularProgressIndicator());
      case _Step.error:
        return _message(Icons.error_outline, Colors.red, 'Ops!', _errorMsg);
      case _Step.identify:
        return _identifyView();
      case _Step.pickFair:
        return _pickFairView();
      case _Step.home:
        if (_openClient != null) return _clientView(_openClient!);
        return _homeView();
    }
  }

  Widget _message(IconData icon, Color color, String title, String msg) =>
      Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 72, color: color),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ]),
      );

  Widget _header({String? subtitle, VoidCallback? onBack}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new, size: 15),
                label: const Text('Voltar'),
                style: TextButton.styleFrom(foregroundColor: _navy),
              ),
            ),
          const SizedBox(height: 4),
          const Text('MONTAGEM USET',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                  letterSpacing: 1)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          const SizedBox(height: 12),
        ],
      );

  Widget _identifyView() {
    final names = _role == _Role.consultor
        ? _consultants
        : _leaders.map((l) => l['name'] ?? '').where((n) => n.isNotEmpty).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        _header(subtitle: 'Acesso da equipe'),
        if (_role == null) ...[
          const SizedBox(height: 8),
          const Text('Quem é você?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _roleCard(_Role.consultor, 'Consultor / Atendimento',
              Icons.support_agent, const Color(0xFF00897B)),
          const SizedBox(height: 10),
          _roleCard(_Role.lider, 'Líder de equipe', Icons.engineering,
              const Color(0xFFF57C00)),
        ] else if (_name == null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _role = null),
              icon: const Icon(Icons.arrow_back_ios_new, size: 15),
              label: const Text('Trocar perfil'),
              style: TextButton.styleFrom(foregroundColor: _navy),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Selecione seu nome',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (names.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nenhum acesso configurado para este perfil. '
                'Peça ao administrador para cadastrar o PIN.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ...names.map((n) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  title: Text(n,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => _name = n),
                ),
              )),
        ] else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _name = null;
                _pinCtrl.clear();
                _pinError = null;
              }),
              icon: const Icon(Icons.arrow_back_ios_new, size: 15),
              label: const Text('Trocar nome'),
              style: TextButton.styleFrom(foregroundColor: _navy),
            ),
          ),
          const SizedBox(height: 8),
          Text(_name!,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            obscureText: true,
            enabled: !_busy,
            onSubmitted: (_) => _verifyPin(),
            decoration: InputDecoration(
              labelText: 'PIN de acesso',
              errorText: _pinError,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _verifyPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Entrar',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _roleCard(_Role role, String label, IconData icon, Color color) =>
      Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withOpacity(0.35))),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color),
          ),
          title: Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _role = role),
        ),
      );

  Widget _pickFairView() => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          _header(subtitle: 'Selecione a feira'),
          ..._fairs.map((f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: const Icon(Icons.festival, color: _navy),
                  title: Text(f.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openFair(f),
                ),
              )),
        ]),
      );

  Widget _homeView() {
    final attention = _items.where(_needsAttention).length;
    final list = _visible;

    return Column(children: [
      // Cabeçalho com sino
      Container(
        color: _navy,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text(
                  '${_role == _Role.lider ? _team : "Atendimento"}'
                  ' · ${_fair?.name ?? ""}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 12),
                ),
              ],
            ),
          ),
          _bell(attention),
          IconButton(
            tooltip: 'Trocar feira',
            onPressed: () => _setStep(_Step.pickFair),
            icon: const Icon(Icons.swap_horiz, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
          ),
        ]),
      ),

      // Abas
      Container(
        color: Colors.white,
        child: Row(children: [
          _tabButton(0, 'Pendências', Icons.assignment_late),
          _tabButton(1, 'Stands', Icons.storefront),
        ]),
      ),

      if (_tab == 0) ...[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('Precisa de ação', _Filter.atencao, Colors.deepOrange),
                _chip('Em andamento', _Filter.andamento, Colors.deepPurple),
                _chip('Aguardando validação', _Filter.aguardando,
                    Colors.amber.shade800),
                _chip('Concluídas', _Filter.concluidas, Colors.green),
                _chip('Todas', _Filter.todas, _navy),
              ],
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _message(Icons.check_circle_outline, Colors.green.shade300,
                  'Nada por aqui', 'Nenhuma pendência neste filtro.')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _card(list[i]),
                ),
        ),
      ] else
        Expanded(child: _standsView()),
    ]);
  }

  Widget _tabButton(int index, String label, IconData icon) {
    final sel = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: sel ? Colors.orange : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: sel ? _navy : Colors.grey),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: sel ? _navy : Colors.grey)),
          ]),
        ),
      ),
    );
  }

  /// Lista de expositores sob responsabilidade de quem está logado — é o que
  /// o consultor usa para navegar por stand, e não só pela fila de pendências.
  Widget _standsView() {
    final clients = _myClients;
    if (clients.isEmpty) {
      return _message(Icons.storefront, Colors.grey,
          'Nenhum stand', 'Você não tem stands nesta feira.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: clients.length,
      itemBuilder: (_, i) {
        final c = clients[i];
        final open = _openCountOf(c);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _openClient = c),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _navy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(c.local.isEmpty ? '—' : c.local,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _navy)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (c.montagem.isNotEmpty)
                        Text(c.montagem,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                      if (c.hangar.isNotEmpty)
                        Text('Hangar ${c.hangar}',
                            style: const TextStyle(
                                color: _navy,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (open > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$open',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _clientView(Client c) {
    final items = _itemsOf(c)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(children: [
      Container(
        color: _navy,
        padding: const EdgeInsets.fromLTRB(8, 10, 16, 14),
        child: Row(children: [
          IconButton(
            onPressed: () => setState(() => _openClient = null),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Voltar',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.displayName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17)),
                Text(
                  [
                    if (c.local.isNotEmpty) 'Stand ${c.local}',
                    if (c.hangar.isNotEmpty) 'Hangar ${c.hangar}',
                    if (c.area.isNotEmpty) '${c.area} m²',
                  ].join(' · '),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 12),
                ),
              ],
            ),
          ),
        ]),
      ),
      // Responsáveis, para o consultor saber a quem recorrer sem sair da tela.
      Container(
        color: Colors.white,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          if (c.produtor.isNotEmpty) _resp('Produtor', c.produtor),
          if (c.atendimento.isNotEmpty) _resp('Atendimento', c.atendimento),
          if (c.marceneiro.isNotEmpty) _resp('Marcenaria', c.marceneiro),
          if (c.eletricista.isNotEmpty) _resp('Elétrica', c.eletricista),
          if (c.tapeceiro.isNotEmpty) _resp('Tapeçaria', c.tapeceiro),
          if (c.faxineira.isNotEmpty) _resp('Limpeza', c.faxineira),
        ]),
      ),
      Expanded(
        child: items.isEmpty
            ? _message(Icons.check_circle_outline, Colors.green.shade300,
                'Sem pendências', 'Este stand não tem chamados registrados.')
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (_, i) => _card(items[i]),
              ),
      ),
    ]);
  }

  Widget _resp(String label, String name) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _navy.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _navy.withOpacity(0.15)),
        ),
        child: Text('$label: $name',
            style: const TextStyle(fontSize: 11, color: _navy)),
      );

  Widget _bell(int count) => Stack(clipBehavior: Clip.none, children: [
        IconButton(
          tooltip: _newSinceOpen > 0
              ? '$_newSinceOpen nova(s) desde que você abriu'
              : '$count aguardando sua ação',
          onPressed: () => setState(() {
            _filter = _Filter.atencao;
            _newSinceOpen = 0;
          }),
          icon: Icon(
            _newSinceOpen > 0
                ? Icons.notifications_active
                : Icons.notifications_none,
            color: _newSinceOpen > 0 ? Colors.amber : Colors.white,
          ),
        ),
        if (count > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _newSinceOpen > 0 ? Colors.red : Colors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ]);

  Widget _chip(String label, _Filter f, Color color) {
    final sel = _filter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: sel ? color : color.withOpacity(0.35)),
          ),
          child: Text('$label (${_countOf(f)})',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : color)),
        ),
      ),
    );
  }

  Widget _card(PendingItem i) {
    final client = _clientOf(i);
    final canApprove = _role == _Role.consultor && i.isPendingApproval;
    final canWork = _role == _Role.lider && !i.isResolved && !i.awaitingValidation;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              PendingStatusBadge(item: i, fontSize: 12),
              const Spacer(),
              Text(
                'Stand ${i.local}'
                '${i.hangar.isNotEmpty ? " · H${i.hangar}" : ""}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              '${i.team} — ${client?.displayName ?? i.clientName}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(i.description, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            Text('Aberta: ${_fmt.format(i.createdAt)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (i.inProgress && i.inProgressBy.isNotEmpty)
              Text('Em andamento por ${i.inProgressBy}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.deepPurple.shade600,
                      fontWeight: FontWeight.w600)),
            PendingNotes(item: i, compact: true),
            if (canApprove || canWork) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (canApprove) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reject(i),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Recusar'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approve(i),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Aprovar'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white),
                    ),
                  ),
                ],
                if (canWork) ...[
                  if (!i.inProgress) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _take(i),
                        icon: const Icon(Icons.engineering, size: 16),
                        label: const Text('Peguei!'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.deepPurple),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _conclude(i),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Concluir'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
