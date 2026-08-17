import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/client.dart';
import '../models/montage_update.dart';
import '../models/pending_item.dart';
import '../utils/furniture_items.dart';

/// Qual relatório de pendências gerar. Substitui o booleano antigo, que não
/// conseguia distinguir recusadas de resolvidas.
enum PendingReportKind { abertas, resolvidas, recusadas }

class PdfService {
  static final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');
  static final _dateFmt = DateFormat('dd/MM/yyyy');

  static String _dur(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}min';
    return '${d.inMinutes}min';
  }

  static PdfColor _teamColor(String team) {
    switch (team.toLowerCase()) {
      case 'elétrica':
      case 'eletrica':
        return PdfColors.orange800;
      case 'limpeza':
        return PdfColors.cyan800;
      case 'marcenaria':
        return PdfColors.brown700;
      case 'tapeçaria':
      case 'tapecaria':
        return PdfColors.purple700;
      case 'comunicação visual':
        return PdfColors.pink700;
      default:
        return PdfColors.grey700;
    }
  }

  /// Abre o compartilhamento com o PDF gerado.
  ///
  /// Compartilha a partir dos bytes, não de um arquivo temporário: no
  /// navegador não existe diretório temporário nem `dart:io`, e era isso que
  /// impedia o app de compilar para web.
  static Future<void> _saveAndShare(pw.Document pdf, String filename) async {
    final bytes = await pdf.save();
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: filename, mimeType: 'application/pdf')],
      subject: filename.replaceAll('_', ' ').replaceAll('.pdf', ''),
      fileNameOverrides: [filename],
    );
  }

  /// Um booleano não dava conta de três relatórios: passar `true` para as
  /// recusadas gerava um PDF intitulado — e salvo como — "resolvidas".
  static Future<void> generatePendingReport(
      List<PendingItem> items, PendingReportKind kind) async {
    final pdf = pw.Document();
    final now = _dateFmt.format(DateTime.now());
    final closed = kind != PendingReportKind.abertas;
    final rejected = kind == PendingReportKind.recusadas;
    final title = switch (kind) {
      PendingReportKind.abertas => 'PENDÊNCIAS ABERTAS',
      PendingReportKind.resolvidas => 'PENDÊNCIAS RESOLVIDAS',
      PendingReportKind.recusadas => 'CHAMADOS RECUSADOS',
    };
    final titleColor = switch (kind) {
      PendingReportKind.abertas => PdfColors.red800,
      PendingReportKind.resolvidas => PdfColors.green800,
      PendingReportKind.recusadas => PdfColors.red800,
    };

    final grouped = <String, List<PendingItem>>{};
    for (final item in items) {
      grouped.putIfAbsent('Hangar ${item.hangar}', () => []).add(item);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: titleColor)),
              pw.Text('CAS 2026 — $now',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 4),
        ],
      ),
      build: (_) {
        if (items.isEmpty) {
          return [
            pw.Center(
                child: pw.Text('Nenhuma pendência encontrada.',
                    style: const pw.TextStyle(color: PdfColors.grey600)))
          ];
        }
        final widgets = <pw.Widget>[];
        for (final key in sortedKeys) {
          widgets.add(pw.Container(
            color: PdfColors.blue50,
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(key,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 12)),
          ));
          for (final item in grouped[key]!) {
            final teamColor = _teamColor(item.team);
            widgets.add(pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8, left: 8),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    pw.Text('Stand ${item.local}  ',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text('${item.clientName}  ',
                        style: const pw.TextStyle(fontSize: 11)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: teamColor,
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4)),
                      ),
                      child: pw.Text(item.team,
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.white)),
                    ),
                    if (item.responsible.isNotEmpty) ...[
                      pw.SizedBox(width: 6),
                      pw.Text('(${item.responsible})',
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Text(item.description,
                      style: const pw.TextStyle(fontSize: 11)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Criado: ${_dtFmt.format(item.createdAt)}'
                    '${item.resolvedAt != null ? "  |  ${rejected ? "Recusado" : "Resolvido"}: ${_dtFmt.format(item.resolvedAt!)}" : ""}',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600),
                  ),
                  // Tempo de resolução não faz sentido para uma recusa.
                  if (closed && !rejected && item.resolvedAt != null)
                    pw.Text(
                      'Tempo: ${_dur(item.resolvedAt!.difference(item.createdAt))}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.green700),
                    ),
                  // Sem o motivo, um relatório de recusados não serve de nada.
                  if (rejected && item.rejectionReason.isNotEmpty)
                    pw.Text('Motivo: ${item.rejectionReason}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.red700)),
                  if (!rejected && item.resolutionNote.isNotEmpty)
                    pw.Text('Nota da montadora: ${item.resolutionNote}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.green700)),
                ],
              ),
            ));
          }
          widgets.add(pw.SizedBox(height: 6));
        }
        return widgets;
      },
    ));

    final filename = switch (kind) {
      PendingReportKind.abertas => 'CAS2026_pendencias_abertas.pdf',
      PendingReportKind.resolvidas => 'CAS2026_pendencias_resolvidas.pdf',
      PendingReportKind.recusadas => 'CAS2026_chamados_recusados.pdf',
    };
    await _saveAndShare(pdf, filename);
  }

  static Future<void> generateSummaryReport(
      Map<String, int> stats, List<PendingItem> resolved) async {
    final pdf = pw.Document();
    final now = _dateFmt.format(DateTime.now());

    Duration total = Duration.zero;
    int cnt = 0;
    for (final item in resolved) {
      if (item.resolvedAt != null) {
        total += item.resolvedAt!.difference(item.createdAt);
        cnt++;
      }
    }
    final avg =
        cnt > 0 ? Duration(minutes: total.inMinutes ~/ cnt) : Duration.zero;

    final byTeam = <String, int>{};
    for (final item in resolved) {
      byTeam[item.team] = (byTeam[item.team] ?? 0) + 1;
    }

    pw.Widget statRow(String label, String value, {PdfColor? color}) =>
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: color ?? PdfColors.black)),
            ],
          ),
        );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Text('RELATÓRIO FINAL — CAS 2026',
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Gerado em: $now',
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 20),
        pw.Text('RESUMO GERAL',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        pw.SizedBox(height: 8),
        statRow('Total de stands', '${stats['total'] ?? 0}'),
        statRow('Stands concluídos', '${stats['completed'] ?? 0}',
            color: PdfColors.green700),
        statRow('Stands com pendências', '${stats['with_pending'] ?? 0}',
            color: PdfColors.orange700),
        statRow('Pendências abertas', '${stats['total_pending'] ?? 0}',
            color: PdfColors.red700),
        statRow('Pendências resolvidas', '${stats['resolved_pending'] ?? 0}',
            color: PdfColors.green700),
        statRow('Tempo médio de resolução', _dur(avg)),
        pw.SizedBox(height: 20),
        if (byTeam.isNotEmpty) ...[
          pw.Text('RESOLVIDAS POR EQUIPE',
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.SizedBox(height: 8),
          ...byTeam.entries.map((e) => statRow(e.key, '${e.value}')),
        ],
      ],
    ));

    await _saveAndShare(pdf, 'CAS2026_relatorio_final.pdf');
  }

  /// Gera um relatório de entrega individual por stand.
  /// Inclui dados do cliente, equipe responsável, pendências resolvidas e
  /// histórico de atualizações de montagem — comprovante profissional de entrega.
  static Future<void> generateStandDeliveryReport(
    String fairName,
    Client client,
    List<PendingItem> resolvedItems,
    List<MontageUpdate> montageUpdates,
  ) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final nowFmt = _dtFmt.format(now);
    final dateFmt = _dateFmt.format(now);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text('RELATÓRIO DE ENTREGA DE STAND',
                    style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900)),
                pw.Text('$fairName  ·  $dateFmt',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600)),
              ]),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  border:
                      pw.Border.all(color: PdfColors.green600, width: 1),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text('ENTREGUE',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green700)),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Divider(color: PdfColors.grey400),
        ],
      ),
      build: (_) {
        final resp = <String>[
          if (client.produtor.isNotEmpty) 'Produtor: ${client.produtor}',
          if (client.marceneiro.isNotEmpty) 'Marcenaria: ${client.marceneiro}',
          if (client.tapeceiro.isNotEmpty) 'Tapeçaria: ${client.tapeceiro}',
          if (client.eletricista.isNotEmpty)
            'Elétrica: ${client.eletricista}',
          if (client.faxineira.isNotEmpty) 'Limpeza: ${client.faxineira}',
        ];

        return [
          // ── Dados do stand ─────────────────────────────────────────
          _pdfSection('IDENTIFICAÇÃO DO STAND'),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              1: const pw.FlexColumnWidth(2),
            },
            children: [
              _pdfRow('Expositor', client.displayName),
              if (client.local.isNotEmpty)
                _pdfRow('Número do Stand', client.local),
              if (client.hangar.isNotEmpty)
                _pdfRow('Hangar', client.hangar),
              if (client.area.isNotEmpty)
                _pdfRow('Área', '${client.area} m²'),
              if (client.montagem.isNotEmpty)
                _pdfRow('Tipo de Montagem', client.montagem),
              _pdfRow('Data de entrega', nowFmt),
            ],
          ),
          pw.SizedBox(height: 16),

          // ── Equipe responsável ─────────────────────────────────────
          if (resp.isNotEmpty) ...[
            _pdfSection('EQUIPE RESPONSÁVEL'),
            ...resp.map((r) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4, left: 8),
                  child: pw.Text('• $r',
                      style: const pw.TextStyle(fontSize: 11)),
                )),
            pw.SizedBox(height: 16),
          ],

          // ── Pendências resolvidas ──────────────────────────────────
          _pdfSection(
              'PENDÊNCIAS RESOLVIDAS (${resolvedItems.length})'),
          if (resolvedItems.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 8, bottom: 8),
              child: pw.Text('Nenhuma pendência registrada.',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600)),
            )
          else
            ...resolvedItems.map((item) {
              final dur = item.resolvedAt != null
                  ? _dur(
                      item.resolvedAt!.difference(item.createdAt))
                  : '';
              return pw.Container(
                margin:
                    const pw.EdgeInsets.only(bottom: 6, left: 8),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4)),
                ),
                child: pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(children: [
                        pw.Container(
                          padding:
                              const pw.EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(
                            color: _teamColor(item.team),
                            borderRadius:
                                const pw.BorderRadius.all(
                                    pw.Radius.circular(3)),
                          ),
                          child: pw.Text(item.team,
                              style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.white)),
                        ),
                        if (dur.isNotEmpty) ...[
                          pw.SizedBox(width: 8),
                          pw.Text('Resolvido em $dur',
                              style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.green700)),
                        ],
                      ]),
                      pw.SizedBox(height: 4),
                      pw.Text(item.description,
                          style:
                              const pw.TextStyle(fontSize: 10)),
                    ]),
              );
            }),
          pw.SizedBox(height: 16),

          // ── Atualizações de montagem ───────────────────────────────
          _pdfSection(
              'HISTÓRICO DE MONTAGEM (${montageUpdates.length} fotos)'),
          if (montageUpdates.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 8),
              child: pw.Text('Nenhuma foto registrada.',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600)),
            )
          else
            ...montageUpdates.map((u) => pw.Padding(
                  padding: const pw.EdgeInsets.only(
                      bottom: 4, left: 8),
                  child: pw.Row(children: [
                    pw.Text('• ${_dtFmt.format(u.createdAt)}',
                        style: const pw.TextStyle(
                            fontSize: 10)),
                    if (u.createdBy.isNotEmpty) ...[
                      pw.SizedBox(width: 8),
                      pw.Text('(${u.createdBy})',
                          style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey600)),
                    ],
                  ]),
                )),

          pw.SizedBox(height: 32),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          pw.Row(
              mainAxisAlignment:
                  pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Gerado em: $nowFmt',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey500)),
                pw.Text('Montagem USET — $fairName',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey500)),
              ]),
        ];
      },
    ));

    final standLabel =
        client.local.isNotEmpty ? client.local : client.rowId;
    await _saveAndShare(
        pdf, 'Entrega_Stand_${standLabel}_$dateFmt.pdf'.replaceAll('/', '-'));
  }

  static pw.Widget _pdfSection(String title) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        color: PdfColors.indigo50,
        child: pw.Text(title,
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900)),
      );

  static pw.TableRow _pdfRow(String label, String value) =>
      pw.TableRow(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child:
              pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ),
      ]);

  /// Mostra snackbar de feedback enquanto gera o PDF

  // ─── Ordem de Serviço de Mobiliário ─────────────────────────────────────
  //
  // Duas por stand: uma do que sai do estoque (interno) e outra do que é
  // sublocado (externo). Quem recebe cada uma precisa saber PARA QUAL cliente
  // vai cada item, então nem a consolidada abre mão do agrupamento por
  // cliente.

  /// Um stand com os itens já separados por destino.
  static pw.Widget _osCliente(
    Client c,
    List<FurnitureItem> itens, {
    required bool comCabecalhoDoCliente,
  }) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (comCabecalhoDoCliente) ...[
            pw.SizedBox(height: 10),
            pw.Text(c.nome,
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
          pw.Text(
            [
              if (c.local.isNotEmpty) 'Stand ${c.local}',
              if (c.hangar.isNotEmpty) 'Hangar ${c.hangar}',
              if (c.tipo.isNotEmpty) c.tipo,
            ].join('  ·  '),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(9),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _osCell('#', bold: true),
                  _osCell('ITEM', bold: true),
                ],
              ),
              // O texto vai como está na planilha: a quantidade já está nele,
              // e recompor a partir de um número separado perderia "10m
              // linear" no caminho.
              for (var i = 0; i < itens.length; i++)
                pw.TableRow(children: [
                  _osCell('${i + 1}'),
                  _osCell(itens[i].raw),
                ]),
            ],
          ),
        ],
      );

  static pw.Widget _osCell(String t, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  static pw.Widget _osDatas(Client c, DateTime entrega) {
    final linhas = <String>[
      if (c.dataMontagem.isNotEmpty)
        'Montagem: ${c.dataMontagem}'
      else if (c.montagem.isNotEmpty)
        'Montagem: ${c.montagem}',
      if (c.dataEvento.isNotEmpty) 'Evento: ${c.dataEvento}',
      if (c.dataDesmontagem.isNotEmpty)
        'Desmontagem: ${c.dataDesmontagem}',
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final l in linhas)
          pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 2),
        pw.Text('ENTREGA: ${_dateFmt.format(entrega)}',
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900)),
      ],
    );
  }

  static pw.Widget _osHeader(
      String titulo, String fairName, FurnitureKind kind, DateTime geradoEm) {
    final cor =
        kind == FurnitureKind.interno ? PdfColors.teal700 : PdfColors.orange800;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(titulo,
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900)),
              pw.Text(fairName,
                  style: const pw.TextStyle(fontSize: 10)),
            ]),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: cor, width: 1),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(kind.label.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: cor)),
            ),
          ],
        ),
        // Carimbo de emissão: se a planilha mudar depois, o papel na mão do
        // fornecedor está desatualizado e ninguém saberia sem isto.
        pw.Text('Emitida em ${_dtFmt.format(geradoEm)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        pw.Divider(color: PdfColors.grey400),
      ],
    );
  }

  /// OS de um stand.
  static Future<void> generateFurnitureOrder({
    required String fairName,
    required Client client,
    required List<FurnitureItem> itens,
    required FurnitureKind kind,
    required DateTime entrega,
  }) async {
    final pdf = pw.Document();
    final agora = DateTime.now();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (_) => _osHeader(
          'ORDEM DE SERVIÇO — MOBILIÁRIO', fairName, kind, agora),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (_) => [
        pw.SizedBox(height: 6),
        pw.Text(client.nome,
            style:
                pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _osDatas(client, entrega),
        pw.SizedBox(height: 10),
        _osCliente(client, itens, comCabecalhoDoCliente: false),
        pw.SizedBox(height: 24),
        _osAssinaturas(),
      ],
    ));

    await _saveAndShare(
        pdf,
        'OS_${kind.code}_${_slug(fairName)}_${_slug(client.nome)}.pdf');
  }

  /// OS da feira inteira, agrupada por cliente.
  ///
  /// O fornecedor recebe um documento só, mas precisa saber para qual cliente
  /// vai cada item — por isso o agrupamento não some na consolidada.
  static Future<void> generateFurnitureOrderConsolidated({
    required String fairName,
    required List<({Client client, List<FurnitureItem> itens})> stands,
    required FurnitureKind kind,
    required DateTime entrega,
  }) async {
    final pdf = pw.Document();
    final agora = DateTime.now();
    final totalItens =
        stands.fold<int>(0, (soma, s) => soma + s.itens.length);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (_) => _osHeader(
          'ORDEM DE SERVIÇO — MOBILIÁRIO (FEIRA)', fairName, kind, agora),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (_) => [
        pw.SizedBox(height: 6),
        pw.Text(
            '${stands.length} stand(s)  ·  $totalItens item(ns)  ·  '
            'ENTREGA: ${_dateFmt.format(entrega)}',
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold)),
        for (final s in stands) ...[
          pw.SizedBox(height: 6),
          _osCliente(s.client, s.itens, comCabecalhoDoCliente: true),
        ],
        pw.SizedBox(height: 24),
        _osAssinaturas(),
      ],
    ));

    await _saveAndShare(
        pdf, 'OS_${kind.code}_${_slug(fairName)}_consolidada.pdf');
  }

  static pw.Widget _osAssinaturas() => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          for (final rotulo in ['Entregue por', 'Recebido por'])
            pw.Column(children: [
              pw.Container(width: 200, height: 0.8, color: PdfColors.grey600),
              pw.SizedBox(height: 3),
              pw.Text(rotulo,
                  style:
                      const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ]),
        ],
      );

  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static Future<void> generateAndShow(
    BuildContext context,
    Future<void> Function() generator,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white)),
        SizedBox(width: 12),
        Text('Gerando PDF...'),
      ]),
      duration: Duration(seconds: 30),
    ));
    try {
      await generator();
    } finally {
      messenger.hideCurrentSnackBar();
    }
  }
}
