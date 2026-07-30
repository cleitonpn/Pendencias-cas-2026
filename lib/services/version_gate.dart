import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'admin_api.dart';

/// Resultado da conferência de versão mínima.
class VersionVerdict {
  final bool blocked;
  final int localBuild;
  final int minBuild;
  final String message;

  const VersionVerdict({
    required this.blocked,
    required this.localBuild,
    required this.minBuild,
    this.message = '',
  });
}

/// Exige uma versão mínima do app.
///
/// Existe por causa das regras do Firestore: quando elas fecham as coleções
/// de PIN, uma versão anterior do app não fica "meio quebrada" — ela lê
/// direto do Firestore, leva permissão negada e mostra mensagens sem sentido,
/// como "nenhum gerente cadastrado". É melhor parar e dizer "atualize" do que
/// deixar a pessoa tentando entender por que o app enlouqueceu.
///
/// Vale também para qualquer mudança futura que quebre compatibilidade: o
/// número fica no Firestore, então subir a exigência não precisa de novo
/// build.
class VersionGate {
  static const _doc = 'app_config';
  static const _id = 'version';

  static Future<int> localBuild() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Confere se esta versão ainda é aceita.
  ///
  /// Falha aberta de propósito: sem conexão, ou com o documento ausente,
  /// ninguém é bloqueado. Um problema nosso de leitura não pode trancar a
  /// equipe fora do app no meio de uma montagem.
  static Future<VersionVerdict> check() async {
    final local = await localBuild();
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_doc)
          .doc(_id)
          .get();
      if (!snap.exists) {
        return VersionVerdict(
            blocked: false, localBuild: local, minBuild: 0);
      }
      final data = snap.data() ?? {};
      final min = (data['minBuild'] as num?)?.toInt() ?? 0;
      // local == 0 significa que não deu para ler a versão instalada.
      // Bloquear nesse caso trancaria todo mundo por um erro nosso.
      final blocked = local > 0 && min > local;
      return VersionVerdict(
        blocked: blocked,
        localBuild: local,
        minBuild: min,
        message: (data['message'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('[versão] não foi possível conferir a mínima: $e');
      return VersionVerdict(blocked: false, localBuild: local, minBuild: 0);
    }
  }

  /// Versão mínima exigida hoje. Zero quando não há exigência.
  static Future<int> currentMinimum() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_doc)
          .doc(_id)
          .get();
      return ((snap.data() ?? {})['minBuild'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Define a versão mínima.
  ///
  /// Vai pelo servidor: escrita direta permitiria a qualquer sessão
  /// autenticada — inclusive a anônima dos portais públicos — exigir uma
  /// versão inexistente e trancar a equipe fora do app.
  static Future<void> setMinimum(int build, {String message = ''}) async {
    await FirebaseFunctions.instance.httpsCallable('setMinBuild').call({
      'token': await AdminApi.token(),
      'minBuild': build,
      'message': message,
    });
  }
}
