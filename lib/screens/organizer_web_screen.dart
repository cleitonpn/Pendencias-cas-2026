import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../services/firestore_service.dart';
import '../services/sheets_service.dart';
import '../services/stand_storage.dart';

/// Public web portal for the event organizer (link, no app install).
/// The organizer identifies herself (name + PIN), then can open requests for
/// ANY stand. Each request goes to the attendant (consultant) for approval
/// before reaching the producer/leader. She can also track her requests.
class OrganizerWebScreen extends StatefulWidget {
  final int? fairId; // from URL ?f=
  const OrganizerWebScreen({super.key, this.fairId});

  @override
  State<OrganizerWebScreen> createState() => _OrganizerWebScreenState();
}

enum _Step { loading, pickFair, identify, menu, pickStand, form, sent, requests, error }

class _OrganizerWebScreenState extends State<OrganizerWebScreen> {
  static const _navy = Color(0xFF0A0F64);

  static const _teams = [
    _TeamInfo('Limpeza',            Icons.cleaning_services, Color(0xFF00897B)),
    _TeamInfo('Elétrica',           Icons.bolt,              Color(0xFFFF6F00)),
    _TeamInfo('Marcenaria',         Icons.carpenter,         Color(0xFF795548)),
    _TeamInfo('Tapeçaria',          Icons.chair,             Color(0xFF7B1FA2)),
    _TeamInfo('Vidraceiro',         Icons.window,            Color(0xFF0288D1)),
    _TeamInfo('Comunicação Visual', Icons.brush,             Color(0xFFD81B60)),
  ];

  _Step _step = _Step.loading;
  String _errorMsg = '';

  List<Fair> _fairs = [];
  Fair? _fair;

  List<String> _organizers = [];
  String? _organizerName;

  List<Client> _clients = [];
  Client? _client;

  final _pinCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedTeam;
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  bool _busy = false;

  List<PendingItem> _myRequests = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String get _createdBy => 'Organizadora: ${_organizerName ?? ''}';

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    try {
      _organizers = await FirestoreService.getOrganizersWithPins();
      if (_organizers.isEmpty) {
        _fail('Nenhuma organizadora cadastrada. Peça ao administrador para '
            'configurar o PIN da organizadora no app.');
        return;
      }
      if (widget.fairId != null) {
        final data = await FirestoreService.getFair(widget.fairId!);
        if (data == null) {
          _fail('Feira não encontrada. Verifique o link ou contate a organização.');
          return;
        }
        final fair = _fairFromData(data);
        if (fair.spreadsheetId.isEmpty || fair.sheetName.isEmpty) {
          _fail('Esta feira ainda não está configurada. Peça ao administrador '
              'para abrir o app e ativar a feira novamente.');
          return;
        }
        _fair = fair;
        _setStep(_Step.identify);
        return;
      }
      final all = await FirestoreService.getFairs();
      _fairs = all
          .map(_fairFromData)
          .where((f) => f.spreadsheetId.isNotEmpty && f.sheetName.isNotEmpty)
          .toList();
      if (_fairs.isEmpty) {
        _fail('Nenhuma feira disponível no momento.');
        return;
      }
      if (_fairs.length == 1) {
        _fair = _fairs.first;
        _setStep(_Step.identify);
      } else {
        _setStep(_Step.pickFair);
      }
    } catch (e) {
      _fail('Não foi possível carregar. Verifique sua conexão e tente '
          'novamente.\n\nDetalhe: $e');
    }
  }

  Fair _fairFromData(Map<String, dynamic> m) => Fair(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        spreadsheetId: (m['spreadsheetId'] as String?) ?? '',
        sheetName: (m['sheetName'] as String?) ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
            DateTime.now(),
        mode: (m['mode'] as String?) ?? 'producao',
      );

  void _selectFair(Fair f) {
    setState(() {
      _fair = f;
      _step = _Step.identify;
    });
  }

  void _checkPin() async {
    if (_organizerName == null) {
      _toast('Selecione seu nome.', error: true);
      return;
    }
    if (_pinCtrl.text.trim().isEmpty) {
      _toast('Digite seu PIN.', error: true);
      return;
    }
    setState(() => _busy = true);
    String? saved;
    try {
      saved = await FirestoreService.getOrganizerPin(_organizerName!);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved == null) {
      _toast('PIN não configurado para você. Contate o administrador.',
          error: true);
      return;
    }
    if (_pinCtrl.text.trim() != saved) {
      _toast('PIN incorreto. Tente novamente.', error: true);
      _pinCtrl.clear();
      return;
    }
    _setStep(_Step.menu);
  }

  Future<void> _loadClients() async {
    setState(() => _step = _Step.loading);
    try {
      _clients = await SheetsService.fetchClients(
        spreadsheetId: _fair!.spreadsheetId,
        sheetName: _fair!.sheetName,
        fairId: _fair!.id!,
      );
      _setStep(_Step.pickStand);
    } catch (e) {
      _fail('Não foi possível carregar os stands. Tente novamente em instantes.');
    }
  }

  void _selectStand(Client c) {
    setState(() {
      _client = c;
      _selectedTeam = null;
      _descCtrl.clear();
      _photos.clear();
      _step = _Step.form;
    });
  }

  String _responsibleFor(String team) {
    final c = _client!;
    switch (team) {
      case 'Limpeza':            return c.faxineira;
      case 'Elétrica':           return c.eletricista;
      case 'Marcenaria':         return c.marceneiro;
      case 'Tapeçaria':          return c.tapeceiro;
      case 'Vidraceiro':         return 'Rodrigo';
      case 'Comunicação Visual': return 'Vinícius';
      default:                   return '';
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final picked =
          await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
      if (picked.isNotEmpty) setState(() => _photos.addAll(picked));
    } catch (_) {
      _toast('Não foi possível selecionar a foto.', error: true);
    }
  }

  Future<void> _submit() async {
    if (_selectedTeam == null) {
      _toast('Selecione a equipe responsável.', error: true);
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _toast('Descreva o que você precisa.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final urls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        urls.add(await StandStorage.uploadPhotoBytes(
          fairId: _fair!.id!,
          bytes: bytes,
          index: i,
        ));
      }
      final item = PendingItem(
        clientId: _client!.rowId,
        clientName: _client!.displayName,
        producerName: _client!.produtor,
        fairName: _fair!.name,
        local: _client!.local,
        hangar: _client!.hangar,
        team: _selectedTeam!,
        responsible: _responsibleFor(_selectedTeam!),
        description: _descCtrl.text.trim(),
        photoUrls: urls,
        origem: 'organizadora',
        createdBy: _createdBy,
        approvalStatus: 'pendente',
        createdAt: DateTime.now(),
      );
      await FirestoreService.savePendingItem(item, _fair!.name);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.sent;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Falha ao enviar. Verifique a conexão e tente novamente.',
          error: true);
    }
  }

  Future<void> _loadMyRequests() async {
    setState(() => _step = _Step.loading);
    try {
      _myRequests = await FirestoreService.getOrganizerRequests(_createdBy);
      _setStep(_Step.requests);
    } catch (e) {
      _fail('Não foi possível carregar seus pedidos. Tente novamente.');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setStep(_Step s) => setState(() => _step = s);
  void _fail(String msg) => setState(() {
        _errorMsg = msg;
        _step = _Step.error;
      });

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.loading:
        return const Center(child: CircularProgressIndicator());
      case _Step.error:
        return _message(Icons.error_outline, Colors.red, 'Ops!', _errorMsg);
      case _Step.pickFair:
        return _pickFairView();
      case _Step.identify:
        return _identifyView();
      case _Step.menu:
        return _menuView();
      case _Step.pickStand:
        return _pickStandView();
      case _Step.form:
        return _formView();
      case _Step.sent:
        return _sentView();
      case _Step.requests:
        return _requestsView();
    }
  }

  Widget _header({String? subtitle}) {
    return Column(
      children: [
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset('assets/logo.png',
              width: 64, height: 64, fit: BoxFit.cover),
        ),
        const SizedBox(height: 10),
        const Text('MONTAGEM USET',
            style: TextStyle(
                color: _navy,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2)),
        const SizedBox(height: 2),
        const Text('Portal da Organizadora',
            style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _message(IconData icon, Color color, String title, String body) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: color),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _pickFairView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _header(subtitle: 'Selecione o evento'),
        ..._fairs.map((f) => Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.event, color: _navy),
                title: Text(f.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _selectFair(f),
              ),
            )),
      ],
    );
  }

  Widget _identifyView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _header(subtitle: _fair?.name),
        const Text('SEU NOME',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _organizers.map((o) {
            final sel = _organizerName == o;
            return GestureDetector(
              onTap: () => setState(() => _organizerName = o),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? _navy : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? _navy : Colors.grey.shade300),
                ),
                child: Text(o,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.black87,
                        fontSize: 14)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        const Text('PIN',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        TextField(
          controller: _pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            hintText: 'Digite seu PIN',
            prefixIcon: const Icon(Icons.lock_outline),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.white,
            counterText: '',
          ),
          onSubmitted: (_) => _checkPin(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _checkPin,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.login),
            label: Text(_busy ? 'Verificando...' : 'Entrar',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _header(subtitle: '${_organizerName ?? ''} • ${_fair?.name ?? ''}'),
        _menuButton(
          icon: Icons.add_circle_outline,
          color: Colors.orange,
          title: 'Criar pendência',
          subtitle: 'Abra um pedido para qualquer stand',
          onTap: _loadClients,
        ),
        const SizedBox(height: 12),
        _menuButton(
          icon: Icons.fact_check_outlined,
          color: _navy,
          title: 'Meus pedidos',
          subtitle: 'Acompanhe o status (aguardando / aprovado / recusado)',
          onTap: _loadMyRequests,
        ),
      ],
    );
  }

  Widget _menuButton({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  Widget _pickStandView() {
    return Column(
      children: [
        _header(subtitle: 'Encontre o stand'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Autocomplete<Client>(
            displayStringForOption: (c) => c.displayName,
            optionsBuilder: (value) {
              final q = value.text.toLowerCase().trim();
              if (q.isEmpty) return const Iterable<Client>.empty();
              return _clients.where((c) =>
                  c.nome.toLowerCase().contains(q) ||
                  c.local.toLowerCase().contains(q) ||
                  c.montagem.toLowerCase().contains(q));
            },
            onSelected: _selectStand,
            fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
              controller: ctrl,
              focusNode: focus,
              decoration: InputDecoration(
                hintText: 'Busque por nome, stand ou empresa...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _clients.length,
            itemBuilder: (context, i) {
              final c = _clients[i];
              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  title: Text(c.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${c.hangar.isNotEmpty ? "Hangar ${c.hangar} • " : ""}Stand ${c.local}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _selectStand(c),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _formView() {
    final c = _client!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _header(subtitle: c.displayName),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: _navy),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  '${c.hangar.isNotEmpty ? "Hangar ${c.hangar} • " : ""}Stand ${c.local}',
                  style: const TextStyle(fontSize: 13)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: const Row(children: [
            Icon(Icons.info, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Seu pedido será enviado ao atendimento para aprovação antes de ir às equipes.',
                  style: TextStyle(fontSize: 12, color: Colors.black87)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('EQUIPE RESPONSÁVEL',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
        const SizedBox(height: 10),
        ..._teams.map((t) {
          final sel = _selectedTeam == t.name;
          final resp = _responsibleFor(t.name);
          return GestureDetector(
            onTap: () => setState(() => _selectedTeam = t.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: sel ? t.color.withOpacity(0.1) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel ? t.color : Colors.grey.shade200,
                    width: sel ? 2 : 1),
              ),
              child: Row(children: [
                Icon(t.icon, color: sel ? t.color : Colors.grey, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: sel ? t.color : Colors.black87,
                              fontSize: 15)),
                      if (resp.isNotEmpty)
                        Text('Responsável: $resp',
                            style: TextStyle(
                                fontSize: 12,
                                color: sel
                                    ? t.color.withOpacity(0.8)
                                    : Colors.grey)),
                    ],
                  ),
                ),
                if (sel) Icon(Icons.check_circle, color: t.color, size: 20),
              ]),
            ),
          );
        }),
        const SizedBox(height: 16),
        const Text('O QUE VOCÊ PRECISA?',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
        const SizedBox(height: 10),
        TextField(
          controller: _descCtrl,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Descreva o pedido...',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickPhotos,
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text('Adicionar fotos (opcional)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navy,
            side: const BorderSide(color: _navy),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(_photos[i].path,
                      width: 84, height: 84, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 84,
                          height: 84,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image))),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _photos.removeAt(i)),
                    child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_busy ? 'Enviando...' : 'Enviar pedido',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        TextButton(
          onPressed: () => _setStep(_Step.menu),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _sentView() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 80, color: Colors.green),
          const SizedBox(height: 16),
          const Text('Pedido enviado!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'O atendimento vai analisar seu pedido. Acompanhe o status em "Meus pedidos".',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _setStep(_Step.menu),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Voltar ao início'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestsView() {
    return Column(
      children: [
        _header(subtitle: 'Meus pedidos'),
        Expanded(
          child: _myRequests.isEmpty
              ? const Center(
                  child: Text('Você ainda não fez pedidos.',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _myRequests.length,
                  itemBuilder: (context, i) => _RequestCard(_myRequests[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _setStep(_Step.menu),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Voltar ao início'),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final PendingItem item;
  const _RequestCard(this.item);

  ({Color color, String label, IconData icon}) get _status {
    if (item.isRejected) {
      return (color: Colors.red, label: 'Recusado', icon: Icons.cancel);
    }
    if (item.isPendingApproval) {
      return (
        color: Colors.orange,
        label: 'Aguardando aprovação',
        icon: Icons.schedule
      );
    }
    if (item.isResolved) {
      return (color: Colors.green, label: 'Resolvido', icon: Icons.check_circle);
    }
    return (
      color: Colors.blue,
      label: 'Aprovado — em andamento',
      icon: Icons.verified
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(s.icon, color: s.color, size: 18),
              const SizedBox(width: 6),
              Text(s.label,
                  style: TextStyle(
                      color: s.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              const Spacer(),
              Text('Stand ${item.local}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Text('${item.team} — ${item.clientName}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(item.description, style: const TextStyle(fontSize: 14)),
            if (item.isRejected && item.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Motivo: ${item.rejectionReason}',
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeamInfo {
  final String name;
  final IconData icon;
  final Color color;
  const _TeamInfo(this.name, this.icon, this.color);
}
