import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../services/firestore_service.dart';
import '../services/sheets_service.dart';
import '../services/stand_storage.dart';

/// Public page opened by exhibitors via the QR code printed on their stand.
/// Self-contained: uses Firestore + Google Sheets only (no local SQLite),
/// so it runs on Flutter Web. The exhibitor identifies the stand, types the
/// PIN, and can ONLY open a maintenance request — nothing else.
class StandRequestScreen extends StatefulWidget {
  final int? fairId;   // from URL ?f=
  final String? rowId; // from URL ?c=
  const StandRequestScreen({super.key, this.fairId, this.rowId});

  @override
  State<StandRequestScreen> createState() => _StandRequestScreenState();
}

enum _Step { loading, pickFair, closed, pickStand, pin, form, sent, error }

class _StandRequestScreenState extends State<StandRequestScreen> {
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

  List<Fair> _maintenanceFairs = [];
  Fair? _fair;
  List<Client> _clients = [];
  Client? _client;

  final _pinCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedTeam;
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  bool _busy = false;

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

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    try {
      if (widget.fairId != null) {
        final data = await FirestoreService.getFair(widget.fairId!);
        if (data == null) {
          _fail('Feira não encontrada. Verifique o adesivo ou contate a organização.');
          return;
        }
        final fair = _fairFromData(data);
        if (!fair.isMaintenance) {
          _setStep(_Step.closed);
          return;
        }
        _fair = fair;
        await _loadClients();
        return;
      }
      // No fair in the URL — let the exhibitor pick one in maintenance mode.
      final all = await FirestoreService.getFairs();
      _maintenanceFairs = all
          .map(_fairFromData)
          .where((f) => f.isMaintenance)
          .toList();
      if (_maintenanceFairs.isEmpty) {
        _setStep(_Step.closed);
        return;
      }
      _setStep(_Step.pickFair);
    } catch (e) {
      _fail('Não foi possível carregar. Verifique sua conexão e tente novamente.\n\nDetalhe: $e');
    }
  }

  Fair _fairFromData(Map<String, dynamic> m) => Fair(
        id: m['id'] as int?,
        name: m['name'] as String,
        spreadsheetId: m['spreadsheetId'] as String,
        sheetName: m['sheetName'] as String,
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
            DateTime.now(),
        mode: (m['mode'] as String?) ?? 'producao',
      );

  Future<void> _selectFair(Fair fair) async {
    setState(() {
      _fair = fair;
      _step = _Step.loading;
    });
    await _loadClients();
  }

  Future<void> _loadClients() async {
    try {
      final clients = await SheetsService.fetchClients(
        spreadsheetId: _fair!.spreadsheetId,
        sheetName: _fair!.sheetName,
        fairId: _fair!.id!,
      );
      _clients = clients;
      // Pre-select the stand if it came in the URL.
      if (widget.rowId != null) {
        final match = clients.where((c) => c.rowId == widget.rowId).toList();
        if (match.isNotEmpty) {
          _client = match.first;
          _setStep(_Step.pin);
          return;
        }
      }
      _setStep(_Step.pickStand);
    } catch (e) {
      _fail('Não foi possível carregar os stands. Tente novamente em instantes.');
    }
  }

  void _selectStand(Client c) {
    setState(() {
      _client = c;
      _pinCtrl.clear();
      _step = _Step.pin;
    });
  }

  void _checkPin() {
    final expected = _client?.pin.trim() ?? '';
    if (expected.isEmpty) {
      _toast('Este stand ainda não tem PIN configurado. Procure a organização.',
          error: true);
      return;
    }
    if (_pinCtrl.text.trim() != expected) {
      _toast('PIN incorreto. Confira o adesivo do seu stand.', error: true);
      return;
    }
    setState(() => _step = _Step.form);
  }

  // ── Submit ───────────────────────────────────────────────────────────────

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
        origem: 'cliente',
        createdBy: 'Expositor',
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

  void _newRequest() {
    setState(() {
      _descCtrl.clear();
      _selectedTeam = null;
      _photos.clear();
      _step = _Step.form;
    });
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
      case _Step.closed:
        return _message(Icons.schedule, _navy, 'Atendimento não iniciado',
            'O atendimento aos expositores ainda não foi aberto para esta feira. Tente novamente mais tarde.');
      case _Step.pickFair:
        return _pickFairView();
      case _Step.pickStand:
        return _pickStandView();
      case _Step.pin:
        return _pinView();
      case _Step.form:
        return _formView();
      case _Step.sent:
        return _sentView();
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
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
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
        ..._maintenanceFairs.map((f) => Card(
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

  Widget _pickStandView() {
    return Column(
      children: [
        _header(subtitle: 'Encontre o seu stand'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Autocomplete<Client>(
            displayStringForOption: (c) => c.displayName,
            optionsBuilder: (value) {
              final q = value.text.toLowerCase().trim();
              if (q.isEmpty) return const Iterable<Client>.empty();
              return _clients.where((c) =>
                  c.nome.toLowerCase().contains(q) ||
                  c.local.toLowerCase().contains(q));
            },
            onSelected: _selectStand,
            fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
              controller: ctrl,
              focusNode: focus,
              decoration: InputDecoration(
                hintText: 'Digite o nome do projeto ou o stand',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
              'Não encontrou? Confira o nome do projeto no adesivo do seu stand.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _pinView() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _header(),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.storefront, color: _navy),
            title: Text(_client!.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${_client!.hangar.isNotEmpty ? "Hangar ${_client!.hangar}  •  " : ""}Stand ${_client!.local}'),
          ),
        ),
        const SizedBox(height: 24),
        const Text('DIGITE O PIN DO SEU STAND',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        TextField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'PIN do adesivo',
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
          onSubmitted: (_) => _checkPin(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _checkPin,
            icon: const Icon(Icons.login),
            label: const Text('Continuar', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (widget.rowId == null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _setStep(_Step.pickStand),
            child: const Text('Trocar de stand'),
          ),
        ],
      ],
    );
  }

  Widget _formView() {
    final c = _client!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _header(subtitle: 'Pedido de manutenção'),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.storefront, color: _navy),
            title: Text(c.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${c.hangar.isNotEmpty ? "Hangar ${c.hangar}  •  " : ""}Stand ${c.local}'),
          ),
        ),
        const SizedBox(height: 20),
        const Text('QUAL EQUIPE VOCÊ PRECISA?',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
        const SizedBox(height: 10),
        ..._teams.map((t) {
          final sel = _selectedTeam == t.name;
          return GestureDetector(
            onTap: () => setState(() => _selectedTeam = t.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: sel ? t.color.withOpacity(0.1) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? t.color : Colors.grey.shade200,
                  width: sel ? 2 : 1,
                ),
              ),
              child: Row(children: [
                Icon(t.icon, color: sel ? t.color : Colors.grey, size: 22),
                const SizedBox(width: 12),
                Text(t.name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: sel ? t.color : Colors.black87)),
                const Spacer(),
                if (sel) Icon(Icons.check_circle, color: t.color, size: 20),
              ]),
            ),
          );
        }),
        const SizedBox(height: 16),
        const Text('DESCREVA O PROBLEMA',
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
            hintText: 'Ex.: o balcão está com a porta solta...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickPhotos,
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: Text(_photos.isEmpty
              ? 'Adicionar foto (opcional)'
              : '${_photos.length} foto(s) — adicionar mais'),
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
            label: const Text('Enviar pedido', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
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
          const Icon(Icons.check_circle, size: 84, color: Colors.green),
          const SizedBox(height: 16),
          const Text('Pedido enviado!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Nossa equipe foi avisada e vai te atender o quanto antes. Você pode fechar esta página.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _newRequest,
            icon: const Icon(Icons.add),
            label: const Text('Fazer outro pedido'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: _navy),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
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
