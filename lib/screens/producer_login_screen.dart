import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import 'producer_pending_screen.dart';

class ProducerLoginScreen extends StatefulWidget {
  const ProducerLoginScreen({super.key});

  @override
  State<ProducerLoginScreen> createState() => _ProducerLoginScreenState();
}

class _ProducerLoginScreenState extends State<ProducerLoginScreen> {
  List<String> _producers = [];
  String? _selected;
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducers();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducers() async {
    final fairId = context.read<AppProvider>().currentFair?.id ?? 1;
    final producers = await DatabaseService.getProducers(fairId: fairId);
    if (mounted) setState(() => _producers = producers);
  }

  Future<void> _login() async {
    if (_selected == null) {
      setState(() => _error = 'Selecione um produtor.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite seu PIN.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final savedPin = await DatabaseService.getProducerPin(_selected!);
    if (!mounted) return;
    setState(() => _loading = false);

    if (savedPin == null) {
      setState(() => _error =
          'PIN não configurado para este produtor.\nPeça ao administrador para configurar em Configurações.');
      return;
    }
    if (savedPin != _pinCtrl.text) {
      setState(() => _error = 'PIN incorreto. Tente novamente.');
      _pinCtrl.clear();
      return;
    }

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProducerPendingScreen(
                lockedProducer: _selected!, canResolve: true)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Acesso Produtor',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SELECIONE SEU NOME',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            _producers.isEmpty
                ? const Text(
                    'Nenhum produtor encontrado. Sincronize a planilha primeiro.',
                    style: TextStyle(color: Colors.grey))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _producers.map((p) {
                      final sel = _selected == p;
                      return GestureDetector(
                        onTap: () =>
                            setState(() {
                              _selected = p;
                              _error = null;
                            }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFF1E3A5F)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel
                                  ? const Color(0xFF1E3A5F)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(p,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white
                                      : Colors.black87,
                                  fontSize: 14)),
                        ),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 28),
            const Text('PIN',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            TextField(
              controller: _pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: 'Digite seu PIN',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
                counterText: '',
              ),
              onSubmitted: (_) => _login(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13))),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _login,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.login),
                label: Text(_loading ? 'Verificando...' : 'Entrar',
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
}
