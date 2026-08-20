import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/models/client.dart';
import 'package:montagem_uset/utils/client_fingerprint.dart';

/// A coluna "elétrica" e a coluna "eletricista" são duas coisas diferentes:
/// uma é a especificação da instalação, a outra é a pessoa que instala. Só a
/// segunda chegava ao app, e trocar uma pela outra faria a equipe montar o
/// stand sem saber quantos pontos precisa.
Client _stand({String eletrica = '', String eletricista = ''}) => Client(
      rowId: '1_5',
      firestoreId: 'abf_5',
      nome: 'PINTA MUNDI',
      montagem: '',
      local: '35B',
      hangar: 'A',
      area: '30',
      deck: '',
      totalArea: '30',
      mezanino: '',
      produtor: 'Cleiton',
      marceneiro: '',
      tapeceiro: '',
      eletricista: eletricista,
      faxineira: '',
      teto50: '',
      eletrica: eletrica,
    );

void main() {
  test('a especificação sobrevive à ida e volta pelo banco', () {
    final volta = Client.fromMap(
        _stand(eletrica: '4 tomadas 220v / 1 ponto trifásico').toMap());
    expect(volta.eletrica, '4 tomadas 220v / 1 ponto trifásico');
  });

  test('elétrica e eletricista não se misturam', () {
    final c = _stand(eletrica: '3 pontos 110v', eletricista: 'Rodrigo');
    final volta = Client.fromMap(c.toMap());
    expect(volta.eletrica, '3 pontos 110v');
    expect(volta.eletricista, 'Rodrigo');
  });

  test('stand sem a coluna preenchida não quebra', () {
    expect(Client.fromMap(_stand().toMap()).eletrica, '');
  });

  test('mudar a elétrica na planilha marca o stand como alterado', () {
    // Sem entrar na assinatura, corrigir a carga na planilha nunca subiria
    // para os outros aparelhos: cada um continuaria mostrando o valor antigo.
    expect(
      clientFingerprint(_stand(eletrica: '3 pontos')) ==
          clientFingerprint(_stand(eletrica: '5 pontos')),
      isFalse,
    );
  });
}
