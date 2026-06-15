import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';

/// Shows analyst notes for a client. When [canEdit] is true, the analyst
/// can type and save notes. Always shows existing notes read-only.
class AnalystNotesWidget extends StatefulWidget {
  final String clientId;
  final bool canEdit;
  final String editorName;
  const AnalystNotesWidget({
    super.key,
    required this.clientId,
    this.canEdit = false,
    this.editorName = '',
  });

  @override
  State<AnalystNotesWidget> createState() => _AnalystNotesWidgetState();
}

class _AnalystNotesWidgetState extends State<AnalystNotesWidget> {
  Map<String, dynamic>? _note;
  bool _loaded = false;
  bool _editing = false;
  bool _saving = false;
  final _textCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final note = await FirestoreService.getAnalystNote(widget.clientId);
    if (!mounted) return;
    setState(() {
      _note = note;
      _loaded = true;
      if (note != null) {
        _textCtrl.text = (note['text'] as String?) ?? '';
        _linkCtrl.text = (note['link'] as String?) ?? '';
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirestoreService.saveAnalystNote(
        widget.clientId,
        _textCtrl.text.trim(),
        _linkCtrl.text.trim(),
        widget.editorName,
      );
      if (mounted) {
        setState(() {
          _note = {
            'text': _textCtrl.text.trim(),
            'link': _linkCtrl.text.trim(),
            'updatedBy': widget.editorName,
          };
          _editing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Consideração salva.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Erro ao salvar.'),
                backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _launchLink(String url) async {
    String target = url.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'https://$target';
    }
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    final text = (_note?['text'] as String?) ?? '';
    final link = (_note?['link'] as String?) ?? '';
    final updatedBy = (_note?['updatedBy'] as String?) ?? '';
    final hasContent = text.isNotEmpty || link.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text('CONSIDERAÇÕES DOS ANALISTAS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5B21B6),
                      letterSpacing: 1)),
              const Spacer(),
              if (widget.canEdit && !_editing)
                GestureDetector(
                  onTap: () => setState(() => _editing = true),
                  child: const Icon(Icons.edit_outlined,
                      size: 16, color: Color(0xFF5B21B6)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            color: const Color(0xFFF3F0FF),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _editing
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _textCtrl,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Observações',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _linkCtrl,
                          decoration: InputDecoration(
                            labelText: 'Link (opcional)',
                            prefixIcon: const Icon(Icons.link, size: 18),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Icon(Icons.save_outlined,
                                        size: 16),
                                label: Text(
                                    _saving ? 'Salvando...' : 'Salvar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF5B21B6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _editing = false;
                                  _textCtrl.text =
                                      (_note?['text'] as String?) ?? '';
                                  _linkCtrl.text =
                                      (_note?['link'] as String?) ?? '';
                                });
                              },
                              child: const Text('Cancelar'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : !hasContent
                      ? const Text(
                          'Nenhuma consideração registrada.',
                          style: TextStyle(
                              color: Colors.grey, fontSize: 13),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (text.isNotEmpty)
                              Text(text,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87)),
                            if (link.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () => _launchLink(link),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.link,
                                          size: 14,
                                          color: Color(0xFF5B21B6)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(link,
                                            style: const TextStyle(
                                                color: Color(0xFF5B21B6),
                                                fontSize: 12,
                                                decoration: TextDecoration
                                                    .underline),
                                            overflow:
                                                TextOverflow.ellipsis),
                                      ),
                                    ]),
                              ),
                            ],
                            if (updatedBy.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('por $updatedBy',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                            ],
                          ],
                        ),
            ),
          ),
        ),
      ],
    );
  }
}
