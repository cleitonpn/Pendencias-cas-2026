import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/client.dart';

class SheetsService {
  static const _spreadsheetId =
      '1Q5jLjT7zQ2zIlf2udS3XIHHLc4o4Qjz9LvZOEIJ3XkE';

  // Usa a API pública do Google Visualization (gviz) — sem precisar de API Key
  // A planilha precisa estar como "qualquer pessoa com o link pode visualizar"
  static String _gvizUrl(String range) =>
      'https://docs.google.com/spreadsheets/d/$_spreadsheetId/gviz/tq'
      '?tqx=out:json&range=${Uri.encodeComponent(range)}';

  static Future<List<List<dynamic>>> _fetchRange(String range) async {
    final response = await http
        .get(Uri.parse(_gvizUrl(range)))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Erro ao acessar a planilha (HTTP ${response.statusCode}).\n'
          'Verifique se ela está compartilhada como "qualquer pessoa pode visualizar".');
    }

    // A resposta vem como JSONP: /*O_o*/\ngoogle.visualization.Query.setResponse({...});
    // Precisamos extrair apenas o JSON interno
    final body = response.body;
    final start = body.indexOf('(') + 1;
    final end = body.lastIndexOf(')');
    if (start <= 0 || end <= start) {
      throw Exception('Formato de resposta inválido. Verifique as permissões da planilha.');
    }

    final json = jsonDecode(body.substring(start, end)) as Map<String, dynamic>;

    if (json['status'] == 'error') {
      final errors = json['errors'] as List?;
      final msg = errors?.isNotEmpty == true
          ? errors!.first['detailed_message'] ?? errors.first['message']
          : 'Erro desconhecido';
      throw Exception('Erro na planilha: $msg');
    }

    final table = json['table'] as Map<String, dynamic>;
    final rows = (table['rows'] as List?) ?? [];

    return rows.map((row) {
      final cells = (row['c'] as List?) ?? [];
      return cells.map((cell) {
        if (cell == null) return '';
        final v = (cell as Map)['v'];
        if (v == null) return '';
        // gviz retorna números como double mesmo para inteiros
        if (v is double) {
          return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
        }
        return v.toString().trim();
      }).toList();
    }).toList();
  }

  static Future<List<Client>> fetchClients() async {
    // Busca B:I e O:T em paralelo para ser mais rápido
    final results = await Future.wait([
      _fetchRange('B:I'),
      _fetchRange('O:T'),
    ]);

    final bToIRows = results[0];
    final oToTRows = results[1];

    final clients = <Client>[];

    // Linha 0 é o cabeçalho — começa em 1
    for (int i = 1; i < bToIRows.length; i++) {
      final bToI = bToIRows[i];
      final oToT = i < oToTRows.length ? oToTRows[i] : <dynamic>[];

      // Ignora linhas sem nome
      final nome = bToI.isNotEmpty ? bToI[0].toString().trim() : '';
      if (nome.isEmpty) continue;

      clients.add(Client.fromSheetRow(bToI, oToT, i));
    }

    return clients;
  }
}
