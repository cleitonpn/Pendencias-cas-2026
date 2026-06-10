import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/client.dart';

class SheetsService {
  // headers=1: the Google Sheets gviz API designates the first row as the
  // header and returns each column's name in `table.cols[].label`. Reading the
  // header from the labels (instead of from a data row) is essential because a
  // numeric column (e.g. m²) returns a NULL value for its text header cell,
  // which would otherwise make the column name disappear.
  static String _gvizUrl(
          String spreadsheetId, String sheetName, String range) =>
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq'
      '?tqx=out:json&headers=1&sheet=${Uri.encodeComponent(sheetName)}&range=${Uri.encodeComponent(range)}';

  static String _cellToString(dynamic cell) {
    if (cell == null) return '';
    final cellMap = cell as Map;
    final f = cellMap['f'] as String?;
    // If the cell has a HYPERLINK formula, extract the URL (first quoted arg)
    if (f != null) {
      final upper = f.trim().toUpperCase();
      if (upper.startsWith('HYPERLINK(') || upper.startsWith('=HYPERLINK(')) {
        final match = RegExp(r'"([^"]+)"').firstMatch(f);
        if (match != null) return match.group(1)!;
      }
    }
    final v = cellMap['v'];
    if (v == null) return '';
    if (v is double) {
      return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString().trim();
  }

  /// Returns the column header labels and the data rows (header excluded).
  static Future<({List<String> header, List<List<dynamic>> rows})> _fetchTable(
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
    final cols = (table['cols'] as List?) ?? [];
    final header = cols
        .map((c) => ((c as Map)['label'] ?? '').toString())
        .toList();

    final rawRows = (table['rows'] as List?) ?? [];
    final rows = rawRows.map((row) {
      final cells = (row['c'] as List?) ?? [];
      return cells.map(_cellToString).toList();
    }).toList();

    return (header: header, rows: rows);
  }

  /// Reads a wide range (B:T) and auto-detects column positions from the header
  /// row, so it works for CAS 2026, Forum, PetVet and any future fair layout.
  static Future<List<Client>> fetchClients({
    required String spreadsheetId,
    required String sheetName,
    required int fairId,
  }) async {
    final table = await _fetchTable(spreadsheetId, sheetName, 'A:BZ');
    final dataRows = table.rows;
    if (table.header.isEmpty) {
      throw Exception(
          'Planilha vazia ou aba "$sheetName" não encontrada.\n'
          'Verifique o nome da aba e as permissões de compartilhamento.');
    }

    // Column names come from the header labels (case-insensitive)
    final header =
        table.header.map((v) => v.toString().toLowerCase().trim()).toList();

    int findCol(List<String> variants) {
      for (final v in variants) {
        final idx = header.indexOf(v);
        if (idx >= 0) return idx;
      }
      return -1;
    }

    final nomeIdx     = findCol(['nome']);
    final montagemIdx = findCol(['montagem']);
    final localIdx    = findCol(['local']);
    final hangarIdx   = findCol(['hangar']);
    // Robust m²/área detection independent of how the superscript is encoded:
    // matches "área"/"area"/"metragem" or "m" followed by 1–2 NON-letter chars
    // (m², m2, m³…). This way any encoding of the "²" character is recognized.
    int areaIdx = -1;
    for (var i = 0; i < header.length; i++) {
      final h = header[i].replaceAll(' ', '');
      final isArea = h == 'area' ||
          h == 'área' ||
          h.contains('metr') ||
          (h.startsWith('m') &&
              h.length >= 2 &&
              h.length <= 3 &&
              !RegExp(r'[a-zà-ÿ]').hasMatch(h.substring(1)));
      if (isArea) {
        areaIdx = i;
        break;
      }
    }
    final produtorIdx = findCol(['produtor']);
    final atendIdx    = findCol(['atendimento', 'consultor', 'atendimento responsável', 'atendimento responsavel']);
    final organizadoraIdx = findCol(['organizadora', 'organizador', 'organização', 'organizacao']);
    final pinIdx      = findCol(['pin', 'senha', 'código', 'codigo', 'pin stand', 'pin acesso']);
    final marceIdx    = findCol(['marceneiro']);
    final tapecIdx    = findCol(['tapeceiro']);
    final eletrIdx    = findCol(['eletricista']);
    final faxiIdx     = findCol(['faxineira']);
    final linkIdx      = findCol(['link', 'projeto link', 'link projeto', 'link do projeto']);
    final linkCvIdx    = findCol([
      'link comunicação visual', 'link comunicacao visual',
      'link cv', 'link print cv', 'print cv',
    ]);
    final mobilarioIdx = findCol(['mobiliário locado', 'mobiliario locado', 'mobiliário', 'mobiliario']);

    if (nomeIdx < 0) {
      throw Exception(
          'Coluna "nome" não encontrada na aba "$sheetName".\n'
          'Verifique se o nome da aba está correto e se a planilha tem cabeçalho.');
    }

    final clients = <Client>[];

    for (int i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];

      String s(int idx) {
        if (idx < 0 || idx >= row.length) return '';
        return row[idx]?.toString().trim() ?? '';
      }

      // Normalizes a person name to Title Case so the casing in the spreadsheet
      // does not affect PIN lookups (which use the name as a Firestore doc ID).
      // "RENAN" → "Renan"  |  "JOÃO PEDRO" → "João Pedro"
      String n(int idx) {
        final raw = s(idx);
        if (raw.isEmpty) return raw;
        return raw.split(' ').map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        }).join(' ');
      }

      final nome = s(nomeIdx);
      if (nome.isEmpty) continue;

      // Normalize EXT hangars: "EXT 1" → "1", "EXT 3" → "3"
      String hangar = s(hangarIdx);
      if (hangar.isNotEmpty) {
        final m = RegExp(r'^(?:EXT|Ext)\.?\s+(\S+)$').firstMatch(hangar);
        if (m != null) hangar = m.group(1)!;
      }

      clients.add(Client(
        fairId: fairId,
        // +1 keeps rowIds identical to the previous scheme (where row 0 was the
        // header), so existing pending items stay linked to their clients.
        rowId: '${fairId}_${i + 1}',
        nome: nome,
        montagem: s(montagemIdx),
        local: s(localIdx),
        hangar: hangar,
        area: s(areaIdx),
        deck: '',
        totalArea: '',
        mezanino: '',
        produtor: n(produtorIdx),
        atendimento: n(atendIdx),
        organizadora: n(organizadoraIdx),
        pin: s(pinIdx),
        marceneiro: n(marceIdx),
        tapeceiro: n(tapecIdx),
        eletricista: n(eletrIdx),
        faxineira: n(faxiIdx),
        teto50: '',
        projectLink: s(linkIdx),
        linkCv: s(linkCvIdx),
        mobilario: s(mobilarioIdx),
      ));
    }

    return clients;
  }
}
