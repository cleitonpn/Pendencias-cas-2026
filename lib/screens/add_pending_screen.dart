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
  // Equipes disponíveis com cores e ícones
  static const _teams = [
    _TeamInfo('Limpeza',               Icons.cleaning_services, Color(0xFF00897B)),
    _TeamInfo('Elétrica',              Icons.bolt,              Color(0xFFFF6F00)),
    _TeamInfo('Marcenaria',            Icons.carpenter,         Color(0xFF795548)),
    _TeamInfo('Tapeçaria',             Icons.chair,             Color(0xFF7B1FA2)),
    _TeamInfo('Vidraceiro',            Icons.window,            Color(0xFF0288D1)),
    _TeamInfo('Comunicação Visual',    Icons.brush,             Color(0xFFD81B60)),
  ];

  String? _selectedTeam;
  final _descCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  // Retorna o responsável da equipe a partir dos dados do cliente (colunas O-T)
  String _getResponsible(String team) {
    final c = widget.client;
    switch (team) {
      case 'Limpeza':         return c.faxineira;
      case 'Elétrica':        return c.eletricista;
      case 'Marcenaria':      return c.marceneiro;
      case 'Tapeçaria':       return c.tapeceiro;
      case 'Vidraceiro':         return 'Rodrigo';
      case 'Comunicação Visual': return 'Vinícius';
      default:                return '';
    }
  }

  Future<void> _save() async {
    if (_selectedTeam == null) {
      _snack('Selecione a equipe responsável.', isError: true);
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _snack('Descreva a pendência.', isError: true);
      return;
    }
    setState(() => _saving = true);

    final responsible = _getResponsible(_selectedTeam!);

    final newItem = PendingItem(
      clientId: widget.client.rowId,
      clientName: widget.client.displayName,
      local: widget.client.local,
      hangar: widget.client.hangar,
      team: _selectedTeam!,
      responsible: responsible,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  borderRadius: BorderRadius.circular(8)),
              child: Text(text, style: const TextStyle(fontSize: 13)),
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
                foregroundColor: Colors.white),
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
    final responsible = _selectedTeam != null ? _getResponsible(_selectedTeam!) : '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text('Nova Pendência',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info do cliente
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const Icon(Icons.info_outline,
                    color: Color(0xFF1E3A5F)),
                title: Text(c.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${c.hangar.isNotEmpty ? "Hangar ${c.hangar}  •  " : ""}Stand ${c.local}'
                    '${c.area.isNotEmpty ? "  •  ${c.area} m²" : ""}',
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

            // Seleção de equipe
            ...(_teams.map((t) {
              final sel = _selectedTeam == t.name;
              final resp = _getResponsible(t.name);
              return GestureDetector(
                onTap: () => setState(() => _selectedTeam = t.name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: sel ? t.color.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? t.color : Colors.grey.shade200,
                      width: sel ? 2 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Icon(t.icon,
                        color: sel ? t.color : Colors.grey,
                        size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: sel ? t.color : Colors.black87,
                                  fontSize: 15)),
                          if (resp.isNotEmpty)
                            Text('Responsável: $resp',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: sel
                                        ? t.color.withOpacity(0.8)
                                        : Colors.grey)),
                        ],
                      ),
                    ),
                    if (sel)
                      Icon(Icons.check_circle, color: t.color, size: 20),
                  ]),
                ),
              );
            })),

            // Aviso se equipe selecionada tem responsável
            if (responsible.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.person, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Text('Responsável: $responsible',
                      style: const TextStyle(
                          color: Colors.blue, fontSize: 13)),
                ]),
              ),
            ],

            const SizedBox(height: 20),
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

class _TeamInfo {
  final String name;
  final IconData icon;
  final Color color;
  const _TeamInfo(this.name, this.icon, this.color);
}
