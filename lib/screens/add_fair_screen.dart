import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'hangar_list_screen.dart';

class AddFairScreen extends StatefulWidget {
  const AddFairScreen({super.key});

  @override
  State<AddFairScreen> createState() => _AddFairScreenState();
}

class _AddFairScreenState extends State<AddFairScreen> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _sheetCtrl = TextEditingController(text: 'Sheet1');
  String _sheetMode = 'individual'; // 'individual' | 'mestra'
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  static String? _extractId(String url) {
    final match =
        RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final sheet = _sheetCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome da feira.');
      return;
    }
    if (url.isEmpty) {
      setState(() => _error = 'Informe o link da planilha.');
      return;
    }
    final spreadsheetId = _extractId(url);
    if (spreadsheetId == null) {
      setState(() =>
          _error = 'Link inválido. Use o link completo do Google Sheets.');
      return;
    }
    if (sheet.isEmpty) {
      setState(() => _error = 'Informe o nome da aba.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final fair = await context.read<AppProvider>().addFair(
        name, spreadsheetId, sheet,
        sheetMode: _sheetMode);
    if (!mounted) return;

    if (_sheetMode == 'individual') {
      await context.read<AppProvider>().selectFair(fair);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HangarListScreen()));
    } else {
      // Mestra fair: go back to selection screen — user syncs to create children
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Nova Feira',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode selector
            _label('TIPO DE PLANILHA'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _ModeBtn(
                    label: 'Individual',
                    icon: Icons.table_chart_outlined,
                    description: 'Uma planilha por feira',
                    active: _sheetMode == 'individual',
                    onTap: () => setState(() => _sheetMode = 'individual'),
                  ),
                  _ModeBtn(
                    label: 'Mestra',
                    icon: Icons.table_rows_outlined,
                    description: 'Várias feiras numa planilha',
                    active: _sheetMode == 'mestra',
                    onTap: () => setState(() => _sheetMode = 'mestra'),
                  ),
                ],
              ),
            ),

            if (_sheetMode == 'mestra') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.purple, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A planilha deve ter uma coluna "FEIRA". '
                      'Cada linha representa um cliente de uma feira diferente. '
                      'As feiras serão criadas automaticamente ao sincronizar.',
                      style: TextStyle(fontSize: 12, color: Colors.purple),
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    SizedBox(width: 8),
                    Text('Antes de adicionar',
                        style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold)),
                  ]),
                  SizedBox(height: 8),
                  Text(
                    'A planilha deve estar compartilhada como "Qualquer pessoa com o link pode visualizar".',
                    style: TextStyle(fontSize: 13, color: Colors.blue),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _label('NOME DA FEIRA'),
            const SizedBox(height: 8),
            _field(_nameCtrl,
                _sheetMode == 'mestra'
                    ? 'Ex: Operacional 2026'
                    : 'Ex: Forum 2026',
                Icons.event),
            const SizedBox(height: 16),

            _label('LINK DA PLANILHA (Google Sheets)'),
            const SizedBox(height: 8),
            _field(_urlCtrl,
                'https://docs.google.com/spreadsheets/d/...', Icons.link),
            const SizedBox(height: 16),

            _label('NOME DA ABA'),
            const SizedBox(height: 8),
            _field(_sheetCtrl, 'Nome exato da aba (ex: projetos)', Icons.tab),
            const SizedBox(height: 6),
            const Text('Confira o nome exato da aba na planilha.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red))),
                ]),
              ),
            ],

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
                    : const Icon(Icons.add),
                label: Text(_saving ? 'Adicionando...' : 'Adicionar Feira',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
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

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1));

  Widget _field(
          TextEditingController ctrl, String hint, IconData icon) =>
      TextField(
        controller: ctrl,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white,
        ),
      );
}

class _ModeBtn extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ModeBtn({
    required this.label,
    required this.description,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1E3A5F) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: active ? Colors.white : Colors.grey, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: active ? Colors.white : Colors.black87)),
              const SizedBox(height: 2),
              Text(description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      color: active ? Colors.white70 : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
