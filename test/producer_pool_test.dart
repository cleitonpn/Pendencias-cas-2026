import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/producer_pool.dart';

void main() {
  group('produtoresFrom', () {
    test('um nome só continua sendo um nome só', () {
      expect(produtoresFrom('Cleiton'), ['Cleiton']);
    });

    test('separa por vírgula e tira o espaço sobrando', () {
      expect(produtoresFrom('Cleiton, Ana Paula'), ['Cleiton', 'Ana Paula']);
      expect(produtoresFrom('Cleiton ,Ana'), ['Cleiton', 'Ana']);
    });

    test('mantém a ordem da planilha', () {
      // O primeiro nome é o dono padrão. Se a ordem mudasse, o dono mudaria
      // junto a cada sincronização.
      expect(produtoresFrom('Ana, Cleiton').first, 'Ana');
      expect(produtoresFrom('Cleiton, Ana').first, 'Cleiton');
    });

    test('não repete a mesma pessoa', () {
      // "Ana, ana" é uma pessoa só; repetida, ela apareceria duas vezes no
      // seletor de transferência.
      expect(produtoresFrom('Ana, ana, ANA'), ['Ana']);
    });

    test('descarta vazios de vírgula sobrando', () {
      expect(produtoresFrom('Cleiton, , Ana,'), ['Cleiton', 'Ana']);
      expect(produtoresFrom(''), isEmpty);
      expect(produtoresFrom(' , '), isEmpty);
    });
  });

  group('ownerFrom', () {
    const pool = ['Cleiton', 'Ana Paula'];

    test('sem transferência, o dono é o primeiro da planilha', () {
      expect(ownerFrom(pool, null), 'Cleiton');
      expect(ownerFrom(pool, ''), 'Cleiton');
    });

    test('com transferência, o dono é quem recebeu', () {
      expect(ownerFrom(pool, 'Ana Paula'), 'Ana Paula');
    });

    test('a transferência vale ignorando caixa e espaço', () {
      expect(ownerFrom(pool, '  ana paula '), 'Ana Paula');
    });

    test('devolve o nome como está na planilha, não como veio gravado', () {
      // O nome exibido tem de bater com o da planilha, senão a mesma pessoa
      // apareceria escrita de dois jeitos entre telas.
      expect(ownerFrom(pool, 'ANA PAULA'), 'Ana Paula');
    });

    test('quem saiu da planilha perde a titularidade', () {
      // Tirar alguém da planilha precisa devolver o stand a quem ficou; senão
      // ele seguiria com um dono que não trabalha mais nele.
      expect(ownerFrom(pool, 'Fulano'), 'Cleiton');
    });

    test('stand sem produtor não inventa dono', () {
      expect(ownerFrom(const [], 'Ana'), '');
    });
  });
}
