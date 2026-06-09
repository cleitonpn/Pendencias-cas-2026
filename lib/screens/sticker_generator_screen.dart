import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../services/sheets_service.dart';
import '../utils/stand_link.dart';

/// Admin tool: generates a printable PDF of stand stickers, each with the
/// project name, stand, a QR code (deep link to the public request page) and
/// the access PIN. Clients without a PIN in the spreadsheet are skipped.
class StickerGeneratorScreen extends StatefulWidget {
  final Fair fair;
  const StickerGeneratorScreen({super.key, required this.fair});

  @override
  State<StickerGeneratorScreen> createState() => _StickerGeneratorScreenState();
}

class _StickerGeneratorScreenState extends State<StickerGeneratorScreen> {
  bool _loading = true;
  bool _generating = false;
  String? _error;
  List<Client> _all = [];
  List<Client> _withPin = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final clients = await SheetsService.fetchClients(
        spreadsheetId: widget.fair.spreadsheetId,
        sheetName: widget.fair.sheetName,
        fairId: widget.fair.id!,
      );
      setState(() {
        _all = clients;
        _withPin = clients.where((c) => c.pin.trim().isNotEmpty).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _generate() async {
    if (_withPin.isEmpty) return;
    setState(() => _generating = true);
    try {
      final doc = pw.Document();
      const perPage = 8; // 2 columns x 4 rows
      for (var i = 0; i < _withPin.length; i += perPage) {
        final slice = _withPin.skip(i).take(perPage).toList();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(18),
            build: (ctx) => pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: slice.map(_stickerCard).toList(),
            ),
          ),
        );
      }
      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final safeName =
          widget.fair.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final file = File('${dir.path}/adesivos_$safeName.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Adesivos — ${widget.fair.name}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Falha ao gerar PDF: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  pw.Widget _stickerCard(Client c) {
    final url = buildStandUrl(fairId: widget.fair.id!, rowId: c.rowId);
    return pw.Container(
      width: 250,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.8),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: url,
            width: 78,
            height: 78,
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PRECISA DE MANUTENÇÃO?',
                    style: pw.TextStyle(
                        fontSize: 7, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(c.displayName,
                    maxLines: 2,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
                if (c.local.isNotEmpty)
                  pw.Text('Stand ${c.local}',
                      style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 4),
                pw.Text('Aponte a câmera para o QR',
                    style: const pw.TextStyle(fontSize: 7)),
                pw.SizedBox(height: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text('PIN: ${c.pin}',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Gerar Adesivos',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red)),
                ))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.fair.name,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              _stat('Stands com PIN', '${_withPin.length}',
                                  Colors.green),
                              _stat('Sem PIN (não gerados)',
                                  '${_all.length - _withPin.length}',
                                  Colors.orange),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_all.length - _withPin.length > 0)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Text(
                              'Stands sem PIN na planilha não recebem adesivo. '
                              'Preencha a coluna "pin" para incluí-los.',
                              style: TextStyle(
                                  color: Colors.orange, fontSize: 13)),
                        ),
                      const Spacer(),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: (_withPin.isEmpty || _generating)
                              ? null
                              : _generate,
                          icon: _generating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.picture_as_pdf),
                          label: Text(
                              _generating
                                  ? 'Gerando...'
                                  : 'Gerar PDF (${_withPin.length} adesivos)',
                              style: const TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$value  ',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 16)),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
