import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDefaultPin = '563982';
const _kPinKey = 'admin_pin';

Future<String> getAdminPin() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kPinKey) ?? _kDefaultPin;
}

Future<void> saveAdminPin(String pin) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPinKey, pin);
}

/// Shows an admin PIN dialog and returns true if the correct PIN was entered.
Future<bool> requireAdminPin(BuildContext context) async {
  final ctrl = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Row(children: [
        Icon(Icons.admin_panel_settings, color: Color(0xFF1E3A5F)),
        SizedBox(width: 8),
        Text('Acesso Administrador'),
      ]),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 6,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Digite o PIN de administrador',
          prefixIcon: Icon(Icons.lock_outline),
          counterText: '',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A5F),
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  final adminPin = await getAdminPin();
  if (ctrl.text == adminPin) return true;

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PIN incorreto. Acesso negado.'),
        backgroundColor: Colors.red,
      ),
    );
  }
  return false;
}
