import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    await context.read<AppProvider>().init();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F64), // navy
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),

            // USET logo mark (U circle)
            Center(
              child: Column(
                children: [
                  // Logo circle
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CustomPaint(painter: _USetLogoPainter()),
                  ),
                  const SizedBox(height: 20),

                  // App name
                  const Text(
                    'MONTAGEM USET',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Gestão de Pendências',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(height: 40),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        color: Colors.white54, strokeWidth: 2.5),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 3),

            // Credit line
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Column(
                children: [
                  Text(
                    'Desenvolvido por Cleiton Nascimento',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Licenciado para USET Brasil',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
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

class _USetLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // White circular background
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    final navyPaint = Paint()..color = const Color(0xFF0A0F64);

    // Draw the U shape (navy) centered
    final double sw = w * 0.18; // stroke width
    final double ux0 = w * 0.15;
    final double ux1 = w * 0.85;
    final double uy0 = h * 0.15;
    final double uy1 = h * 0.88;
    final double midY = uy0 + (uy1 - uy0) * 0.45;

    // Left arm
    canvas.drawRect(
        Rect.fromLTRB(ux0, uy0, ux0 + sw, midY), navyPaint);
    // Right arm
    canvas.drawRect(
        Rect.fromLTRB(ux1 - sw, uy0, ux1, midY), navyPaint);
    // Bottom arc (filled U bowl)
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTRB(ux0, midY - sw * 0.5, ux1, uy1),
        Radius.circular(w * 0.35));
    canvas.drawRRect(rrect, navyPaint);
    // Inner white cutout (hollow bowl)
    final innerRRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(ux0 + sw, midY + sw * 0.5, ux1 - sw, uy1 - sw * 0.5),
        Radius.circular(w * 0.28));
    canvas.drawRRect(innerRRect, bgPaint);

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
