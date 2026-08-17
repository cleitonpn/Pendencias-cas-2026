import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/furniture_items.dart';

void main() {
  group('quebra da coluna', () {
    test('separa pela barra e limpa o espaço sobrando', () {
      final itens = furnitureItemsFrom('4 cadeiras dkr / 1 mesa dkr / 1 geladeira');
      expect(itens.map((i) => i.raw),
          ['4 cadeiras dkr', '1 mesa dkr', '1 geladeira']);
    });

    test('espaço duplo da planilha real não cria item diferente', () {
      // Copiado de um stand de verdade: "1 geladeira duplex  / 1 cooktop".
      final a = furnitureItemsFrom('1 geladeira duplex  / 1 cooktop');
      final b = furnitureItemsFrom('1 geladeira duplex / 1 cooktop');
      expect(a.first.key, b.first.key);
    });

    test('barra sobrando não vira item vazio', () {
      expect(furnitureItemsFrom('1 mesa / / 2 cadeiras /').length, 2);
      expect(furnitureItemsFrom(''), isEmpty);
      expect(furnitureItemsFrom('  /  '), isEmpty);
    });

    test('coluna sem barra é um item só', () {
      expect(furnitureItemsFrom('1 geladeira').single.raw, '1 geladeira');
    });
  });

  group('identidade do item', () {
    test('não muda com acento nem caixa', () {
      // Corrigir "estantes de aco" para "estantes de aço" não pode
      // desclassificar o item.
      expect(furnitureKey('5 estantes de aço'), furnitureKey('5 ESTANTES DE ACO'));
    });

    test('itens diferentes têm chaves diferentes', () {
      expect(furnitureKey('1 mesa dkr') == furnitureKey('1 mesa torre'), isFalse);
    });

    test('o mesmo item repetido no stand ganha chaves distintas', () {
      // "1 cadeira / 1 cadeira" são duas linhas de verdade; com a mesma
      // chave, classificar uma classificaria a outra.
      final itens = furnitureItemsFrom('1 cadeira / 1 cadeira');
      expect(itens.length, 2);
      expect(itens[0].key == itens[1].key, isFalse);
    });

    test('a chave não depende da posição', () {
      // Inserir um item no meio da planilha não pode reclassificar o resto.
      final antes = furnitureItemsFrom('1 mesa / 1 geladeira');
      final depois = furnitureItemsFrom('1 mesa / 4 cadeiras / 1 geladeira');
      expect(depois.last.key, antes.last.key);
    });
  });

  group('quantidade', () {
    test('número no começo vira contagem', () {
      expect(furnitureItemsFrom('4 cadeiras dkr').single.qtd, 4);
    });

    test('medida não vira contagem', () {
      // "10m linear jardim" são dez metros, não dez unidades. Somar isso com
      // cadeiras daria um total sem significado.
      expect(furnitureItemsFrom('10m linear jardim').single.qtd, isNull);
    });

    test('item sem número não inventa quantidade', () {
      expect(furnitureItemsFrom('geladeira duplex').single.qtd, isNull);
    });

    test('o texto impresso guarda a quantidade original', () {
      expect(furnitureItemsFrom('10m linear jardim').single.raw,
          '10m linear jardim');
    });
  });

  group('aviso de quebra suspeita', () {
    test('item muito longo é marcado para conferência', () {
      final longo = furnitureItemsFrom('1 ${'mesa muito comprida ' * 5}');
      expect(longo.single.suspeito, isTrue);
    });

    test('item normal não é marcado', () {
      expect(furnitureItemsFrom('4 cadeiras dkr').single.suspeito, isFalse);
    });
  });

  group('interno x externo', () {
    test('lê o que está gravado', () {
      expect(furnitureKindFrom('interno'), FurnitureKind.interno);
      expect(furnitureKindFrom('externo'), FurnitureKind.externo);
    });

    test('reconhece o item descartado', () {
      expect(furnitureKindFrom('nao_mobiliario'), FurnitureKind.naoMobiliario);
    });

    test('só interno e externo entram em OS e em pendência', () {
      // O descartado é uma observação na coluna, não um item para alguém
      // atender: se entrasse na OS, viraria papel pedindo o que não existe.
      expect(FurnitureKind.interno.atendivel, isTrue);
      expect(FurnitureKind.externo.atendivel, isTrue);
      expect(FurnitureKind.naoMobiliario.atendivel, isFalse);
    });

    test('o código gravado é estável', () {
      // É ele que está no Firestore; mudar renomearia a classificação de
      // todos os stands já feitos.
      expect(FurnitureKind.interno.code, 'interno');
      expect(FurnitureKind.externo.code, 'externo');
      expect(FurnitureKind.naoMobiliario.code, 'nao_mobiliario');
    });

    test('item ainda não classificado devolve null, não um padrão', () {
      // Assumir "interno" por omissão mandaria para o estoque um item que
      // ninguém conferiu.
      expect(furnitureKindFrom(null), isNull);
      expect(furnitureKindFrom('qualquer coisa'), isNull);
    });
  });

  group('item marcado na pendência', () {
    test('vai e volta pelo Firestore sem perder nada', () {
      const p = FurniturePick(
          key: 'balcao_vitrine', raw: '1 balcão vitrine',
          kind: FurnitureKind.externo);
      final volta = furniturePicksFrom([p.toMap()]).single;
      expect(volta.key, p.key);
      expect(volta.raw, p.raw);
      expect(volta.kind, FurnitureKind.externo);
    });

    test('vai e volta pelo SQLite, que guarda JSON', () {
      const p = FurniturePick(
          key: 'mesa', raw: '1 mesa dkr', kind: FurnitureKind.interno);
      final json = jsonEncode([p.toMap()]);
      expect(furniturePicksFrom(json).single.kind, FurnitureKind.interno);
    });

    test('item marcado antes de ser classificado não vira interno', () {
      // O chamado pode ser aberto pelo expositor antes de a equipe classificar
      // o stand. Inventar um lado aqui contaria o problema no time errado.
      const p = FurniturePick(key: 'geladeira', raw: '1 geladeira');
      final volta = furniturePicksFrom([p.toMap()]).single;
      expect(volta.kind, isNull);
      expect(volta.kindLabel, 'Sem classificação');
    });

    test('a classificação gravada não muda quando o item é reclassificado', () {
      // O relatório responde "onde deu problema", e isso é o que valia na
      // hora. Se o item virar externo depois, o chamado antigo continua
      // contando como interno.
      const noChamado = FurniturePick(
          key: 'balcao', raw: '1 balcão', kind: FurnitureKind.interno);
      final agora = {'balcao': 'externo'};
      final volta = furniturePicksFrom([noChamado.toMap()]).single;
      expect(volta.kind, FurnitureKind.interno);
      expect(furnitureKindFrom(agora['balcao']), FurnitureKind.externo);
    });

    test('lista quebrada não derruba o chamado', () {
      // Melhor um chamado sem os itens do que um chamado que não abre.
      expect(furniturePicksFrom('isso não é json'), isEmpty);
      expect(furniturePicksFrom(null), isEmpty);
      expect(furniturePicksFrom(''), isEmpty);
      expect(furniturePicksFrom(42), isEmpty);
      expect(furniturePicksFrom([{'key': 'x'}]), isEmpty); // sem texto
    });
  });
}
