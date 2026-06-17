import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';

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
  ];

  final Set<String> _selected = {'todos'};

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

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o título do aviso.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await FirestoreService.writeAviso(
        title: title,
        body: body,
        createdBy: _authorName,
        targetGroups: _selected.toList(),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const Text('Título',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _navy,
                    fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ex: Reunião amanhã às 9h',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Mensagem',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _navy,
                    fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _bodyCtrl,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Escreva o conteúdo do aviso...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Enviar para',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _navy,
                    fontSize: 13)),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: _allGroups.map((entry) {
                  final key = entry.$1;
                  final label = entry.$2;
                  final isSelected = _selected.contains(key);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(label,
                        style: const TextStyle(fontSize: 14)),
                    value: isSelected,
                    activeColor: _navy,
                    onChanged: (_) => _toggleGroup(key),
                  );
                }).toList(),
              ),
            ),
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
}
