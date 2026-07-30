import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/meeting.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import 'meeting_compose_screen.dart';

/// Agenda de reuniões.
///
/// Cada um vê as reuniões para as quais foi convidado. Quem agenda — gerente,
/// consultor ou admin — vê todas, porque precisa acompanhar o que marcou para
/// os outros.
class MeetingListScreen extends StatefulWidget {
  const MeetingListScreen({super.key});

  @override
  State<MeetingListScreen> createState() => _MeetingListScreenState();
}

class _MeetingListScreenState extends State<MeetingListScreen> {
  static const _navy = Color(0xFF1E3A5F);
  static const _podeAgendar = ['admin', 'manager', 'consultant'];

  String _name = '';
  String _role = '';
  bool _loading = true;
  bool _mostrarPassadas = false;

  @override
  void initState() {
    super.initState();
    SessionService.get().then((s) {
      if (!mounted) return;
      setState(() {
        _name = s?['name'] ?? '';
        _role = s?['role'] ?? '';
        _loading = false;
      });
    });
  }

  bool get _agenda => _podeAgendar.contains(_role);

  List<Meeting> _minhas(List<Meeting> todas) {
    final agora = DateTime.now();
    return todas.where((m) {
      if (m.canceled) return false;
      if (!_mostrarPassadas && m.startsAt.isBefore(agora)) return false;
      // Quem agenda acompanha tudo; os demais veem só o que lhes diz respeito.
      return _agenda || m.includes(_name, _role);
    }).toList()
      ..sort((a, b) => _mostrarPassadas
          ? b.startsAt.compareTo(a.startsAt)
          : a.startsAt.compareTo(b.startsAt));
  }

  Future<void> _cancelar(Meeting m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reunião?'),
        content: Text('Os ${m.participants.length} participantes serão '
            'avisados do cancelamento.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar reunião'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirestoreService.cancelMeeting(m.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Não foi possível cancelar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Agenda de Reuniões',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_mostrarPassadas ? Icons.history_toggle_off
                : Icons.history),
            tooltip: _mostrarPassadas ? 'Ver próximas' : 'Ver realizadas',
            onPressed: () =>
                setState(() => _mostrarPassadas = !_mostrarPassadas),
          ),
        ],
      ),
      floatingActionButton: _agenda
          ? FloatingActionButton.extended(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Agendar'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const MeetingComposeScreen()),
              ),
            )
          : null,
      body: StreamBuilder<List<Meeting>>(
        stream: FirestoreService.streamMeetings(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const _Aviso(
              icone: Icons.cloud_off,
              texto: 'Não foi possível carregar a agenda.\n'
                  'Confira a conexão e tente de novo.',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lista = _minhas(snap.data!);
          if (lista.isEmpty) {
            return _Aviso(
              icone: Icons.event_available,
              texto: _mostrarPassadas
                  ? 'Nenhuma reunião realizada.'
                  : _agenda
                      ? 'Nenhuma reunião marcada.\nToque em Agendar para criar.'
                      : 'Você não tem reuniões marcadas.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: lista.length,
            itemBuilder: (context, i) => _Card(
              meeting: lista[i],
              podeCancelar: _agenda && !lista[i].isPast,
              onCancel: () => _cancelar(lista[i]),
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Meeting meeting;
  final bool podeCancelar;
  final VoidCallback onCancel;

  const _Card({
    required this.meeting,
    required this.podeCancelar,
    required this.onCancel,
  });

  /// Quanto falta, em texto curto. Saber "em 2 horas" resolve mais rápido do
  /// que ler a data e fazer a conta.
  String get _quanto {
    final falta = meeting.startsAt.difference(DateTime.now());
    if (falta.isNegative) return 'realizada';
    if (falta.inMinutes < 60) return 'em ${falta.inMinutes} min';
    if (falta.inHours < 24) return 'em ${falta.inHours}h';
    return 'em ${falta.inDays} dia(s)';
  }

  @override
  Widget build(BuildContext context) {
    final quando = DateFormat("EEEE, d 'de' MMM 'às' HH:mm", 'pt_BR')
        .format(meeting.startsAt);
    final proxima = !meeting.isPast &&
        meeting.startsAt.difference(DateTime.now()).inHours < 24;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: proxima ? Colors.orange : const Color(0xFFE5E7EB),
          width: proxima ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(meeting.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: proxima
                        ? Colors.orange.withOpacity(0.15)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_quanto,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: proxima ? Colors.orange.shade900 : Colors.grey,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _linha(Icons.event_outlined, meeting.fairName),
            _linha(Icons.schedule, quando),
            if (meeting.location.isNotEmpty)
              _linha(Icons.place_outlined, meeting.location),
            if (meeting.notes.isNotEmpty)
              _linha(Icons.notes, meeting.notes),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: meeting.participants
                  .map((p) => Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        label: Text('${p.name} · ${p.roleLabel}',
                            style: const TextStyle(fontSize: 11)),
                      ))
                  .toList(),
            ),
            if (meeting.createdBy.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Agendada por ${meeting.createdBy}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            if (podeCancelar)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  label: const Text('Cancelar',
                      style: TextStyle(color: Colors.red)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _linha(IconData icone, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 15, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ),
          ],
        ),
      );
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final String texto;
  const _Aviso({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              Text(texto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 15)),
            ],
          ),
        ),
      );
}
