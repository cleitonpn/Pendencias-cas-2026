import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/client_key.dart';

/// A chave que liga este app à ferramenta de aprovação de arte.
///
/// Os casos aqui são exatamente os de tools/client_key_parity.test.js, que
/// roda no CI. Divergir em um caractere faz a ponte não casar nada — sem erro
/// em lugar nenhum, igual ao que já aconteceu com os tópicos FCM.
void main() {
  group('normalização', () {
    test('acento é convertido, não apagado', () {
      // O `_normalize` de sheets_service (usado no firestoreId) APAGA o
      // caractere acentuado: "Módulos" vira "mdulos". Se a chave fizesse o
      // mesmo, ela dependeria de os dois lados errarem igual.
      expect(normalizeKeyPart('Módulos'), 'modulos');
      expect(normalizeKeyPart('Comunicação'), 'comunicacao');
      expect(normalizeKeyPart('São Paulo'), 'sao_paulo');
      expect(normalizeKeyPart('Açaí'), 'acai');
    });

    test('caixa e espaço sobrando não mudam a chave', () {
      expect(normalizeKeyPart(' JADLOG '), normalizeKeyPart('jadlog'));
    });

    test('pontuação seguida vira um sublinhado só, e não sobra nas pontas', () {
      expect(normalizeKeyPart('-- Selia --'), 'selia');
      expect(normalizeKeyPart('A  &&  B'), 'a_b');
    });
  });

  group('a chave', () {
    test('casos de referência, os mesmos do JS', () {
      expect(clientKeyFor(fairName: 'ABAV', nome: 'JadLog'), 'abav__jadlog');
      expect(clientKeyFor(fairName: 'ABAV', nome: 'JADLOG'), 'abav__jadlog');
      expect(clientKeyFor(fairName: 'ABAV', nome: ' jadlog '), 'abav__jadlog');
      expect(
          clientKeyFor(fairName: 'CAS 2026 Módulos', nome: 'Comunicação'),
          'cas_2026_modulos__comunicacao');
      expect(
          clientKeyFor(fairName: 'Conferencia Luxo — ECBR', nome: 'J&T'),
          'conferencia_luxo_ecbr__j_t');
      expect(clientKeyFor(fairName: 'São Paulo', nome: 'Açaí & Cia'),
          'sao_paulo__acai_cia');
      expect(clientKeyFor(fairName: '  ABAV  ', nome: '-- Selia --'),
          'abav__selia');
      expect(clientKeyFor(fairName: 'ABAV', nome: 'Tray  Commerce'),
          'abav__tray_commerce');
    });

    test('sem uma das partes não há chave', () {
      // Meia chave ligaria coisas que não têm relação nenhuma.
      expect(clientKeyFor(fairName: '', nome: 'JadLog'), '');
      expect(clientKeyFor(fairName: 'ABAV', nome: ''), '');
      expect(clientKeyFor(fairName: 'ABAV', nome: '   '), '');
      expect(clientKeyFor(fairName: 'ABAV', nome: '###'), '');
    });

    test('o separador nunca fica ambíguo', () {
      expect(clientKeyFor(fairName: 'feira a', nome: 'b') ==
              clientKeyFor(fairName: 'feira', nome: 'a b'),
          isFalse);
    });

    test('não depende da posição na planilha', () {
      // É o ponto inteiro: o firestoreId muda quando alguém insere uma linha
      // acima; a chave não.
      expect(clientKeyFor(fairName: 'ABAV', nome: 'Selia'),
          clientKeyFor(fairName: 'ABAV', nome: 'Selia'));
    });
  });

  group('nomes repetidos na mesma feira', () {
    test('nenhum dos dois recebe chave', () {
      // Desempatar por posição resolveria na aparência e traria de volta a
      // fragilidade que a chave existe para eliminar — agora invisível.
      final chaves = clientKeysFor('ABAV', ['Selia', 'SELIA', 'Tray']);
      expect(chaves.containsKey('selia'), isFalse);
      expect(chaves['tray'], 'abav__tray');
    });

    test('os ambíguos ficam listados, para alguém poder resolver', () {
      expect(nomesAmbiguos(['Selia', 'selia', 'Tray']), ['selia']);
      expect(nomesAmbiguos(['Selia', 'Tray']), isEmpty);
    });

    test('nome vazio não conta como repetição', () {
      expect(nomesAmbiguos(['', '   ', 'Tray']), isEmpty);
    });
  });

  group('o documento é deste cliente?', () {
    const chave = 'abav__jadlog';

    test('carimbo que bate é aceito', () {
      expect(
          documentoDoCliente({'clientKey': chave, 'clientName': 'JadLog'},
              clientKey: chave, nome: 'JadLog'),
          isTrue);
    });

    test('carimbo de outro stand é recusado', () {
      // É o caso que interessa: depois de uma reordenação, o documento sob
      // aquele id é de outra empresa.
      expect(
          documentoDoCliente({'clientKey': 'abav__selia'},
              clientKey: chave, nome: 'JadLog'),
          isFalse);
    });

    test('sem chave, o nome ainda confere', () {
      expect(
          documentoDoCliente({'clientName': 'Selia'},
              clientKey: chave, nome: 'JadLog'),
          isFalse);
      expect(
          documentoDoCliente({'clientName': 'JADLOG'},
              clientKey: chave, nome: 'JadLog'),
          isTrue);
    });

    test('documento antigo, sem carimbo nenhum, é aceito', () {
      // Recusar apagaria da tela todo check-off e toda anotação que já estão
      // gravados: trocaria um erro raro por uma perda geral e imediata.
      expect(
          documentoDoCliente({'completed': true},
              clientKey: chave, nome: 'JadLog'),
          isTrue);
    });

    test('documento inexistente não é de ninguém', () {
      expect(documentoDoCliente(null, clientKey: chave, nome: 'JadLog'),
          isFalse);
    });

    test('cliente sem chave ainda confere pelo nome', () {
      // Expositor cujo nome repete na feira não tem chave; o carimbo de nome
      // continua protegendo.
      expect(
          documentoDoCliente({'clientKey': 'abav__selia', 'clientName': 'Selia'},
              clientKey: '', nome: 'JadLog'),
          isFalse);
    });
  });

  group('o caso real de 30/08 — deslocamento de 2 posições', () {
    // Log da sincronização, feira Conferencia Luxo — ECBR: 10 stands
    // deslocados duas posições porque duas linhas saíram do topo. O documento
    // sob "_15" foi escrito para a JadLog e hoje o "_15" é a Selia.
    const feira = 'Conferencia Luxo — ECBR';
    final daJadlog = {
      'clientKey': clientKeyFor(fairName: feira, nome: 'JadLog'),
      'clientName': 'JadLog',
    };

    test('a Selia não recebe o documento da JadLog', () {
      expect(
        documentoDoCliente(daJadlog,
            clientKey: clientKeyFor(fairName: feira, nome: 'Selia'),
            nome: 'Selia'),
        isFalse,
      );
    });

    test('a JadLog continua recebendo o dela', () {
      expect(
        documentoDoCliente(daJadlog,
            clientKey: clientKeyFor(fairName: feira, nome: 'JadLog'),
            nome: 'JadLog'),
        isTrue,
      );
    });

    test('a chave não se move quando linhas saem do topo', () {
      // É o ponto: o firestoreId da JadLog foi de _15 para _13, a chave não.
      expect(clientKeyFor(fairName: feira, nome: 'JadLog'),
          'conferencia_luxo_ecbr__jadlog');
    });
  });

  group('o carimbo gravado', () {
    test('leva chave e nome', () {
      expect(carimboDoCliente(clientKey: 'abav__jadlog', nome: 'JadLog'),
          {'clientKey': 'abav__jadlog', 'clientName': 'JadLog'});
    });

    test('não grava campo vazio', () {
      // Um clientKey vazio gravado viraria "carimbo presente que não bate" e
      // recusaria o documento do próprio dono.
      expect(carimboDoCliente(clientKey: '', nome: 'JadLog'),
          {'clientName': 'JadLog'});
      expect(carimboDoCliente(clientKey: '', nome: '  '), isEmpty);
    });
  });
}
