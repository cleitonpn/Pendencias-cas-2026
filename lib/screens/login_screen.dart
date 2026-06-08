import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../utils/admin_pin.dart';
import 'fair_selection_screen.dart';
import 'producer_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isAdmin = false;
  List<String> _producers = [];
  String? _selected;
  final _pinCtrl = TextEditingController();
  bool _loadingProducers = true;
  bool _verifying = false;
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
    try {
      final list = await FirestoreService.getProducersWithPins();
      if (mounted) setState(() { _producers = list; _loadingProducers = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingProducers = false);
    }
  }

  Future<void> _enter() async {
    setState(() { _error = null; _verifying = true; });
    try {
      if (_isAdmin) {
        await _enterAdmin();
      } else {
        await _enterProducer();
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _enterAdmin() async {
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite o PIN de administrador.');
      return;
    }
    final adminPin = await getAdminPin();
    if (_pinCtrl.text != adminPin) {
      setState(() => _error = 'PIN incorreto.');
      _pinCtrl.clear();
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const FairSelectionScreen()));
  }

  Future<void> _enterProducer() async {
    if (_selected == null) {
      setState(() => _error = 'Selecione seu nome.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite seu PIN.');
      return;
    }
    final savedPin = await FirestoreService.getProducerPin(_selected!);
    if (!mounted) return;
    if (savedPin == null) {
      setState(() => _error = 'PIN não configurado. Contate o administrador.');
      return;
    }
    if (_pinCtrl.text != savedPin) {
      setState(() => _error = 'PIN incorreto.');
      _pinCtrl.clear();
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(
            builder: (_) => ProducerHomeScreen(producerName: _selected!)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F64),
      body: SafeArea(
        child: Column(
          children: [
            // ── Logo section ────────────────────────────────────────────
            const Spacer(flex: 2),
            Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: CustomPaint(painter: _USetLogoPainter()),
                  ),
                  const SizedBox(height: 16),
                  const Text('MONTAGEM USET',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3)),
                  const SizedBox(height: 4),
                  const Text('Gestão de Pendências',
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                ],
              ),
            ),
            const Spacer(flex: 2),

            // ── Login card ──────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _ToggleBtn(
                            label: 'Produtor',
                            icon: Icons.badge_outlined,
                            active: !_isAdmin,
                            onTap: () => setState(() {
                                  _isAdmin = false;
                                  _error = null;
                                  _pinCtrl.clear();
                                })),
                        _ToggleBtn(
                            label: 'Administrador',
                            icon: Icons.admin_panel_settings_outlined,
                            active: _isAdmin,
                            onTap: () => setState(() {
                                  _isAdmin = true;
                                  _error = null;
                                  _pinCtrl.clear();
                                  _selected = null;
                                })),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Producer name selector
                  if (!_isAdmin) ...[
                    const Text('SEU NOME',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _loadingProducers
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _producers.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.orange.shade200)),
                                child: const Text(
                                    'Nenhum produtor cadastrado.\nContate o administrador.',
                                    style: TextStyle(
                                        color: Colors.orange, fontSize: 13)),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _producers.map((p) {
                                  final sel = _selected == p;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selected = p;
                                      _error = null;
                                    }),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: sel
                                            ? const Color(0xFF1E3A5F)
                                            : Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(20),
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
                                              fontSize: 13)),
                                    ),
                                  );
                                }).toList(),
                              ),
                    const SizedBox(height: 16),
                  ],

                  // PIN field
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
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: _isAdmin ? 'PIN de administrador' : 'Seu PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      counterText: '',
                    ),
                    onSubmitted: (_) => _enter(),
                  ),

                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200)),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 13))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Login button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _verifying ? null : _enter,
                      icon: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: Text(_verifying ? 'Verificando...' : 'Entrar',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ToggleBtn(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1E3A5F) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: active ? Colors.white : Colors.grey, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _USetLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);
    final navyPaint = Paint()..color = const Color(0xFF0A0F64);
    final double sw = w * 0.18;
    final double ux0 = w * 0.15;
    final double ux1 = w * 0.85;
    final double uy0 = h * 0.15;
    final double uy1 = h * 0.88;
    final double midY = uy0 + (uy1 - uy0) * 0.45;
    canvas.drawRect(Rect.fromLTRB(ux0, uy0, ux0 + sw, midY), navyPaint);
    canvas.drawRect(Rect.fromLTRB(ux1 - sw, uy0, ux1, midY), navyPaint);
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTRB(ux0, midY - sw * 0.5, ux1, uy1),
        Radius.circular(w * 0.35));
    canvas.drawRRect(rrect, navyPaint);
    final innerRRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(ux0 + sw, midY + sw * 0.5, ux1 - sw, uy1 - sw * 0.5),
        Radius.circular(w * 0.28));
    canvas.drawRRect(innerRRect, bgPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
