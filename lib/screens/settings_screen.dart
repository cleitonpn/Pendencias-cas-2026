import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'hangar_list_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool isInitial;
  const SettingsScreen({super.key, this.isInitial = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBusy = false;

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
      if (widget.isInitial) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HangarListScreen()));
      } else {
        Navigator.of(context).pop();
        _snack('Dados sincronizados com sucesso!');
      }
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isInitial)
                IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context)),

              const Spacer(),

              const Center(
                child: Icon(Icons.construction, color: Colors.white, size: 72),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text('CAS 2026',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
              ),
              const Center(
                child: Text('Gestão de Pendências',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),

              const Spacer(),

              // Instrução simples
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.info_outline, color: Colors.amber, size: 18),
                      SizedBox(width: 8),
                      Text('Antes de sincronizar',
                          style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 10),
                    _step('1', 'Abra a planilha no Google Sheets'),
                    _step('2', 'Clique em  Compartilhar'),
                    _step('3',
                        'Mude para "Qualquer pessoa com o link"\ne selecione "Visualizador"'),
                    _step('4', 'Toque em Sincronizar abaixo'),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : _sync,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.sync, color: Colors.white),
                  label: Text(
                    _isBusy ? 'Sincronizando...' : 'Sincronizar Planilha',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
              ),

              const Spacer(),
            ],
          ),
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
              decoration: const BoxDecoration(
                  color: Colors.white24, shape: BoxShape.circle),
              child: Center(
                  child: Text(num,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13))),
          ],
        ),
      );
}
