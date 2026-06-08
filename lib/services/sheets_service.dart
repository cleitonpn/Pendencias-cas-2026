import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/client.dart';

class SheetsService {
  static String _gvizUrl(String spreadsheetId, String sheetName, String range) =>
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq'
      '?tqx=out:json&headers=0&sheet=${Uri.encodeComponent(sheetName)}&range=${Uri.encodeComponent(range)}';

  static Future<List<List<dynamic>>> _fetchRange(
      String spreadsheetId, String sheetName, String range) async {
    final response = await http
        .get(Uri.parse(_gvizUrl(spreadsheetId, sheetName, range)))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
          'Erro ao acessar a planilha (HTTP ${response.statusCode}).\n'
          'Verifique se ela está compartilhada como "qualquer pessoa pode visualizar".');
    }

    final body = response.body;
    final start = body.indexOf('(') + 1;
    final end = body.lastIndexOf(')');
    if (start <= 0 || end <= start) {
      throw Exception(
          'Formato de resposta inválido. Verifique as permissões da planilha.');
    }

    final json =
        jsonDecode(body.substring(start, end)) as Map<String, dynamic>;

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
        if (v is double) {
          return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
        }
        return v.toString().trim();
      }).toList();
    }).toList();
  }

  static Future<List<Client>> fetchClients({
    required String spreadsheetId,
    required String sheetName,
    required int fairId,
  }) async {
    // Fetch B:I (client info) and P:T (team responsibles) in parallel
    final results = await Future.wait([
      _fetchRange(spreadsheetId, sheetName, 'B:I'),
      _fetchRange(spreadsheetId, sheetName, 'P:T'),
    ]);

    final bToIRows = results[0];
    final oToTRows = results[1];

    final clients = <Client>[];

    // Row 0 is the header — start at 1
    for (int i = 1; i < bToIRows.length; i++) {
      final rawRow = bToIRows[i];
      final oToT = i < oToTRows.length ? oToTRows[i] : <dynamic>[];

      final nome = rawRow.isNotEmpty ? rawRow[0].toString().trim() : '';
      if (nome.isEmpty) continue;

      // Normalize EXT hangars: "EXT 1" → "1", "EXT 3" → "3"
      final bToI = List<dynamic>.from(rawRow);
      if (bToI.length > 3) {
        final h = bToI[3].toString().trim();
        final extMatch = RegExp(r'^(?:EXT|Ext)\.?\s+(\S+)$').firstMatch(h);
        if (extMatch != null) bToI[3] = extMatch.group(1)!;
      }

      clients.add(Client.fromSheetRow(bToI, oToT, i, fairId: fairId));
    }

    return clients;
  }
}
