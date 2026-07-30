import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/directory_service.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../widgets/user_picker.dart';

class CircularComposeScreen extends StatefulWidget {
  const CircularComposeScreen({super.key});

  @override
  State<CircularComposeScreen> createState() =>
      _CircularComposeScreenState();
}

class _CircularComposeScreenState extends State<CircularComposeScreen> {
  static const _navy = Color(0xFF1E3A5F);

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;
  String _authorName = '';

  static const _allGroups = [
    ('todos', 'Todos os usuários'),
    ('produtores', 'Produtores'),
    ('consultores', 'Consultores'),
    ('lideres', 'Líderes'),
    ('analistas', 'Analistas'),
    ('admins', 'Admins / Gerentes'),
    ('logistica', 'Logística'),
  ];

  final Set<String> _selected = {'todos'};

  /// 'groups' | 'users' | 'fair'
  String _targetType = 'groups';

  List<AppUser> _allUsers = [];
  final Set<String> _selectedUserKeys = {};
  bool _loadingUsers = false;
  bool _usersFailed = false;

  // Por feira
  Fair? _fair;
  List<AppUser> _fairAudience = [];
  bool _loadingAudience = false;
  String? _audienceWarning;

  @override
  void initState() {
    super.initState();
    SessionService.get().then((s) {
      if (mounted) setState(() => _authorName = s?['name'] ?? 'Admin');
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _toggleGroup(String key) {
    setState(() {
      if (key == 'todos') {
        _selected.clear();
        _selected.add('todos');
      } else {
        _selected.remove('todos');
        if (_selected.contains(key)) {
          _selected.remove(key);
          if (_selected.isEmpty) _selected.add('todos');
        } else {
          _selected.add(key);
        }
      }
    });
  }

  /// Carrega TODO mundo que existe no app.
  ///
  /// A lista vinha da coleção de presença, que só tem quem abriu o app há
  /// pouco: quem estava com o celular no bolso não aparecia para ser
  /// escolhido, que é justamente quem mais precisa do aviso.
  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    final r = await DirectoryService.all();
    if (!mounted) return;
    setState(() {
      _allUsers = r.users;
      _usersFailed = r.failed;
      _loadingUsers = false;
    });
  }

  /// Monta a plateia de uma feira: quem trabalha nela, mais analistas,
  /// gerentes e admins, que entram sempre.
  Future<void> _loadFairAudience(Fair fair) async {
    setState(() {
      _fair = fair;
      _loadingAudience = true;
      _audienceWarning = null;
    });

    if (_allUsers.isEmpty) await _loadUsers();
    if (!mounted) return;
    final everyone = _allUsers;

    // A feira pode não ter sido sincronizada neste aparelho. O espelho da
    // nuvem preenche, para o aviso não sair sem metade da equipe.
    await context.read<AppProvider>().ensureFairClients(fair);
    final campo = await DatabaseService.getFairAudience(fair.id!);
    final selecionados = <AppUser>[
      ...DirectoryService.match(everyone, 'producer', campo.producers),
      ...DirectoryService.match(everyone, 'consultant', campo.consultants),
      ...DirectoryService.match(everyone, 'leader', campo.leaders),
      ...everyone
          .where((u) => DirectoryService.alwaysIncluded.contains(u.role)),
    ];

    // Sem repetir: um mesmo nome pode aparecer em mais de uma coluna.
    final porChave = {for (final u in selecionados) u.key: u};

    // Quem está na planilha mas não tem cadastro no app não recebe nada. É
    // melhor dizer isso do que deixar a pessoa de fora em silêncio.
    final semCadastro = <String>[
      ...campo.producers.where((n) =>
          DirectoryService.match(everyone, 'producer', [n]).isEmpty),
      ...campo.consultants.where((n) =>
          DirectoryService.match(everyone, 'consultant', [n]).isEmpty),
      ...campo.leaders.where((n) =>
          DirectoryService.match(everyone, 'leader', [n]).isEmpty),
    ];

    if (!mounted) return;
    setState(() {
      _fairAudience = porChave.values.toList();
      _selectedUserKeys
        ..clear()
        ..addAll(porChave.keys);
      _loadingAudience = false;
      final avisos = <String>[];
      if (semCadastro.isNotEmpty) {
        avisos.add('Sem cadastro no app, não receberão: '
            '${semCadastro.toSet().join(", ")}.');
      }
      if (campo.producers.isEmpty &&
          campo.consultants.isEmpty &&
          campo.leaders.isEmpty) {
        avisos.add('Ninguém de campo foi encontrado para esta feira, nem '
            'aqui nem na nuvem. Sincronize a planilha e tente de novo.');
      }
      _audienceWarning = avisos.isEmpty ? null : avisos.join('\n');
    });
  }

  List<AppUser> get _pickerUsers =>
      _targetType == 'fair' ? _fairAudience : _allUsers;

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Informe o título do aviso.');
      return;
    }
    if (_targetType == 'fair' && _fair == null) {
      _snack('Escolha a feira do aviso.');
      return;
    }
    final dirigido = _targetType == 'users' || _targetType == 'fair';
    final escolhidos = _pickerUsers
        .where((u) => _selectedUserKeys.contains(u.key))
        .toList();
    if (dirigido && escolhidos.isEmpty) {
      _snack('Escolha pelo menos uma pessoa.');
      return;
    }

    setState(() => _sending = true);
    try {
      await FirestoreService.writeAviso(
        title: title,
        body: body,
        createdBy: _authorName,
        targetType: _targetType,
        targetGroups: dirigido ? [] : _selected.toList(),
        targetUsers: escolhidos.map((u) => u.toMap()).toList(),
        fairName: _targetType == 'fair' ? (_fair?.name ?? '') : '',
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Aviso enviado com sucesso!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        _snack('Erro ao enviar: $e');
      }
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final fairs = context.watch<AppProvider>().fairs
        .where((f) => f.id != null && !f.isMestra)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Novo Aviso',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _sending
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _send,
                  child: const Text('Enviar',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Label('Título'),
            const SizedBox(height: 6),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: _input('Ex: Reunião amanhã às 9h'),
            ),
            const SizedBox(height: 20),
            const _Label('Mensagem'),
            const SizedBox(height: 6),
            TextField(
              controller: _bodyCtrl,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: _input('Escreva o conteúdo do aviso...'),
            ),
            const SizedBox(height: 20),
            const _Label('Enviar para'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _chip('Por grupo', 'groups'),
                _chip('Por feira', 'fair'),
                _chip('Por usuário', 'users'),
              ],
            ),
            const SizedBox(height: 12),
            if (_targetType == 'groups') _groupsCard(),
            if (_targetType == 'fair') _fairCard(fairs),
            if (_targetType == 'users') _usersCard(),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_sending ? 'Enviando...' : 'Publicar Aviso'),
                onPressed: _sending ? null : _send,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _chip(String label, String value) => ChoiceChip(
        label: Text(label),
        selected: _targetType == value,
        selectedColor: _navy,
        labelStyle: TextStyle(
          color: _targetType == value ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
        onSelected: (_) {
          setState(() => _targetType = value);
          if (value != 'groups' && _allUsers.isEmpty) _loadUsers();
        },
      );

  Widget _card(Widget child) => Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      );

  Widget _groupsCard() => Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: _allGroups.map((entry) {
            return CheckboxListTile(
              dense: true,
              title: Text(entry.$2, style: const TextStyle(fontSize: 14)),
              value: _selected.contains(entry.$1),
              activeColor: _navy,
              onChanged: (_) => _toggleGroup(entry.$1),
            );
          }).toList(),
        ),
      );

  Widget _fairCard(List<Fair> fairs) => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              value: _fair?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Feira',
                prefixIcon: Icon(Icons.event_outlined),
                isDense: true,
              ),
              items: fairs
                  .map((f) => DropdownMenuItem<int>(
                        value: f.id,
                        child: Text(f.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (id) {
                final f = fairs.where((e) => e.id == id).toList();
                if (f.isNotEmpty) _loadFairAudience(f.first);
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Vai para quem trabalha nesta feira — produtores, consultores e '
              'líderes — mais analistas, gerentes e admins, que entram sempre. '
              'Dá para desmarcar quem não precisa.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (_audienceWarning != null) ...[
              const SizedBox(height: 8),
              Text(_audienceWarning!,
                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ],
            const SizedBox(height: 8),
            if (_loadingAudience)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_fair == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Escolha a feira para ver quem será avisado.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              UserPicker(
                users: _fairAudience,
                selectedKeys: _selectedUserKeys,
                onChanged: (s) => setState(() {
                  _selectedUserKeys
                    ..clear()
                    ..addAll(s);
                }),
                lockedRoles: DirectoryService.alwaysIncluded.toSet(),
                lockedReason:
                    'Analistas, gerentes e admins recebem sempre e não podem '
                    'ser desmarcados.',
              ),
          ],
        ),
      );

  Widget _usersCard() => _card(
        _loadingUsers
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_usersFailed)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Parte da lista não carregou. Confira a conexão — '
                        'alguém pode ficar de fora do aviso.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ),
                  UserPicker(
                    users: _allUsers,
                    selectedKeys: _selectedUserKeys,
                    onChanged: (s) => setState(() {
                      _selectedUserKeys
                        ..clear()
                        ..addAll(s);
                    }),
                  ),
                ],
              ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E3A5F),
          fontSize: 13));
}
