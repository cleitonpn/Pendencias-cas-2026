import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/client.dart';

class SheetsService {
  static const _spreadsheetId =
      '1Q5jLjT7zQ2zIlf2udS3XIHHLc4o4Qjz9LvZOEIJ3XkE';
  static const _keyApiKey = 'google_api_key';
  static const _keySheetName = 'sheet_name';

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiKey) ?? '';
  }

  static Future<String> getSheetName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySheetName) ?? 'Sheet1';
  }

  static Future<void> saveSettings(String apiKey, String sheetName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, apiKey.trim());
    await prefs.setString(
        _keySheetName, sheetName.trim().isEmpty ? 'Sheet1' : sheetName.trim());
  }

  static Future<List<Client>> fetchClients() async {
    final apiKey = await getApiKey();
    final sheetName = await getSheetName();

    if (apiKey.isEmpty) throw Exception('Chave de API não configurada.');

    final ranges = [
      Uri.encodeComponent('$sheetName!B:I'),
      Uri.encodeComponent('$sheetName!O:T'),
    ].map((r) => 'ranges=$r').join('&');

    final uri = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$_spreadsheetId/values:batchGet?$ranges&key=$apiKey');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final msg = (body['error'] as Map?)?.containsKey('message') == true
          ? body['error']['message']
          : 'Erro HTTP ${response.statusCode}';
      throw Exception(msg);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final ranges2 = data['valueRanges'] as List;

    final bToIRows = (ranges2[0]['values'] as List?) ?? [];
    final oToTRows = (ranges2[1]['values'] as List?) ?? [];

    final clients = <Client>[];
    for (int i = 1; i < bToIRows.length; i++) {
      final bToI = bToIRows[i] as List;
      final oToT = i < oToTRows.length ? oToTRows[i] as List : <dynamic>[];

      // Skip empty rows (no name and no stand)
      if (bToI.isEmpty) continue;
      final name = bToI.isNotEmpty ? bToI[0]?.toString().trim() ?? '' : '';
      final stand = bToI.length > 1 ? bToI[1]?.toString().trim() ?? '' : '';
      if (name.isEmpty && stand.isEmpty) continue;

      clients.add(Client.fromSheetRow(bToI, oToT, i));
    }

    return clients;
  }
}
