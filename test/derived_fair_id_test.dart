import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/fair_key.dart';

/// O id da feira derivada de planilha mestra.
///
/// Antes ele era o próximo número que o SQLite daquele aparelho tinha a dar, e
/// esse número virava o id do documento no Firestore. Dois aparelhos
/// sincronizando a mesma planilha criavam a MESMA feira com ids diferentes,
/// publicavam dois documentos, e a feira passava a aparecer duas vezes para
/// todo mundo — cada cópia com o seu próprio modo.
void main() {
  group('id derivado do nome', () {
    test('o mesmo nome dá sempre o mesmo id', () {
      // É o ponto inteiro: dois aparelhos precisam chegar ao mesmo número
      // sem falar um com o outro.
      expect(derivedFairId('ABAV'), derivedFairId('ABAV'));
      expect(derivedFairId('SUMMIT LOGISTICA ECBR'),
          derivedFairId('SUMMIT LOGISTICA ECBR'));
    });

    test('caixa, espaço sobrando e acento não criam feira nova', () {
      // A coluna FEIRA é digitada à mão e varia entre sincronizações.
      expect(derivedFairId(' abav '), derivedFairId('ABAV'));
      expect(derivedFairId('Bienal do Livro'), derivedFairId('BIENAL DO LIVRO'));
      expect(derivedFairId('Conferência'), derivedFairId('CONFERENCIA'));
    });

    test('feiras diferentes têm ids diferentes', () {
      expect(derivedFairId('ABAV') == derivedFairId('BIENAL DO LIVRO'), isFalse);
      expect(derivedFairId('SUMMIT LOGISTICA ECBR') == derivedFairId('EXPOPOSTOS'),
          isFalse);
    });

    test('fica acima da faixa dos ids criados à mão', () {
      // As feiras individuais vêm do autoincremento e são números pequenos.
      // Cair em cima de uma delas seria roubar a feira de outra pessoa.
      for (final nome in ['ABAV', 'BIENAL DO LIVRO', 'EXPOPOSTOS', 'PETVET']) {
        expect(derivedFairId(nome), greaterThan(1000));
      }
    });

    test('nome sem letra nem número não gera id', () {
      // Sem chave não há id estável, e o chamador cai no autoincremento em
      // vez de todos os nomes vazios dividirem o mesmo id.
      expect(derivedFairId(''), 0);
      expect(derivedFairId('   '), 0);
      expect(derivedFairId('---'), 0);
    });
  });

  group('qual modo sobrevive à fusão', () {
    test('manutenção vence produção e pré-produção', () {
      // Manutenção é o modo que abre o QR para o expositor. Rebaixá-lo numa
      // fusão fecharia o atendimento no meio do evento.
      expect(fairModeRank('manutencao'), greaterThan(fairModeRank('producao')));
      expect(fairModeRank('producao'),
          greaterThan(fairModeRank('pre_producao')));
    });

    test('modo desconhecido não vence nenhum modo real', () {
      expect(fairModeRank('qualquer_coisa'),
          lessThan(fairModeRank('pre_producao')));
    });
  });
}
