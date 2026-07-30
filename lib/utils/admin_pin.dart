import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/admin_api.dart';
import '../services/session_service.dart';

/// Portão de administrador.
///
/// Antes o PIN era conferido no próprio aparelho, contra um valor padrão
/// escrito no código (e guardado em SharedPreferences quando trocado). Quem
/// abrisse o APK tinha acesso de admin, e a troca de PIN valia só naquele
/// celular. Agora quem confere é o servidor, contra os administradores
/// cadastrados, e o app guarda apenas um token de sessão de 12 horas.
Future<bool> requireAdminPin(BuildContext context) async {
  // Quem entrou no app como administrador já provou quem é no login e saiu de
  // lá com a sessão de gestão. Pedir o PIN de novo aqui só atrapalharia — e,
  // pior, travaria o trabalho em campo quando o sinal do pavilhão cai, já que
  // a conferência agora depende do servidor.
  final session = await SessionService.get();
  if (session?['role'] == 'admin' && await AdminApi.hasValidSession()) {
    return true;
  }

  if (!context.mounted) return false;
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

  final r = await AdminApi.gate(ctrl.text);
  if (r.ok) return true;

  if (context.mounted) {
    final msg = switch (r.reason) {
      'erro' => 'Não foi possível verificar agora. Confira a conexão.',
      'bloqueado' => 'Muitas tentativas erradas. Tente de novo em 15 minutos.',
      'nenhum_admin' => 'Nenhum administrador cadastrado no sistema.',
      _ => 'PIN incorreto. Acesso negado.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
  return false;
}
