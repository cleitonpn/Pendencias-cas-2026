import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/models/art_status.dart';
import 'package:montagem_uset/models/client.dart';

/// A regra do print da comunicação visual.
///
/// São duas origens para o mesmo documento: a planilha, colada à mão, e a
/// ferramenta de aprovação, que sempre tem a prova mais recente daquele stand.
/// Escolher errado aqui faz o produtor abrir na montagem a versão que o
/// cliente já mandou corrigir.

Client stand({String linkCv = '', ArtStatus? arte}) => Client(
      rowId: '1_1',
      firestoreId: 'feira_1',
      nome: 'After Click',
      montagem: '',
      local: 'A12',
      hangar: '',
      area: '36',
      deck: '',
      totalArea: '36',
      mezanino: '',
      produtor: 'Marcos',
      marceneiro: '',
      tapeceiro: '',
      eletricista: '',
      faxineira: '',
      teto50: '',
      linkCv: linkCv,
    )..arte = arte;

const daFerramenta = ArtStatus(
  estado: 'aprovada',
  rotulo: 'Aprovada',
  recebidas: 3,
  total: 3,
  linkProva: 'https://ferramenta/prova-nova.png',
);

void main() {
  group('link da comunicação visual', () {
    test('a prova da ferramenta vence o link da planilha', () {
      final c = stand(linkCv: 'https://drive/print-antigo.png', arte: daFerramenta);
      expect(c.linkCvEfetivo, 'https://ferramenta/prova-nova.png');
      expect(c.provaDaFerramenta, isTrue);
    });

    test('sem ferramenta, a planilha continua valendo', () {
      // O stand que ainda não foi importado para a ferramenta não pode perder
      // o print que já tinha — seria uma funcionalidade nova apagando uma
      // antiga que funciona.
      final c = stand(linkCv: 'https://drive/print.png');
      expect(c.linkCvEfetivo, 'https://drive/print.png');
      expect(c.provaDaFerramenta, isFalse);
    });

    test('ferramenta sem prova ainda cai para a planilha', () {
      // Importado, com status, mas o analista ainda não subiu prova nenhuma.
      const semProva = ArtStatus(
        estado: 'aguardando', rotulo: 'Aguardando cliente', recebidas: 0, total: 3);
      final c = stand(linkCv: 'https://drive/print.png', arte: semProva);
      expect(c.linkCvEfetivo, 'https://drive/print.png');
      expect(c.provaDaFerramenta, isFalse);
    });

    test('sem nenhuma das duas, fica vazio e a tela esconde o botão', () {
      expect(stand().linkCvEfetivo, '');
    });
  });

  group('leitura do status', () {
    test('lê o documento publicado pela ferramenta', () {
      final a = ArtStatus.fromMap({
        'estado': 'em_impressao',
        'rotulo': 'Em impressão',
        'recebidas': 4,
        'total': 5,
        'linkProva': 'https://x/p.png',
      });
      expect(a.estado, 'em_impressao');
      expect(a.contador, '4 de 5 artes');
      expect(a.temPecas, isTrue);
    });

    test('documento capenga não quebra a ficha do stand', () {
      final a = ArtStatus.fromMap({});
      expect(a.estado, 'sem_pecas');
      expect(a.total, 0);
      expect(a.contador, '', reason: 'sem peça, "0 de 0" só parece defeito');
    });

    test('o rótulo vem da ferramenta, não é traduzido aqui', () {
      // Se o app traduzisse por conta própria, um estado novo apareceria como
      // caixa vazia até alguém publicar um APK.
      final a = ArtStatus.fromMap({'estado': 'estado_que_ainda_nao_existe', 'rotulo': 'Texto novo'});
      expect(a.rotulo, 'Texto novo');
    });
  });

  test('recarregar a feira não perde o status da arte', () {
    // `reidentify` reconstrói o Client quando a feira é lida de outro
    // aparelho. Sem carregar o status junto, a faixa sumia da ficha sem
    // ninguém entender por quê.
    final c = stand(arte: daFerramenta);
    final outro = c.reidentify(2, '2_1');
    expect(outro.arte?.linkProva, 'https://ferramenta/prova-nova.png');
  });
}
