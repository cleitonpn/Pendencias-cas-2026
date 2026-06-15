import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../models/pending_item.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/analyst_notes_widget.dart';
import 'add_pending_screen.dart';

/// Read-only client detail for the Consultant role.
/// The consultant can browse everything and CREATE pending items, but cannot
/// resolve, validate, or mark anything as complete.
class ConsultantClientDetailScreen extends StatefulWidget {
  final Client client;
  final String consultantName;
  const ConsultantClientDetailScreen(
      {super.key, required this.client, this.consultantName = ''});

  @override
  State<ConsultantClientDetailScreen> createState() =>
      _ConsultantClientDetailScreenState();
}

class _ConsultantClientDetailScreenState
    extends State<ConsultantClientDetailScreen> {
  List<PendingItem> _items = [];
  Set<String> _awaitingIds = {};
  bool _loading = false;
  AppProvider? _provider;

  // Specs state
  String _revestimento = '';       // 'napa' | 'formica' | ''
  final _corRevestimentoCtrl = TextEditingController();
  String _iluminacao = '';          // 'branca' | 'quente' | ''
  final _paredesCtrl = TextEditingController();
  final _tetoCtrl = TextEditingController();
  final _testeiraCtrl = TextEditingController();
  bool _pisoElevado = false;
  final _alturaElevacaoCtrl = TextEditingController();
  final _tipoPisoCtrl = TextEditingController();
  final _corPisoCtrl = TextEditingController();
  final _anotacoesCtrl = TextEditingController();
  bool _savingSpecs = false;
  bool _specsLocked = false;
  bool _editRequested = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSpecs();
    _provider = context.read<AppProvider>();
    _provider!.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    _corRevestimentoCtrl.dispose();
    _paredesCtrl.dispose();
    _tetoCtrl.dispose();
    _testeiraCtrl.dispose();
    _alturaElevacaoCtrl.dispose();
    _tipoPisoCtrl.dispose();
    _corPisoCtrl.dispose();
    _anotacoesCtrl.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _loadSpecs() async {
    final specs = await FirestoreService.getClientSpecs(widget.client.rowId);
    if (!mounted) return;
    if (specs == null) return;
    setState(() {
      _revestimento = (specs['revestimento'] as String?) ?? '';
      _corRevestimentoCtrl.text = (specs['corRevestimento'] as String?) ?? '';
      _iluminacao = (specs['iluminacao'] as String?) ?? '';
      _paredesCtrl.text = (specs['paredes'] as String?) ?? '';
      _tetoCtrl.text = (specs['teto'] as String?) ?? '';
      _testeiraCtrl.text = (specs['testeira'] as String?) ?? '';
      _pisoElevado = (specs['pisoElevado'] as bool?) ?? false;
      _alturaElevacaoCtrl.text = (specs['alturaElevacao'] as String?) ?? '';
      _tipoPisoCtrl.text = (specs['tipoPiso'] as String?) ?? '';
      _corPisoCtrl.text = (specs['corPiso'] as String?) ?? '';
      _anotacoesCtrl.text = (specs['anotacoes'] as String?) ?? '';
      _specsLocked = (specs['locked'] as bool?) ?? false;
      _editRequested = (specs['editRequested'] as bool?) ?? false;
    });
  }

  Future<void> _saveSpecs() async {
    setState(() => _savingSpecs = true);
    try {
      await FirestoreService.saveClientSpecs(widget.client.rowId, {
        'revestimento': _revestimento,
        'corRevestimento': _corRevestimentoCtrl.text.trim(),
        'iluminacao': _iluminacao,
        'paredes': _paredesCtrl.text.trim(),
        'teto': _tetoCtrl.text.trim(),
        'testeira': _testeiraCtrl.text.trim(),
        'pisoElevado': _pisoElevado,
        'alturaElevacao': _pisoElevado ? _alturaElevacaoCtrl.text.trim() : '',
        'tipoPiso': _tipoPisoCtrl.text.trim(),
        'corPiso': _corPisoCtrl.text.trim(),
        'anotacoes': _anotacoesCtrl.text.trim(),
        'locked': false,
        'editRequested': false,
      });
      await FirestoreService.lockClientSpecs(widget.client.rowId);
      FirestoreService.writeSpecChangeEvent(
        clientId: widget.client.rowId,
        clientName: widget.client.displayName,
        fairName: widget.client.rowId.split('_').first,
        consultantName: widget.consultantName,
      );
      if (mounted) {
        setState(() { _specsLocked = true; _editRequested = false; });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Especificações salvas e bloqueadas.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Erro ao salvar. Verifique sua conexão.'),
                backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _savingSpecs = false);
    }
  }

  Future<void> _requestEdit() async {
    try {
      await FirestoreService.requestSpecEdit(
        widget.client.rowId,
        widget.client.displayName,
        widget.client.rowId.split('_').first,
        widget.consultantName,
      );
      if (mounted) {
        setState(() => _editRequested = true);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Pedido de edição enviado ao administrador.'),
                duration: Duration(seconds: 3)));
      }
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final items =
        await DatabaseService.getPendingItemsByClient(widget.client.rowId);
    List<PendingItem> awaiting = [];
    try {
      awaiting =
          await FirestoreService.getAwaitingItemsByClientId(widget.client.rowId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _items = items;
        _awaitingIds = awaiting.map((i) => i.firestoreId ?? '').toSet()
          ..remove('');
        _loading = false;
      });
    }
  }

  Future<void> _addPending() async {
    final item = await Navigator.push<PendingItem>(
        context,
        MaterialPageRoute(
            builder: (_) => AddPendingScreen(
                client: widget.client,
                createdBy: widget.consultantName.isNotEmpty
                    ? 'Consultor: ${widget.consultantName}'
                    : 'Consultor')));
    if (item != null) {
      _items.insert(0, item);
      setState(() {});
    }
  }

  bool _isAwaiting(PendingItem item) =>
      item.firestoreId != null && _awaitingIds.contains(item.firestoreId);

  Future<void> _launchUrl(String url) async {
    String target = url.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'https://$target';
    }
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir o link.')));
      }
    }
  }

  void _copyWhatsApp(PendingItem item) {
    Clipboard.setData(ClipboardData(text: item.toWhatsAppText()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Texto copiado! Cole no WhatsApp.'),
        backgroundColor: Color(0xFF25D366),
        duration: Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final open = _items
        .where((p) => !p.isResolved && !_isAwaiting(p))
        .toList();
    final awaiting =
        _items.where((p) => !p.isResolved && _isAwaiting(p)).toList();
    final resolved = _items.where((p) => p.isResolved).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(c.local.isNotEmpty ? 'Stand ${c.local}' : c.displayName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              color: const Color(0xFF1E3A5F),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.displayName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    if (c.hangar.isNotEmpty)
                      _chip(Icons.warehouse, 'Hangar ${c.hangar}'),
                    if (c.local.isNotEmpty) _chip(Icons.grid_on, c.local),
                    if (c.area.isNotEmpty)
                      _chip(Icons.square_foot, '${c.area} m²'),
                    if (c.montagem.isNotEmpty) _chip(Icons.business, c.montagem),
                  ]),
                ],
              ),
            ),

            // Responsibles
            const _SectionTitle(
                text: 'RESPONSÁVEIS POR EQUIPE', color: Colors.grey),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (c.produtor.isNotEmpty)
                        _RespChip('Produtor', c.produtor, Colors.indigo),
                      if (c.marceneiro.isNotEmpty)
                        _RespChip('Marcenaria', c.marceneiro, Colors.brown),
                      if (c.tapeceiro.isNotEmpty)
                        _RespChip('Tapeçaria', c.tapeceiro, Colors.purple),
                      if (c.eletricista.isNotEmpty)
                        _RespChip('Elétrica', c.eletricista, Colors.orange),
                      if (c.faxineira.isNotEmpty)
                        _RespChip('Limpeza', c.faxineira, Colors.cyan.shade700),
                      _RespChip('Vidraceiro', 'Rodrigo', Colors.lightBlue),
                      _RespChip('Com. Visual', 'Vinícius', Colors.pink),
                    ],
                  ),
                ),
              ),
            ),

            // Project link
            if (c.projectLink.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: InkWell(
                  onTap: () => _launchUrl(c.projectLink),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.link, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Ver projeto no Drive',
                            style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                      Icon(Icons.open_in_new,
                          color: Colors.blue.shade400, size: 16),
                    ]),
                  ),
                ),
              ),

            if (c.linkMemorial.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: InkWell(
                  onTap: () => _launchUrl(c.linkMemorial),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.description_outlined,
                          color: Colors.teal.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Ver Memorial Descritivo',
                            style: TextStyle(
                                color: Colors.teal.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                      Icon(Icons.open_in_new,
                          color: Colors.teal.shade400, size: 16),
                    ]),
                  ),
                ),
              ),

            if (c.linkCv.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: InkWell(
                  onTap: () => _launchUrl(c.linkCv),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.pink.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.image_outlined,
                          color: Colors.pink.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Ver print Comunicação Visual',
                            style: TextStyle(
                                color: Colors.pink.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                      Icon(Icons.open_in_new,
                          color: Colors.pink.shade400, size: 16),
                    ]),
                  ),
                ),
              ),

            // Mobiliário locado
            if (c.mobilario.isNotEmpty) ...[
              const _SectionTitle(
                  text: 'MOBILIÁRIO LOCADO', color: Colors.teal),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.chair_outlined,
                            color: Colors.teal, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(c.mobilario,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Especificações do stand
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(children: [
                const Text('ESPECIFICAÇÕES DO STAND',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A5F),
                        letterSpacing: 1)),
                const SizedBox(width: 8),
                if (_specsLocked)
                  const Icon(Icons.lock, size: 14, color: Colors.orange),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _specsLocked
                  ? _buildSpecsReadOnly()
                  : _buildSpecsForm(),
            ),

            // Analyst notes (read-only for consultant)
            AnalystNotesWidget(clientId: widget.client.rowId, canEdit: false),

            // Create pending button (the only action available)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addPending,
                  icon: const Icon(Icons.add),
                  label: const Text('Criar Pendência'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),

            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
            else ...[
              if (open.isNotEmpty) ...[
                _SectionTitle(
                    text: 'PENDÊNCIAS ABERTAS (${open.length})',
                    color: Colors.orange),
                ...open.map((item) => _PendingCard(
                    item: item, badge: null, onCopy: () => _copyWhatsApp(item))),
              ],
              if (awaiting.isNotEmpty) ...[
                _SectionTitle(
                    text: 'AGUARDANDO VALIDAÇÃO (${awaiting.length})',
                    color: Colors.blue),
                ...awaiting.map((item) => _PendingCard(
                    item: item,
                    badge: _Badge('Aguardando validação', Colors.blue),
                    onCopy: () => _copyWhatsApp(item))),
              ],
              if (resolved.isNotEmpty) ...[
                _SectionTitle(
                    text: 'RESOLVIDAS (${resolved.length})',
                    color: Colors.green),
                ...resolved.map((item) => _PendingCard(
                    item: item,
                    badge: _Badge('Resolvido', Colors.green),
                    onCopy: () => _copyWhatsApp(item))),
              ],
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('Nenhuma pendência registrada.',
                          style: TextStyle(color: Colors.grey))),
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecsReadOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Balcões
        if (_revestimento.isNotEmpty || _corRevestimentoCtrl.text.isNotEmpty) ...[
          _SpecSection('BALCÕES'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                if (_revestimento.isNotEmpty)
                  _SpecReadRow('Revestimento', _revestimento == 'napa' ? 'Napa' : 'Formica'),
                if (_revestimento.isNotEmpty && _corRevestimentoCtrl.text.isNotEmpty)
                  const Divider(height: 16),
                if (_corRevestimentoCtrl.text.isNotEmpty)
                  _SpecReadRow('Cor do revestimento', _corRevestimentoCtrl.text),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // Iluminação
        if (_iluminacao.isNotEmpty) ...[
          _SpecSection('ILUMINAÇÃO'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _SpecReadRow('Tipo', _iluminacao == 'branca' ? 'Branca' : 'Quente'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // Cores
        if (_paredesCtrl.text.isNotEmpty || _tetoCtrl.text.isNotEmpty || _testeiraCtrl.text.isNotEmpty) ...[
          _SpecSection('CORES'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                if (_paredesCtrl.text.isNotEmpty)
                  _SpecReadRow('Paredes', _paredesCtrl.text),
                if (_paredesCtrl.text.isNotEmpty && _tetoCtrl.text.isNotEmpty)
                  const Divider(height: 16),
                if (_tetoCtrl.text.isNotEmpty)
                  _SpecReadRow('Teto', _tetoCtrl.text),
                if ((_paredesCtrl.text.isNotEmpty || _tetoCtrl.text.isNotEmpty) && _testeiraCtrl.text.isNotEmpty)
                  const Divider(height: 16),
                if (_testeiraCtrl.text.isNotEmpty)
                  _SpecReadRow('Testeira', _testeiraCtrl.text),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // Piso
        _SpecSection('PISO'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _SpecReadRow('Piso elevado', _pisoElevado ? 'Sim' : 'Não',
                  valueColor: _pisoElevado ? Colors.orange : Colors.grey),
              if (_pisoElevado && _alturaElevacaoCtrl.text.isNotEmpty) ...[
                const Divider(height: 16),
                _SpecReadRow('Altura da elevação', _alturaElevacaoCtrl.text),
              ],
              if (_tipoPisoCtrl.text.isNotEmpty) ...[
                const Divider(height: 16),
                _SpecReadRow('Tipo do piso', _tipoPisoCtrl.text),
              ],
              if (_corPisoCtrl.text.isNotEmpty) ...[
                const Divider(height: 16),
                _SpecReadRow('Cor do piso', _corPisoCtrl.text),
              ],
            ]),
          ),
        ),
        // Anotações
        if (_anotacoesCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SpecSection('ANOTAÇÕES DIVERSAS'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_anotacoesCtrl.text,
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _editRequested ? null : _requestEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(_editRequested ? 'Pedido enviado ao admin' : 'Pedir Edição'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpecsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // BALCÕES
        _SpecSection('BALCÕES'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Revestimento',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              _TogglePicker(
                options: const ['Napa', 'Formica'],
                values: const ['napa', 'formica'],
                selected: _revestimento,
                onChanged: (v) => setState(() => _revestimento = v),
              ),
              const SizedBox(height: 12),
              _SpecField(label: 'Cor do revestimento', controller: _corRevestimentoCtrl),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        // ILUMINAÇÃO
        _SpecSection('ILUMINAÇÃO'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tipo de iluminação',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              _TogglePicker(
                options: const ['Branca', 'Quente'],
                values: const ['branca', 'quente'],
                selected: _iluminacao,
                onChanged: (v) => setState(() => _iluminacao = v),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        // CORES
        _SpecSection('CORES'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _SpecField(label: 'Paredes', controller: _paredesCtrl),
              const SizedBox(height: 12),
              _SpecField(label: 'Teto', controller: _tetoCtrl),
              const SizedBox(height: 12),
              _SpecField(label: 'Testeira', controller: _testeiraCtrl),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        // PISO
        _SpecSection('PISO'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                const Expanded(child: Text('Piso elevado',
                    style: TextStyle(fontSize: 14))),
                Switch(
                  value: _pisoElevado,
                  activeColor: const Color(0xFF1E3A5F),
                  onChanged: (v) => setState(() => _pisoElevado = v),
                ),
              ]),
              if (_pisoElevado) ...[
                const SizedBox(height: 10),
                _SpecField(label: 'Altura da elevação (ex: 10 cm)', controller: _alturaElevacaoCtrl),
              ],
              const SizedBox(height: 12),
              _SpecField(label: 'Tipo do piso', controller: _tipoPisoCtrl),
              const SizedBox(height: 12),
              _SpecField(label: 'Cor do piso', controller: _corPisoCtrl),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        // ANOTAÇÕES
        _SpecSection('ANOTAÇÕES DIVERSAS'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _anotacoesCtrl,
              maxLines: 4,
              maxLength: 300,
              decoration: InputDecoration(
                hintText: 'Observações gerais...',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _savingSpecs ? null : _saveSpecs,
            icon: _savingSpecs
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_savingSpecs ? 'Salvando...' : 'Salvar Especificações'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );
}

class _Badge {
  final String text;
  final MaterialColor color;
  _Badge(this.text, this.color);
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionTitle({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 1)),
      );
}

class _RespChip extends StatelessWidget {
  final String team, person;
  final Color color;
  const _RespChip(this.team, this.person, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(team,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.bold)),
            Text(person, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _PendingCard extends StatelessWidget {
  final PendingItem item;
  final _Badge? badge;
  final VoidCallback onCopy;

  const _PendingCard(
      {required this.item, required this.badge, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final bg = badge?.color.shade50 ?? Colors.white;
    final border = badge?.color.shade200 ?? Colors.orange.shade200;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _TeamBadge(team: item.team),
              if (item.responsible.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(item.responsible,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
              const Spacer(),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badge!.color.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge!.text,
                      style: TextStyle(
                          color: badge!.color.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 8),
            if (item.fromClient) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.storefront, size: 13, color: Colors.orange),
                  SizedBox(width: 4),
                  Text('Solicitado pelo expositor',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            Text(item.description, style: const TextStyle(fontSize: 14)),
            if (item.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              PhotoStrip(urls: item.photoUrls),
            ],
            const SizedBox(height: 6),
            Text(_fmt(item.createdAt),
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('WhatsApp', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF25D366),
                side: const BorderSide(color: Color(0xFF25D366)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

Widget _SpecSection(String title) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(title,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1)),
    );

class _SpecReadRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SpecReadRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.black87)),
          ),
        ],
      );
}

class _SpecField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _SpecField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      );
}

class _TogglePicker extends StatelessWidget {
  final List<String> options;
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;
  const _TogglePicker(
      {required this.options,
      required this.values,
      required this.selected,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(options.length, (i) {
          final isSelected = selected == values[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(values[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: EdgeInsets.only(right: i < options.length - 1 ? 6 : 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1E3A5F)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF1E3A5F)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Center(
                  child: Text(
                    options[i],
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.grey.shade600),
                  ),
                ),
              ),
            ),
          );
        }),
      );
}

class _TeamBadge extends StatelessWidget {
  final String team;
  const _TeamBadge({required this.team});

  Color get _color {
    switch (team.toLowerCase()) {
      case 'elétrica':
      case 'eletrica':
        return Colors.orange;
      case 'limpeza':
        return Colors.cyan.shade700;
      case 'marcenaria':
        return Colors.brown;
      case 'tapeçaria':
      case 'tapecaria':
        return Colors.purple;
      case 'vidraceiro':
        return Colors.lightBlue;
      case 'comunicação visual':
      case 'comunicacao visual':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _color.withOpacity(0.4)),
        ),
        child: Text(team,
            style: TextStyle(
                color: _color, fontSize: 12, fontWeight: FontWeight.bold)),
      );
}
