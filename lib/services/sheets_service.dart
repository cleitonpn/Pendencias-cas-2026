import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/client.dart';
import '../utils/client_key.dart';
import '../utils/producer_pool.dart';

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
        .map((c) => _normalizeHeader(((c as Map)['label'] ?? '').toString()))
        .toList();

    final rawRows = (table['rows'] as List?) ?? [];
    final rows = rawRows.map((row) {
      final cells = (row['c'] as List?) ?? [];
      return cells.map(_cellToString).toList();
    }).toList();

    return (header: header, rows: rows);
  }

  /// Strips hidden Unicode chars (BOM, non-breaking spaces, zero-width chars)
  /// that the gviz API occasionally embeds in column labels, then lowercases
  /// and trims so header matching is reliable regardless of sheet formatting.
  static String _normalizeHeader(String raw) => raw
      .replaceAll('﻿', '')   // BOM
      .replaceAll(' ', ' ')  // non-breaking space → regular space
      .replaceAll('​', '')   // zero-width space
      .replaceAll('‌', '')   // zero-width non-joiner
      .replaceAll('‍', '')   // zero-width joiner
      .replaceAll(' ', ' ')  // thin space → regular space
      .replaceAll(' ', ' ')  // narrow no-break space → regular space
      .toLowerCase()
      .trim();

  /// Shared helper: builds a findCol closure from a normalised header list.
  static int Function(List<String>) _makeFindCol(List<String> header) {
    return (List<String> variants) {
      for (final v in variants) {
        final idx = header.indexOf(v);
        if (idx >= 0) return idx;
      }
      return -1;
    };
  }

  /// Shared helper: robust m²/área detection independent of superscript encoding.
  static int _findAreaCol(List<String> header) {
    for (var i = 0; i < header.length; i++) {
      final h = header[i].replaceAll(' ', '');
      final isArea = h == 'area' ||
          h == 'área' ||
          h.contains('metr') ||
          (h.startsWith('m') &&
              h.length >= 2 &&
              h.length <= 3 &&
              !RegExp(r'[a-zà-ÿ]').hasMatch(h.substring(1)));
      if (isArea) return i;
    }
    return -1;
  }

  /// Normalises a fair name to a stable, device-independent string suitable for
  /// use as a Firestore document key prefix:
  /// "CAS 2026 – Módulos" → "cas_2026__mdulos"  (lowercased, spaces→_, non-alnum stripped)
  static String _normalize(String name) => name
      .toLowerCase()
      .trim()
      .replaceAll(' ', '_')
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');

  /// Reads a wide range (A:BZ) and auto-detects column positions from the header
  /// row, so it works for CAS 2026, Forum, PetVet and any future fair layout.
  /// Expositores de UMA feira, respeitando a origem da planilha.
  ///
  /// Numa feira derivada de planilha mestra, a aba contém todas as feiras
  /// juntas: [fetchClients] devolveria a planilha inteira. Os portais públicos
  /// caíam nisso — ao abrir uma feira vinda da mestra, apareciam os
  /// expositores de todas as outras.
  ///
  /// A reidentificação repete o que o app faz no sync da mestra. Sem ela, o
  /// pedido criado no portal apontaria para um cliente que o app não
  /// reconhece.
  static Future<List<Client>> fetchFairClients({
    required String spreadsheetId,
    required String sheetName,
    required int fairId,
    required String fairName,
    required bool isMestraChild,
  }) async {
    if (!isMestraChild) {
      return fetchClients(
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
        fairId: fairId,
        fairName: fairName,
      );
    }
    final grouped = await fetchClientsGroupedByFair(
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
    );
    final mine = grouped[fairName] ?? const <Client>[];
    return mine.map((c) {
      final rowNum = c.rowId.split('_').last;
      return c.reidentify(fairId, '${fairId}_$rowNum');
    }).toList();
  }

  static Future<List<Client>> fetchClients({
    required String spreadsheetId,
    required String sheetName,
    required int fairId,
    required String fairName,
  }) async {
    final table = await _fetchTable(spreadsheetId, sheetName, 'A:BZ');
    final dataRows = table.rows;
    if (table.header.isEmpty) {
      throw Exception(
          'Planilha vazia ou aba "$sheetName" não encontrada.\n'
          'Verifique o nome da aba e as permissões de compartilhamento.');
    }

    final header =
        table.header.map((v) => v.toString().toLowerCase().trim()).toList();
    final findCol = _makeFindCol(header);

    final nomeIdx        = findCol(['nome']);
    final montagemIdx    = findCol(['montagem']);
    // Nas feiras grandes a coluna "tipo" diz o que o stand é — informação que
    // a equipe procura antes de qualquer outra.
    final tipoIdx        = findCol(['tipo', 'type', 'tipo do stand',
        'tipo stand', 'tipo montagem', 'tipo de montagem']);
    final localIdx       = findCol(['local', 'localização', 'localizacao',
        'local stand', 'local do stand', 'localização stand']);
    final hangarIdx      = findCol(['hangar']);
    final areaIdx        = _findAreaCol(header);
    final produtorIdx    = findCol(['produtor']);
    final atendIdx       = findCol(['atendimento', 'consultor',
        'atendimento responsável', 'atendimento responsavel']);
    final organizadoraIdx = findCol(['organizadora', 'organizador',
        'organização', 'organizacao']);
    final pinIdx         = findCol(['pin', 'senha', 'código', 'codigo',
        'pin stand', 'pin acesso']);
    final marceIdx       = findCol(['marceneiro']);
    final tapecIdx       = findCol(['tapeceiro']);
    final eletrIdx       = findCol(['eletricista']);
    final faxiIdx        = findCol(['faxineira']);
    final linkIdx        = findCol(['link projeto', 'link', 'projeto link',
        'link do projeto']);
    final linkCvIdx      = findCol(['link comunicação visual',
        'link comunicacao visual', 'link cv', 'link print cv', 'print cv']);
    final linkMemorialIdx = findCol(['link memorial', 'memorial',
        'memorial descritivo', 'link do memorial']);
    final mobilarioIdx   = findCol(['mobiliário locado', 'mobiliario locado',
        'mobiliário', 'mobiliario']);
    final extrasIdx      = findCol(['extras', 'extra', 'itens extras',
        'itens adicionais']);
    // Balcões e cores: a planilha escreve de vários jeitos, com e sem acento.
    final balcaoPadraoIdx  = findCol(['balcão padrão', 'balcao padrao',
        'balcão padrao', 'balcao padrão', 'balcao', 'balcão']);
    final balcaoPersIdx    = findCol(['balcão personalizado',
        'balcao personalizado', 'balcão personalizado ',
        'balcao personalizado ', 'balcão customizado', 'balcao customizado']);
    final coresIdx         = findCol(['cores', 'cor', 'cores do stand',
        'cor do stand']);
    // A especificação elétrica do stand, não o nome do eletricista: são duas
    // colunas diferentes e a equipe precisa das duas.
    final eletricaIdx      = findCol(['elétrica', 'eletrica',
        'instalação elétrica', 'instalacao eletrica', 'ponto elétrico',
        'ponto eletrico', 'pontos elétricos', 'pontos eletricos']);

    // Event-level date columns.  'montagem'/'evento'/'desmontagem' alone are
    // accepted as fallbacks for sheets that don't use the "data " prefix.
    final pavilhaoIdx       = findCol(['pavilhão', 'pavilhao', 'paviliao',
        'pavilhao do evento']);
    final dataMontagemIdx   = findCol(['data montagem', 'data de montagem',
        'data_montagem', 'dt montagem', 'montagem']);
    final dataEventoIdx     = findCol(['data evento', 'data do evento',
        'data abertura', 'dt evento', 'evento']);
    final dataDesmontagemIdx = findCol(['data desmontagem',
        'data de desmontagem', 'desmontagem', 'dt desmontagem']);
    final linkPlantaIdx     = findCol(['link planta', 'link da planta',
        'planta baixa', 'mapa', 'planta']);
    final linkDriveIdx      = findCol(['link drive', 'drive',
        'link pasta', 'link do drive']);

    if (nomeIdx < 0) {
      throw Exception(
          'Coluna "nome" não encontrada na aba "$sheetName".\n'
          'Verifique se o nome da aba está correto e se a planilha tem cabeçalho.');
    }

    final clients = <Client>[];

    // A chave estável precisa saber, ANTES de montar a lista, quais nomes se
    // repetem na feira: nome repetido não recebe chave. Por isso a varredura
    // vem antes do laço.
    final chavesPorNome = clientKeysFor(
      fairName,
      dataRows.map((r) =>
          (nomeIdx >= 0 && nomeIdx < r.length ? r[nomeIdx] : null)
              ?.toString()
              .trim() ??
          ''),
    );

    for (int i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];

      String s(int idx) {
        if (idx < 0 || idx >= row.length) return '';
        return row[idx]?.toString().trim() ?? '';
      }

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
        rowId: '${fairId}_${i + 1}',
        firestoreId: '${_normalize(fairName)}_${i + 1}',
        // O firestoreId acima é a POSIÇÃO na aba: inserir uma linha reescreve
        // o de todo mundo abaixo. A clientKey não muda com isso.
        clientKey: chavesPorNome[normalizeKeyPart(nome)] ?? '',
        nome: nome,
        montagem: s(montagemIdx),
        tipo: s(tipoIdx),
        local: s(localIdx),
        hangar: hangar,
        area: s(areaIdx),
        deck: '',
        totalArea: '',
        mezanino: '',
        // A coluna aceita mais de um nome separado por vírgula. O primeiro
        // é o dono padrão; a transferência dentro do app troca esse valor.
        produtor: ownerFrom(produtoresFrom(n(produtorIdx)), null),
        produtores: produtoresFrom(n(produtorIdx)),
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
        linkMemorial: s(linkMemorialIdx),
        mobilario: s(mobilarioIdx),
        extras: s(extrasIdx),
        balcaoPadrao: s(balcaoPadraoIdx),
        balcaoPersonalizado: s(balcaoPersIdx),
        cores: s(coresIdx),
        eletrica: s(eletricaIdx),
        pavilhao: s(pavilhaoIdx),
        dataMontagem: s(dataMontagemIdx),
        dataEvento: s(dataEventoIdx),
        dataDesmontagem: s(dataDesmontagemIdx),
        linkPlanta: s(linkPlantaIdx),
        linkDrive: s(linkDriveIdx),
      ));
    }

    return clients;
  }

  /// Reads a master spreadsheet that has a FEIRA column and groups clients by
  /// fair name. Returns a map of feiraNome → clients (with fairId=0 and rowId
  /// '0_N' as placeholders — the caller must call [Client.reidentify] with the
  /// real derived fair IDs before persisting).
  ///
  /// Master sheet expected columns (auto-detected by label):
  ///   FEIRA | Pavilhão | montagem | evento | desmontagem | nome | local | area | …
  static Future<Map<String, List<Client>>> fetchClientsGroupedByFair({
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final table = await _fetchTable(spreadsheetId, sheetName, 'A:BZ');
    final dataRows = table.rows;
    if (table.header.isEmpty) {
      throw Exception(
          'Planilha vazia ou aba "$sheetName" não encontrada.\n'
          'Verifique o nome da aba e as permissões de compartilhamento.');
    }

    final header =
        table.header.map((v) => v.toString().toLowerCase().trim()).toList();
    final findCol = _makeFindCol(header);

    final feiraIdx         = findCol(['feira', 'nome da feira', 'evento feira']);
    final pavilhaoIdx      = findCol(['pavilhão', 'pavilhao', 'paviliao',
        'pavilhao do evento']);
    // In the master sheet, "montagem" / "evento" / "desmontagem" are DATE columns
    final dataMontagemIdx  = findCol(['montagem', 'data montagem',
        'data de montagem']);
    final dataEventoIdx    = findCol(['evento', 'data evento',
        'data do evento', 'data abertura']);
    final dataDesmontagemIdx = findCol(['desmontagem', 'data desmontagem',
        'data de desmontagem']);
    final nomeIdx          = findCol(['nome']);
    final tipoIdx          = findCol(['tipo', 'type', 'tipo do stand',
        'tipo stand', 'tipo montagem']);
    final localIdx         = findCol(['local', 'localização', 'localizacao',
        'local stand', 'local do stand', 'localização stand']);
    final hangarIdx        = findCol(['hangar']);
    final areaIdx          = _findAreaCol(header);
    final produtorIdx      = findCol(['produtor']);
    final atendIdx         = findCol(['atendimento', 'consultor',
        'atendimento responsável', 'atendimento responsavel']);
    final organizadoraIdx  = findCol(['organizadora', 'organizador',
        'organização', 'organizacao']);
    final pinIdx           = findCol(['pin', 'senha', 'código', 'codigo',
        'pin stand', 'pin acesso']);
    final marceIdx         = findCol(['marceneiro']);
    final tapecIdx         = findCol(['tapeceiro']);
    final eletrIdx         = findCol(['eletricista']);
    final faxiIdx          = findCol(['faxineira']);
    final linkIdx          = findCol(['link projeto', 'link projeto',
        'projeto link', 'link do projeto']);
    final linkCvIdx        = findCol(['print cv', 'link cv',
        'link comunicação visual', 'link comunicacao visual',
        'link print cv']);
    final linkMemorialIdx  = findCol(['link memorial', 'memorial',
        'memorial descritivo', 'link do memorial']);
    final mobilarioIdx     = findCol(['mobiliário locado', 'mobiliario locado',
        'mobiliário', 'mobiliario']);
    final extrasIdx        = findCol(['extras', 'extra', 'itens extras',
        'itens adicionais']);
    // Balcões e cores: a planilha escreve de vários jeitos, com e sem acento.
    final balcaoPadraoIdx  = findCol(['balcão padrão', 'balcao padrao',
        'balcão padrao', 'balcao padrão', 'balcao', 'balcão']);
    final balcaoPersIdx    = findCol(['balcão personalizado',
        'balcao personalizado', 'balcão personalizado ',
        'balcao personalizado ', 'balcão customizado', 'balcao customizado']);
    final coresIdx         = findCol(['cores', 'cor', 'cores do stand',
        'cor do stand']);
    // A especificação elétrica do stand, não o nome do eletricista: são duas
    // colunas diferentes e a equipe precisa das duas.
    final eletricaIdx      = findCol(['elétrica', 'eletrica',
        'instalação elétrica', 'instalacao eletrica', 'ponto elétrico',
        'ponto eletrico', 'pontos elétricos', 'pontos eletricos']);
    final linkPlantaIdx    = findCol(['link planta', 'link da planta',
        'planta baixa', 'planta', 'mapa']);
    final linkDriveIdx     = findCol(['link drive', 'drive',
        'link pasta', 'link do drive']);

    if (feiraIdx < 0) {
      throw Exception(
          'Coluna "FEIRA" não encontrada na aba "$sheetName".\n'
          'A planilha mestra deve ter uma coluna com o nome "FEIRA".');
    }
    if (nomeIdx < 0) {
      throw Exception(
          'Coluna "nome" não encontrada na aba "$sheetName".\n'
          'Verifique se a planilha tem cabeçalho.');
    }

    final grouped = <String, List<Client>>{};

    // Cada linha da mestra é de uma feira; a ambiguidade de nome é dentro de
    // cada uma, não da aba inteira. Duas feiras podem ter um expositor
    // homônimo sem que nenhuma das duas fique sem chave.
    final nomesPorFeira = <String, List<String>>{};
    for (final r in dataRows) {
      String cel(int idx) =>
          (idx >= 0 && idx < r.length ? r[idx] : null)?.toString().trim() ?? '';
      final f = cel(feiraIdx);
      if (f.isEmpty) continue;
      (nomesPorFeira[f] ??= []).add(cel(nomeIdx));
    }
    final chavesPorFeira = {
      for (final e in nomesPorFeira.entries)
        e.key: clientKeysFor(e.key, e.value),
    };

    for (int i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];

      String s(int idx) {
        if (idx < 0 || idx >= row.length) return '';
        return row[idx]?.toString().trim() ?? '';
      }

      String n(int idx) {
        final raw = s(idx);
        if (raw.isEmpty) return raw;
        return raw.split(' ').map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        }).join(' ');
      }

      final feiraNome = s(feiraIdx);
      final nome = s(nomeIdx);
      if (feiraNome.isEmpty || nome.isEmpty) continue;

      String hangar = s(hangarIdx);
      if (hangar.isNotEmpty) {
        final m = RegExp(r'^(?:EXT|Ext)\.?\s+(\S+)$').firstMatch(hangar);
        if (m != null) hangar = m.group(1)!;
      }

      final rowNumInFair = (grouped[feiraNome]?.length ?? 0) + 1;
      final client = Client(
        fairId: 0,           // placeholder — caller calls reidentify()
        rowId: '0_${i + 1}', // placeholder row id
        firestoreId: '${_normalize(feiraNome)}_$rowNumInFair',
        // Posicional, e na mestra ainda pior: depende de quantas linhas DESTA
        // feira vieram antes. A clientKey não depende de nenhuma das duas
        // coisas.
        clientKey:
            chavesPorFeira[feiraNome]?[normalizeKeyPart(nome)] ?? '',
        nome: nome,
        // A mestra já mostrava o TIPO no lugar da montagem; mantido para não
        // mudar o que essas feiras exibem hoje.
        montagem: s(tipoIdx),
        tipo: s(tipoIdx),
        local: s(localIdx),
        hangar: hangar,
        area: s(areaIdx),
        deck: '',
        totalArea: '',
        mezanino: '',
        // A coluna aceita mais de um nome separado por vírgula. O primeiro
        // é o dono padrão; a transferência dentro do app troca esse valor.
        produtor: ownerFrom(produtoresFrom(n(produtorIdx)), null),
        produtores: produtoresFrom(n(produtorIdx)),
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
        linkMemorial: s(linkMemorialIdx),
        mobilario: s(mobilarioIdx),
        extras: s(extrasIdx),
        balcaoPadrao: s(balcaoPadraoIdx),
        balcaoPersonalizado: s(balcaoPersIdx),
        cores: s(coresIdx),
        eletrica: s(eletricaIdx),
        pavilhao: s(pavilhaoIdx),
        dataMontagem: s(dataMontagemIdx),
        dataEvento: s(dataEventoIdx),
        dataDesmontagem: s(dataDesmontagemIdx),
        linkPlanta: s(linkPlantaIdx),
        linkDrive: s(linkDriveIdx),
      );

      grouped.putIfAbsent(feiraNome, () => []).add(client);
    }

    return grouped;
  }
}
