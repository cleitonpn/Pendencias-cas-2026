import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../utils/admin_pin.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBusy = false;
  List<String> _producers = [];
  Map<String, String?> _pins = {};

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final fairId = context.read<AppProvider>().currentFair?.id ?? 1;
    // Load producer names from local DB (if synced) and from Firestore (if PINs set)
    final localProducers = await DatabaseService.getProducers(fairId: fairId);
    final firestoreProducers = await FirestoreService.getProducersWithPins();
    final allProducers = {...localProducers, ...firestoreProducers}.toList()..sort();

    final pins = <String, String?>{};
    for (final p in allProducers) {
      pins[p] = await FirestoreService.getProducerPin(p);
    }
    if (mounted) setState(() { _producers = allProducers; _pins = pins; });
  }

  Future<void> _sync() async {
    setState(() => _isBusy = true);
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    await provider.syncFromSheets();
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (provider.error != null) {
      _snack('Erro: ${provider.error}', isError: true);
    } else {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Dados sincronizados com sucesso!'),
        backgroundColor: Colors.green,
      ));
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<void> _editPin(String producerName) async {
    final currentPin = _pins[producerName];
    final ctrl = TextEditingController(text: currentPin ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('PIN — $producerName'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o PIN (4–6 dígitos)',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          if (currentPin != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Remover', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result.isEmpty) {
      await FirestoreService.deleteProducerPin(producerName);
    } else {
      await FirestoreService.setProducerPin(producerName, result);
    }
    await _loadPins();
  }

  Future<void> _changeAdminPin() async {
    final currentPin = await getAdminPin();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.admin_panel_settings, color: Color(0xFF1E3A5F)),
          SizedBox(width: 8),
          Text('Alterar PIN Admin'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'PIN atual', prefixIcon: Icon(Icons.lock)),
            ),
            TextField(
              controller: newCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Novo PIN', prefixIcon: Icon(Icons.lock_open)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (currentCtrl.text != currentPin) {
                Navigator.pop(ctx);
                _snack('PIN atual incorreto.', isError: true);
                return;
              }
              if (newCtrl.text.length < 4) {
                _snack('O novo PIN deve ter ao menos 4 dígitos.',
                    isError: true);
                return;
              }
              await saveAdminPin(newCtrl.text);
              Navigator.pop(ctx);
              _snack('PIN de administrador alterado!');
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Alterar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fair = context.watch<AppProvider>().currentFair;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Configurações',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fair != null) ...[
              const Text('FEIRA ATUAL',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.event, color: Color(0xFF1E3A5F), size: 20),
                        const SizedBox(width: 8),
                        Text(fair.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 6),
                      Text('Aba: ${fair.sheetName}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Sync section
            const Text('SINCRONIZAÇÃO',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _step('1', 'Abra a planilha no Google Sheets'),
                    _step('2', 'Clique em Compartilhar'),
                    _step('3',
                        'Mude para "Qualquer pessoa com o link"\ne selecione "Visualizador"'),
                    _step('4', 'Toque em Sincronizar abaixo'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isBusy ? null : _sync,
                        icon: _isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.sync, color: Colors.white),
                        label: Text(
                            _isBusy ? 'Sincronizando...' : 'Sincronizar Planilha',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Producer PINs
            const Text('PINs DOS PRODUTORES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'Configure um PIN para que cada produtor possa acessar suas pendências.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            _producers.isEmpty
                ? Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Nenhum produtor encontrado. Sincronize a planilha primeiro.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: _producers.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        final pin = _pins[p];
                        final hasPin = pin != null;
                        return Column(
                          children: [
                            if (i > 0) const Divider(height: 1, indent: 16),
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: hasPin
                                    ? Colors.green.shade100
                                    : Colors.grey.shade100,
                                child: Icon(
                                    hasPin ? Icons.lock : Icons.lock_open,
                                    color: hasPin ? Colors.green : Colors.grey,
                                    size: 20),
                              ),
                              title: Text(p,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  hasPin ? 'PIN configurado' : 'Sem PIN',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: hasPin ? Colors.green : Colors.grey)),
                              trailing: TextButton(
                                onPressed: () => _editPin(p),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

            const SizedBox(height: 24),

            // Admin PIN management
            const Text('ADMINISTRADOR',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1E3A5F),
                  child: Icon(Icons.admin_panel_settings,
                      color: Colors.white, size: 20),
                ),
                title: const Text('PIN de Administrador',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Altere o PIN de acesso admin',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                trailing: TextButton(
                  onPressed: _changeAdminPin,
                  child: const Text('Alterar',
                      style: TextStyle(color: Color(0xFF1E3A5F))),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _step(String num, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withOpacity(0.1),
                  shape: BoxShape.circle),
              child: Center(
                  child: Text(num,
                      style: const TextStyle(
                          color: Color(0xFF1E3A5F),
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(color: Colors.black87, fontSize: 13))),
          ],
        ),
      );
}
