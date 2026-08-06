import 'package:flutter/material.dart';

/// O estado da comunicação visual de um stand, vindo da ferramenta de
/// aprovação de arte.
///
/// A ferramenta controla a arte PEÇA a peça — lona, testeira, adesivo, cada
/// uma no seu momento. Aqui chega uma linha só por stand, porque a pergunta de
/// quem está montando é uma só: "posso contar com essa arte?".
///
/// O agregado é sempre o estado MAIS ATRASADO, nunca o mais avançado. Um stand
/// com quatro peças impressas e uma sem arte nenhuma não está quase pronto:
/// está esperando o cliente, e é isso que precisa aparecer. O contador ao lado
/// é o que separa "falta uma" de "falta tudo".
///
/// Nada disto é escrito pelo app. A coleção `cv_status` é publicada pela
/// ferramenta através de uma ação agendada; aqui só se lê.
class ArtStatus {
  /// `sem_pecas`, `aguardando`, `em_analise`, `aprovada`, `em_impressao`,
  /// `impressa`.
  final String estado;

  /// Texto pronto, definido pela ferramenta. Vem de lá de propósito: se o app
  /// traduzisse por conta própria, um estado novo apareceria como caixa vazia
  /// até alguém publicar um APK.
  final String rotulo;

  final int recebidas;
  final int total;

  /// A prova de aprovação mais recente. Tem prioridade sobre o print que vem
  /// da planilha — é o mesmo documento, só que atualizado sozinho.
  final String linkProva;

  final String provaEm;
  final DateTime? atualizadoEm;

  const ArtStatus({
    required this.estado,
    required this.rotulo,
    this.recebidas = 0,
    this.total = 0,
    this.linkProva = '',
    this.provaEm = '',
    this.atualizadoEm,
  });

  factory ArtStatus.fromMap(Map<String, dynamic> m) => ArtStatus(
        estado: (m['estado'] as String?) ?? 'sem_pecas',
        rotulo: (m['rotulo'] as String?) ?? 'Sem informação',
        recebidas: (m['recebidas'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
        linkProva: (m['linkProva'] as String?) ?? '',
        provaEm: (m['provaEm'] as String?) ?? '',
        atualizadoEm: m['atualizadoEm'] is String
            ? DateTime.tryParse(m['atualizadoEm'] as String)
            : null,
      );

  bool get temPecas => total > 0;

  /// "3 de 5 artes" — vazio quando não há peça cadastrada, porque "0 de 0" não
  /// informa nada e ainda parece defeito.
  String get contador => temPecas ? '$recebidas de $total artes' : '';

  /// A cor segue o significado, não o estado: vermelho é o que trava a
  /// montagem, verde é o que já pode ser esquecido.
  Color get cor {
    switch (estado) {
      case 'aguardando':
        return Colors.red.shade700;
      case 'em_analise':
        return Colors.orange.shade800;
      case 'aprovada':
        return Colors.green.shade700;
      case 'em_impressao':
        return Colors.blue.shade700;
      case 'impressa':
        return Colors.green.shade800;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData get icone {
    switch (estado) {
      case 'aguardando':
        return Icons.hourglass_empty;
      case 'em_analise':
        return Icons.search;
      case 'aprovada':
        return Icons.check_circle_outline;
      case 'em_impressao':
        return Icons.print_outlined;
      case 'impressa':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }
}
