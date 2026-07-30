import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/fair.dart';
import '../models/meeting.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/directory_service.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../widgets/user_picker.dart';

/// Agenda uma reunião.
///
/// A reunião é sempre de uma feira: é o que dá contexto a quem recebe o
/// convite e o que permite sugerir de cara quem trabalha nela.
class MeetingComposeScreen extends StatefulWidget {
  const MeetingComposeScreen({super.key});

  @override
  State<MeetingComposeScreen> createState() => _MeetingComposeScreenState();
}

class _MeetingComposeScreenState extends State<MeetingComposeScreen> {
  static const _navy = Color(0xFF1E3A5F);

  final _titleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  Fair? _fair;
  DateTime? _date;
  TimeOfDay? _time;

  List<AppUser> _allUsers = [];
  final Set<String> _selectedKeys = {};
  bool _loadingUsers = true;
  bool _usersFailed = false;
  String? _audienceWarning;

  String _authorName = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    SessionService.get().then((s) {
      if (mounted) setState(() => _authorName = s?['name'] ?? '');
    });
    _loadUsers();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final r = await DirectoryService.all();
    if (!mounted) return;
    setState(() {
      _allUsers = r.users;
      _usersFailed = r.failed;
      _loadingUsers = false;
    });
  }

  /// Ao escolher a feira, já marca quem trabalha nela. É sugestão: dá para
  /// desmarcar e para incluir qualquer outra pessoa.
  Future<void> _pickFair(Fair f) async {
    setState(() {
      _fair = f;
      _audienceWarning = null;
    });
    final campo = await DatabaseService.getFairAudience(f.id!);
    final sugeridos = <AppUser>[
      ...DirectoryService.match(_allUsers, 'producer', campo.producers),
      ...DirectoryService.match(_allUsers, 'consultant', campo.consultants),
      ...DirectoryService.match(_allUsers, 'leader', campo.leaders),
    ];
    if (!mounted) return;
    setState(() {
      _selectedKeys
        ..clear()
        ..addAll(sugeridos.map((u) => u.key));
      if (sugeridos.isEmpty) {
        _audienceWarning =
            'Ninguém de campo foi encontrado para esta feira neste aparelho. '
            'Sincronize a feira ou escolha os participantes na mão.';
      }
    });
  }

  DateTime? get _startsAt {
    if (_date == null || _time == null) return null;
    return DateTime(
        _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return _snack('Informe o assunto da reunião.');
    if (_fair == null) return _snack('Escolha a feira da reunião.');
    if (_startsAt == null) return _snack('Escolha a data e a hora.');
    if (_locationCtrl.text.trim().isEmpty) {
      return _snack('Informe o local da reunião.');
    }
    final participantes =
        _allUsers.where((u) => _selectedKeys.contains(u.key)).toList();
    if (participantes.isEmpty) {
      return _snack('Escolha pelo menos um participante.');
    }
    // O lembrete sai 30 minutos antes; marcar para daqui a 10 faria a reunião
    // nascer sem lembrete e sem aviso de que ele não viria.
    if (_startsAt!.isBefore(DateTime.now())) {
      return _snack('Essa data e hora já passaram.');
    }

    setState(() => _saving = true);
    try {
      await FirestoreService.createMeeting(Meeting(
        id: '',
        title: title,
        fairId: _fair!.id!,
        fairName: _fair!.name,
        location: _locationCtrl.text.trim(),
        startsAt: _startsAt!,
        createdBy: _authorName,
        createdAt: DateTime.now(),
        participants: participantes,
        notes: _notesCtrl.text.trim(),
      ));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Reunião agendada! Os participantes foram avisados.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Não foi possível agendar: $e');
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

    final quando = _startsAt == null
        ? null
        : DateFormat("EEEE, d 'de' MMMM 'às' HH:mm", 'pt_BR')
            .format(_startsAt!);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Agendar Reunião',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loadingUsers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('Assunto'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _input('Ex: Alinhamento de montagem'),
                  ),
                  const SizedBox(height: 18),
                  const _Label('Feira'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _fair?.id,
                    isExpanded: true,
                    decoration: _input('Escolha a feira').copyWith(
                        prefixIcon: const Icon(Icons.event_outlined)),
                    items: fairs
                        .map((f) => DropdownMenuItem<int>(
                              value: f.id,
                              child:
                                  Text(f.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (id) {
                      final f = fairs.where((e) => e.id == id).toList();
                      if (f.isNotEmpty) _pickFair(f.first);
                    },
                  ),
                  const SizedBox(height: 18),
                  const _Label('Quando'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(_date == null
                              ? 'Data'
                              : DateFormat('dd/MM/yyyy').format(_date!)),
                          onPressed: () async {
                            final now = DateTime.now();
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _date ?? now,
                              firstDate: now.subtract(const Duration(days: 1)),
                              lastDate: now.add(const Duration(days: 365)),
                            );
                            if (d != null) setState(() => _date = d);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                              _time == null ? 'Hora' : _time!.format(context)),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: _time ?? TimeOfDay.now(),
                            );
                            if (t != null) setState(() => _time = t);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (quando != null) ...[
                    const SizedBox(height: 6),
                    Text(quando,
                        style: const TextStyle(
                            fontSize: 12, color: _navy, fontWeight: FontWeight.w600)),
                    const Text(
                      'Os participantes recebem o convite agora e um lembrete '
                      '30 minutos antes.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const _Label('Local'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _locationCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _input('Ex: Sala de reunião do pavilhão azul')
                        .copyWith(
                            prefixIcon: const Icon(Icons.place_outlined)),
                  ),
                  const SizedBox(height: 18),
                  const _Label('Observações (opcional)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _input('Pauta, o que levar…'),
                  ),
                  const SizedBox(height: 18),
                  const _Label('Participantes'),
                  const SizedBox(height: 6),
                  if (_usersFailed)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Parte da lista não carregou. Confira a conexão — '
                        'alguém pode ficar de fora do convite.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ),
                  if (_audienceWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_audienceWarning!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange)),
                    ),
                  if (_fair != null)
                    const Text(
                      'Quem trabalha nesta feira já vem marcado. Dá para '
                      'desmarcar e para incluir qualquer outra pessoa.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  const SizedBox(height: 6),
                  Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: UserPicker(
                        users: _allUsers,
                        selectedKeys: _selectedKeys,
                        onChanged: (s) => setState(() {
                          _selectedKeys
                            ..clear()
                            ..addAll(s);
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.event_available),
                      label: Text(_saving ? 'Agendando…' : 'Agendar reunião'),
                      onPressed: _saving ? null : _save,
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
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
