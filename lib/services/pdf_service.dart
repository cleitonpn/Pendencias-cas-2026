import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/pending_item.dart';

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

  /// Salva o PDF em arquivo temporário e abre o compartilhamento do Android
  static Future<void> _saveAndShare(pw.Document pdf, String filename) async {
    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: filename.replaceAll('_', ' ').replaceAll('.pdf', ''),
      ),
    );
  }

  static Future<void> generatePendingReport(
      List<PendingItem> items, bool showResolved) async {
    final pdf = pw.Document();
    final now = _dateFmt.format(DateTime.now());
    final title = showResolved ? 'PENDÊNCIAS RESOLVIDAS' : 'PENDÊNCIAS ABERTAS';

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
                      color: showResolved
                          ? PdfColors.green800
                          : PdfColors.red800)),
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
                    '${item.resolvedAt != null ? "  |  Resolvido: ${_dtFmt.format(item.resolvedAt!)}" : ""}',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600),
                  ),
                  if (showResolved && item.resolvedAt != null)
                    pw.Text(
                      'Tempo: ${_dur(item.resolvedAt!.difference(item.createdAt))}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.green700),
                    ),
                ],
              ),
            ));
          }
          widgets.add(pw.SizedBox(height: 6));
        }
        return widgets;
      },
    ));

    final filename = showResolved
        ? 'CAS2026_pendencias_resolvidas.pdf'
        : 'CAS2026_pendencias_abertas.pdf';
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

  /// Mostra snackbar de feedback enquanto gera o PDF
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
