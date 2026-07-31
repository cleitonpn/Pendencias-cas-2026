/// Produtores habilitados num stand, lidos da coluna `produtor` da planilha.
///
/// A planilha aceita mais de um nome separado por vírgula. Isso NÃO significa
/// que os dois são donos ao mesmo tempo: significa que os dois podem ser. O
/// dono atual é um só, e a transferência entre eles acontece dentro do app.
///
/// Foi por aí que a gente resolveu o caso de dois produtores no mesmo stand
/// sem duplicar métrica: quem entrega é quem encerra, e quem tem trabalho na
/// mão é quem está com a titularidade agora.
List<String> produtoresFrom(String raw) {
  final vistos = <String>{};
  final out = <String>[];
  for (final parte in raw.split(',')) {
    final nome = parte.trim();
    if (nome.isEmpty) continue;
    // Sem repetir, ignorando caixa: "Ana, ana" é uma pessoa só, e o seletor
    // de transferência mostraria o mesmo nome duas vezes.
    final chave = nome.toLowerCase();
    if (vistos.add(chave)) out.add(nome);
  }
  return out;
}

/// Quem é o dono do stand agora.
///
/// [override] é a transferência gravada no app. Ela só vale se a pessoa
/// continuar na lista da planilha — tirar alguém da planilha precisa devolver
/// o stand a quem ficou, senão o stand seguiria com um dono que não trabalha
/// mais nele.
///
/// Sem override, o dono é o primeiro nome da planilha.
String ownerFrom(List<String> pool, String? override) {
  if (pool.isEmpty) return '';
  final alvo = override?.trim().toLowerCase() ?? '';
  if (alvo.isNotEmpty) {
    for (final nome in pool) {
      if (nome.toLowerCase() == alvo) return nome;
    }
  }
  return pool.first;
}
