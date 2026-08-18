/// A rua do stand, tirada do próprio código dele.
///
/// Não existe coluna de rua na planilha: a rua está dentro da localização.
/// "B50" é o stand 50 da rua B, "A 12" é o 12 da rua A. A parte de letras
/// antes do número é a rua.
///
/// Serve para a OS da feira sair separada por rua, que é como a entrega
/// acontece de verdade — quem descarrega percorre uma rua por vez, e uma
/// lista fora de ordem faz a pessoa atravessar o pavilhão a cada item.
///
/// Stand só com número não tem rua, e é isso que devolve: [semRua]. Inventar
/// uma agruparia stands que não têm nada a ver um com o outro.
String ruaDe(String local) {
  final m = RegExp(r'^([^0-9]+)').firstMatch(local.trim());
  if (m == null) return semRua;
  final rua = m
      .group(1)!
      // Separador entre a rua e o número ("RUA C - 3") não faz parte do nome.
      .replaceAll(RegExp(r'[\s\-_.]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toUpperCase();
  return rua.isEmpty ? semRua : rua;
}

/// Rótulo dos stands cuja localização não começa por letra.
const semRua = 'Sem rua';

/// Ordena ruas de um jeito que faz sentido no papel: "A", "B", … e o
/// [semRua] por último, porque é a sobra e não uma rua de verdade.
int compararRuas(String a, String b) {
  if (a == b) return 0;
  if (a == semRua) return 1;
  if (b == semRua) return -1;
  return a.compareTo(b);
}

/// Ordena stands da mesma rua pelo número, não pelo texto.
///
/// Em ordem alfabética "B10" vem antes de "B9", e a lista impressa manda a
/// pessoa voltar no meio da rua.
int compararStands(String a, String b) {
  final na = _numeroDe(a);
  final nb = _numeroDe(b);
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  if (na != null && nb == null) return -1;
  if (na == null && nb != null) return 1;
  return a.compareTo(b);
}

int? _numeroDe(String local) {
  final m = RegExp(r'(\d+)').firstMatch(local);
  return m == null ? null : int.tryParse(m.group(1)!);
}
