import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../models/pending_item.dart';

class AddPendingScreen extends StatefulWidget {
  final Client client;
  const AddPendingScreen({super.key, required this.client});

  @override
  State<AddPendingScreen> createState() => _AddPendingScreenState();
}

class _AddPendingScreenState extends State<AddPendingScreen> {
  static const _teams = [
    'Limpeza',
    'Elétrica',
    'Marcenaria',
    'Tapeçaria',
    'Laminação',
    'Produtos',
    'Montagem',
    'MK',
  ];

  String? _team;
  final _descCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_team == null) {
      _snack('Selecione a equipe responsável.', isError: true);
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _snack('Descreva a pendência.', isError: true);
      return;
    }
    setState(() => _saving = true);

    final newItem = PendingItem(
      clientId: widget.client.rowId,
      clientName: widget.client.displayName,
      stand: widget.client.stand,
      hangar: widget.client.hangar,
      team: _team!,
      description: _descCtrl.text.trim(),
      createdAt: DateTime.now(),
    );

    final saved = await context.read<AppProvider>().addPendingItem(newItem);
    if (!mounted) return;
    setState(() => _saving = false);

    await _showDialog(saved);
    if (mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _showDialog(PendingItem item) {
    final text = item.toWhatsAppText();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('Pendência criada!'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja copiar o texto para enviar no WhatsApp?',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  Text(text, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar')),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              _snack('Copiado! Abra o WhatsApp e cole.');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : const Color(0xFF25D366),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text('Nova Pendência',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Client info card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const Icon(Icons.info_outline,
                    color: Color(0xFF1E3A5F)),
                title: Text(c.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'Hangar ${c.hangar} • Stand ${c.stand}',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
              ),
            ),

            const SizedBox(height: 20),
            const Text('EQUIPE RESPONSÁVEL',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _teams.map((team) {
                final sel = _team == team;
                return GestureDetector(
                  onTap: () => setState(() => _team = team),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? Colors.orange : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sel ? Colors.orange : Colors.grey.shade300,
                        width: sel ? 2 : 1,
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                  color: Colors.orange.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ]
                          : [],
                    ),
                    child: Text(team,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : Colors.black87)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),
            const Text('DESCRIÇÃO DA PENDÊNCIA',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 10),

            TextField(
              controller: _descCtrl,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Descreva detalhadamente a pendência...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Criar Pendência',
                    style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
