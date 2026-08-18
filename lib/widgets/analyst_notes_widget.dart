import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';

/// As considerações registradas sobre um stand.
///
/// São VÁRIAS, uma por pessoa, e ninguém escreve por cima da de ninguém.
/// Antes era um texto único: o segundo analista abria a mesma caixa, salvava,
/// e a observação do primeiro sumia sem aviso — o autor original nem ficava
/// sabendo que tinha existido.
///
/// Por isso não há "editar": quem escreveu registrou o que viu naquele
/// momento, e reescrever isso depois apaga história. O que existe é apagar,
/// que é uma decisão explícita e com confirmação.
class AnalystNotesWidget extends StatefulWidget {
  final String clientId;

  /// Quem pode acrescentar e apagar considerações.
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
  static const _roxo = Color(0xFF5B21B6);

  List<Map<String, dynamic>> _notas = [];
  bool _carregado = false;
  bool _escrevendo = false;
  bool _salvando = false;
  final _textCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final notas = await FirestoreService.getAnalystNotes(widget.clientId);
    if (!mounted) return;
    setState(() {
      _notas = notas;
      _carregado = true;
    });
  }

  Future<void> _salvar() async {
    final texto = _textCtrl.text.trim();
    final link = _linkCtrl.text.trim();
    if (texto.isEmpty && link.isEmpty) {
      _aviso('Escreva a consideração antes de salvar.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      await FirestoreService.addAnalystNote(
          widget.clientId, texto, link, widget.editorName);
      if (!mounted) return;
      _textCtrl.clear();
      _linkCtrl.clear();
      setState(() => _escrevendo = false);
      await _carregar();
      if (mounted) _aviso('Consideração registrada.');
    } catch (_) {
      if (mounted) _aviso('Erro ao salvar.', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _apagar(Map<String, dynamic> nota) async {
    final autor = (nota['by'] as String?) ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Apagar consideração?'),
        content: Text(
          autor.isEmpty
              ? 'Esta consideração será removida para todos.'
              : 'Esta consideração foi escrita por $autor e será removida '
                  'para todos.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirestoreService.deleteAnalystNote(widget.clientId, nota);
      await _carregar();
      if (mounted) _aviso('Consideração apagada.');
    } catch (_) {
      if (mounted) _aviso('Não foi possível apagar.', erro: true);
    }
  }

  void _aviso(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? Colors.red : Colors.green,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _abrirLink(String url) async {
    var alvo = url.trim();
    if (!alvo.startsWith('http://') && !alvo.startsWith('https://')) {
      alvo = 'https://$alvo';
    }
    final uri = Uri.tryParse(alvo);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_carregado) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Text(
              _notas.isEmpty
                  ? 'CONSIDERAÇÕES DOS ANALISTAS'
                  : 'CONSIDERAÇÕES DOS ANALISTAS (${_notas.length})',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _roxo,
                  letterSpacing: 1),
            ),
            const Spacer(),
            // Acrescentar, nunca reescrever: o ícone é de "adicionar" porque
            // é isso que a ação faz.
            if (widget.canEdit && !_escrevendo)
              GestureDetector(
                onTap: () => setState(() => _escrevendo = true),
                child: const Icon(Icons.add_circle_outline,
                    size: 18, color: _roxo),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_escrevendo) _formulario(),
              if (_notas.isEmpty && !_escrevendo)
                _caixa(const Text('Nenhuma consideração registrada.',
                    style: TextStyle(color: Colors.grey, fontSize: 13))),
              ..._notas.map(_cartao),
            ],
          ),
        ),
      ],
    );
  }

  Widget _caixa(Widget filho) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        color: const Color(0xFFF3F0FF),
        child: Padding(padding: const EdgeInsets.all(14), child: filho),
      );

  Widget _formulario() => _caixa(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _textCtrl,
            maxLines: 4,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nova consideração',
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add, size: 16),
                label: Text(_salvando ? 'Salvando...' : 'Adicionar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _roxo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _salvando
                  ? null
                  : () {
                      _textCtrl.clear();
                      _linkCtrl.clear();
                      setState(() => _escrevendo = false);
                    },
              child: const Text('Cancelar'),
            ),
          ]),
        ],
      ));

  Widget _cartao(Map<String, dynamic> nota) {
    final texto = (nota['text'] as String?) ?? '';
    final link = (nota['link'] as String?) ?? '';
    final autor = (nota['by'] as String?) ?? '';
    final quando = DateTime.tryParse((nota['at'] as String?) ?? '');

    return _caixa(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              [
                if (autor.isNotEmpty) autor,
                if (quando != null) DateFormat('dd/MM HH:mm').format(quando),
              ].join('  ·  '),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: _roxo),
            ),
          ),
          if (widget.canEdit)
            GestureDetector(
              onTap: () => _apagar(nota),
              child: Icon(Icons.delete_outline,
                  size: 17, color: Colors.red.shade400),
            ),
        ]),
        if (texto.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(texto,
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
        if (link.isNotEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _abrirLink(link),
            child: Row(children: [
              const Icon(Icons.link, size: 15, color: _roxo),
              const SizedBox(width: 6),
              Expanded(
                child: Text(link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        color: _roxo,
                        decoration: TextDecoration.underline)),
              ),
            ]),
          ),
        ],
      ],
    ));
  }
}
