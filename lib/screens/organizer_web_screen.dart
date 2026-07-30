import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../services/firestore_service.dart';
import '../services/sheets_service.dart';
import '../services/stand_storage.dart';
import '../utils/web_portal.dart';
import '../widgets/pending_status.dart';
import '../services/pin_service.dart';

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

/// Situações pelas quais a organizadora pode filtrar seus pedidos.
enum _ReqStatus { aguardando, andamento, concluido, recusado }

class _OrganizerWebScreenState extends State<OrganizerWebScreen> {
  static const _navy = Color(0xFF0A0F64);
  static const _kOrgName = 'org_verified_name';
  static const _kFairId  = 'org_fair_id';

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
  final Map<int, List<Client>> _clientCache = {};

  final _pinCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedTeam;
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  bool _busy = false;

  List<PendingItem> _myRequests = [];

  /// Date filters on "Meus pedidos": by opening date and by conclusion date.
  DateTimeRange? _openedRange;
  DateTimeRange? _closedRange;

  /// Situações marcadas. Vazio = todas.
  final Set<_ReqStatus> _statusFilter = {};

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
      final list = await PinService.listNames('organizer');
      _organizers = list.names;
      if (_organizers.isEmpty) {
        _fail('Nenhuma organizadora cadastrada. Peça ao administrador para '
            'configurar o PIN da organizadora no app.');
        return;
      }

      // Restore session from a previous visit so page refresh doesn't force
      // re-identification. The name is only accepted if it's still in the list.
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kOrgName);
      if (saved != null && _organizers.contains(saved)) {
        _organizerName = saved;
        // If we already know which fair and the URL doesn't override it, jump
        // directly to that fair without scanning every spreadsheet.
        final savedFairId = widget.fairId ?? prefs.getInt(_kFairId);
        if (savedFairId != null) {
          await _loadFairById(savedFairId);
        } else {
          await _loadFairs();
        }
        return;
      }

      _setStep(_Step.identify);
    } catch (e) {
      _fail('Não foi possível carregar. Verifique sua conexão e tente '
          'novamente.\n\nDetalhe: $e');
    }
  }

  /// Loads a single fair by ID without scanning every spreadsheet.
  /// Falls back to _loadFairs() if the fair is not found.
  Future<void> _loadFairById(int id) async {
    setState(() => _step = _Step.loading);
    try {
      final all = (await FirestoreService.getFairs())
          .map(_fairFromData)
          .where((f) =>
              f.id == id &&
              f.spreadsheetId.isNotEmpty &&
              f.sheetName.isNotEmpty)
          .toList();
      if (all.isEmpty) {
        await _loadFairs();
        return;
      }
      _fair = all.first;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kFairId, _fair!.id!);
      _setStep(_Step.menu);
    } catch (_) {
      await _loadFairs(); // fallback to full scan
    }
  }

  /// After identifying, loads the fairs the organizer is responsible for.
  Future<void> _loadFairs() async {
    setState(() => _step = _Step.loading);
    try {
      // Fast path: if the organizer has a specific fair assigned in Firestore,
      // skip the slow spreadsheet-by-spreadsheet scan.
      if (widget.fairId == null) {
        final assignedId =
            await FirestoreService.getOrganizerFairId(_organizerName!);
        if (assignedId != null) {
          await _loadFairById(assignedId);
          return;
        }
      }

      final all = (await FirestoreService.getFairs())
          .map(_fairFromData)
          .where((f) =>
              f.id != null &&
              f.spreadsheetId.isNotEmpty &&
              f.sheetName.isNotEmpty)
          .toList();

      if (widget.fairId != null) {
        final match = all.where((f) => f.id == widget.fairId).toList();
        if (match.isEmpty) {
          _fail('Feira não encontrada. Verifique o link ou contate a organização.');
          return;
        }
        _fair = match.first;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kFairId, _fair!.id!);
        _setStep(_Step.menu);
        return;
      }

      final name = _organizerName!.toLowerCase().trim();
      final mine = <Fair>[];
      await Future.wait(all.map((f) async {
        try {
          final clients = await SheetsService.fetchClients(
            spreadsheetId: f.spreadsheetId,
            sheetName: f.sheetName,
            fairId: f.id!,
            fairName: f.name,
          );
          if (clients
              .any((c) => c.organizadora.toLowerCase().trim() == name)) {
            _clientCache[f.id!] = clients;
            mine.add(f);
          }
        } catch (_) {}
      }));
      mine.sort((a, b) => a.name.compareTo(b.name));
      _fairs = mine;

      if (mine.isEmpty) {
        _fail('Nenhuma feira atribuída a você no momento.\n\n'
            'Verifique se o seu nome está na coluna "organizadora" da planilha, '
            'ou contate a organização.');
        return;
      }
      if (mine.length == 1) {
        _fair = mine.first;
        _clients = _clientCache[mine.first.id!] ?? [];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kFairId, _fair!.id!);
        _setStep(_Step.menu);
      } else {
        _setStep(_Step.pickFair);
      }
    } catch (e) {
      _fail('Não foi possível carregar as feiras. Tente novamente.\n\n'
          'Detalhe: $e');
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
        autoApprove: m['autoApprove'] == true,
      );

  Future<void> _selectFair(Fair f) async {
    // Persist in both Firestore and SharedPreferences so future sessions
    // go straight to this fair without the full spreadsheet scan.
    await FirestoreService.setOrganizerFairId(_organizerName!, f.id!);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFairId, f.id!);
    setState(() {
      _fair = f;
      _clients = _clientCache[f.id!] ?? [];
      _step = _Step.menu;
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
    // Verificação no servidor: este portal é público, e era por ele que os
    // PINs de todos os papéis ficavam ao alcance de qualquer visitante.
    final res = await PinService.verify(
        role: 'organizer', name: _organizerName!, pin: _pinCtrl.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      switch (res.reason) {
        case 'nao_cadastrado':
          _toast('PIN não configurado para você. Contate o administrador.',
              error: true);
          break;
        case 'pin_incorreto':
          _toast('PIN incorreto. Tente novamente.', error: true);
          _pinCtrl.clear();
          break;
        default:
          _toast('Não foi possível verificar agora. Confira a conexão.',
              error: true);
      }
      return;
    }
    // Save session so page refresh doesn't require re-identification.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOrgName, _organizerName!);
    // Marca o portal para o F5 na URL nua voltar para cá (ver _WebRouter).
    await prefs.setString(kLastWebPortal, kPortalOrganizadora);
    await _loadFairs();
  }

  /// Logs out the organizer: clears persisted session and returns to identify.
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOrgName);
    await prefs.remove(_kFairId);
    setState(() {
      _organizerName = null;
      _pinCtrl.clear();
      _fair = null;
      _fairs.clear();
      _clients.clear();
      _clientCache.clear();
    });
    _setStep(_Step.identify);
  }

  Future<void> _loadClients() async {
    final cached = _clientCache[_fair!.id!];
    if (cached != null && cached.isNotEmpty) {
      _clients = cached;
      _setStep(_Step.pickStand);
      return;
    }
    setState(() => _step = _Step.loading);
    try {
      _clients = await SheetsService.fetchClients(
        spreadsheetId: _fair!.spreadsheetId,
        sheetName: _fair!.sheetName,
        fairId: _fair!.id!,
        fairName: _fair!.name,
      );
      _clientCache[_fair!.id!] = _clients;
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
    // Antes de gastar upload de foto, avisa se já existe chamado aberto para
    // este stand e esta mesma equipe.
    final duplicates = await _openItemsForSelection();
    if (!mounted) return;
    if (duplicates.isNotEmpty) {
      final proceed = await _showDuplicateDialog(duplicates);
      if (!mounted) return;
      if (proceed != true) {
        _clearForm();
        return;
      }
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
        consultantName: _client!.atendimento,
        fairName: _fair!.name,
        local: _client!.local,
        hangar: _client!.hangar,
        team: _selectedTeam!,
        responsible: _responsibleFor(_selectedTeam!),
        description: _descCtrl.text.trim(),
        photoUrls: urls,
        origem: 'organizadora',
        createdBy: _createdBy,
        // Com aprovação automática ligada na feira, o pedido já entra liberado
        // para o produtor e a equipe, sem passar por consultor/admin.
        approvalStatus: _fair!.autoApprove ? 'aprovada' : 'pendente',
        createdAt: DateTime.now(),
      );
      final newId = await FirestoreService.savePendingItem(item, _fair!.name);
      if (!mounted) return;
      setState(() => _busy = false);
      await _showCreatedDialog(item, newId);
      if (!mounted) return;
      await _loadMyRequests();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Falha ao enviar. Verifique a conexão e tente novamente.',
          error: true);
    }
  }

  /// Chamados ainda abertos deste stand para a equipe selecionada.
  /// Recusados e concluídos não contam como duplicidade.
  Future<List<PendingItem>> _openItemsForSelection() async {
    if (_client == null || _selectedTeam == null) return [];
    try {
      final all = await FirestoreService.getItemsByClientId(_client!.rowId);
      return all
          .where((i) =>
              i.team == _selectedTeam &&
              !i.isResolved &&
              !i.isRejected)
          .toList();
    } catch (_) {
      // Sem conexão para checar: não bloqueia a abertura do chamado.
      return [];
    }
  }

  void _clearForm() {
    setState(() {
      _descCtrl.clear();
      _selectedTeam = null;
      _photos.clear();
    });
    _toast('Pedido cancelado e campos limpos.');
  }

  /// Mostra os chamados já abertos para a mesma equipe e pergunta se ela quer
  /// abrir outro assim mesmo.
  Future<bool?> _showDuplicateDialog(List<PendingItem> existing) {
    final plural = existing.length != 1;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF57C00), size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              plural
                  ? 'Já existem pedidos abertos'
                  : 'Já existe um pedido aberto',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'O stand ${_client!.local} já tem '
                  '${existing.length} pedido${plural ? "s" : ""} '
                  'em aberto na equipe $_selectedTeam:',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                ...existing.map((e) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFE082)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            PendingStatusBadge(item: e, fontSize: 11),
                            const Spacer(),
                            Text(_dateTimeFmt.format(e.createdAt),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ]),
                          const SizedBox(height: 6),
                          Text(e.description,
                              style: const TextStyle(fontSize: 13)),
                          PendingNotes(item: e, compact: true),
                        ],
                      ),
                    )),
                const SizedBox(height: 4),
                const Text(
                  'Deseja abrir um novo pedido mesmo assim?',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não, cancelar',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Sim, continuar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Resumo da pendência criada ─────────────────────────────────────────────

  static final _dateFmt = DateFormat('dd/MM/yyyy');
  static final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  /// Plain-text summary of a request — this is what "Copiar tudo" puts on the
  /// clipboard, so it has to read well when pasted into WhatsApp or e-mail.
  String _summaryText(PendingItem item, String? protocol) {
    final b = StringBuffer()
      ..writeln('*PENDÊNCIA REGISTRADA*')
      ..writeln();
    if (protocol != null && protocol.isNotEmpty) {
      b.writeln('Protocolo: $protocol');
    }
    b
      ..writeln('Feira: ${item.fairName}')
      ..writeln('Stand: ${item.local}'
          '${item.hangar.isNotEmpty ? " — Hangar ${item.hangar}" : ""}')
      ..writeln('Cliente: ${item.clientName}')
      ..writeln('Equipe: ${item.team}');
    if (item.responsible.isNotEmpty) {
      b.writeln('Responsável: ${item.responsible}');
    }
    if (item.producerName.isNotEmpty) {
      b.writeln('Produtor: ${item.producerName}');
    }
    b
      ..writeln('Aberta em: ${_dateTimeFmt.format(item.createdAt)}')
      ..writeln('Solicitante: ${item.createdBy}')
      ..writeln('Status: Aguardando aprovação')
      ..writeln()
      ..writeln('Descrição:')
      ..writeln(item.description);
    if (item.photoUrls.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Fotos (${item.photoUrls.length}):');
      for (final u in item.photoUrls) {
        b.writeln(u);
      }
    }
    return b.toString().trim();
  }

  /// Shown right after a request is created: full details, with the option to
  /// copy everything to the clipboard or just close.
  Future<void> _showCreatedDialog(PendingItem item, String? protocol) async {
    final text = _summaryText(item, protocol);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 26),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Pendência registrada!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Seu pedido foi enviado e está aguardando aprovação.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (protocol != null && protocol.isNotEmpty)
                        _sumRow('Protocolo', protocol),
                      _sumRow('Feira', item.fairName),
                      _sumRow(
                          'Stand',
                          '${item.local}'
                          '${item.hangar.isNotEmpty ? " — Hangar ${item.hangar}" : ""}'),
                      _sumRow('Cliente', item.clientName),
                      _sumRow('Equipe', item.team),
                      if (item.responsible.isNotEmpty)
                        _sumRow('Responsável', item.responsible),
                      if (item.producerName.isNotEmpty)
                        _sumRow('Produtor', item.producerName),
                      _sumRow('Aberta em', _dateTimeFmt.format(item.createdAt)),
                      _sumRow('Solicitante', item.createdBy),
                      _sumRow('Status', 'Aguardando aprovação'),
                      if (item.photoUrls.isNotEmpty)
                        _sumRow('Fotos', '${item.photoUrls.length} anexada'
                            '${item.photoUrls.length != 1 ? "s" : ""}'),
                      const Divider(height: 18),
                      const Text('Descrição',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(item.description,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) _toast('Informações copiadas!');
            },
            icon: const Icon(Icons.copy_all, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            label: const Text('Copiar tudo',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

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

  Future<void> _launchLink(String url) async {
    String target = url.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'https://$target';
    }
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _toast('Não foi possível abrir o link.', error: true);
    }
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

  /// Shared header with logo and an optional prominent back button.
  Widget _header({String? subtitle, VoidCallback? onBack}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new, size: 15),
                label: const Text('Voltar',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  foregroundColor: _navy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
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
                  style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
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
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Tentar novamente'),
            style: TextButton.styleFrom(foregroundColor: _navy),
          ),
        ],
      ),
    );
  }

  Widget _pickFairView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _header(
            subtitle: 'Selecione a feira',
            onBack: () => _setStep(_Step.menu)),
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
        _header(subtitle: 'Identifique-se para continuar'),
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
        _header(
            subtitle: '${_organizerName ?? ''} • ${_fair?.name ?? ''}',
            onBack: _fairs.length > 1 ? () => _setStep(_Step.pickFair) : null),
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
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Trocar usuário / Sair'),
            style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                textStyle: const TextStyle(fontSize: 13)),
          ),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _header(
              subtitle: 'Encontre o stand',
              onBack: () => _setStep(_Step.menu)),
        ),
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
        _header(
            subtitle: c.displayName,
            onBack: () => _setStep(_Step.pickStand)),
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
        if (c.projectLink.isNotEmpty) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _launchLink(c.projectLink),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(children: [
                Icon(Icons.folder_open, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Ver projeto no Drive',
                      style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
                Icon(Icons.open_in_new, color: Colors.blue.shade400, size: 16),
              ]),
            ),
          ),
        ],
        if (c.linkCv.isNotEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _launchLink(c.linkCv),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.pink.shade200),
              ),
              child: Row(children: [
                Icon(Icons.image_outlined, color: Colors.pink.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Ver print Comunicação Visual',
                      style: TextStyle(
                          color: Colors.pink.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
                Icon(Icons.open_in_new, color: Colors.pink.shade400, size: 16),
              ]),
            ),
          ),
        ],
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

  // ── Filtros por data ───────────────────────────────────────────────────────

  bool _inRange(DateTime? date, DateTimeRange? range) {
    if (range == null) return true;
    // Filtrando por conclusão, o que ainda não foi concluído fica de fora.
    if (date == null) return false;
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// Situação de um pedido, na ordem em que importa: recusa antes de
  /// conclusão, já que um recusado também vem marcado como resolvido.
  static _ReqStatus _statusOf(PendingItem r) {
    if (r.isRejected) return _ReqStatus.recusado;
    if (r.isPendingApproval) return _ReqStatus.aguardando;
    if (r.isResolved) return _ReqStatus.concluido;
    return _ReqStatus.andamento;
  }

  List<PendingItem> get _filteredRequests => _myRequests
      .where((r) =>
          (_statusFilter.isEmpty || _statusFilter.contains(_statusOf(r))) &&
          _inRange(r.createdAt, _openedRange) &&
          _inRange(r.resolvedAt, _closedRange))
      .toList();

  bool get _hasDateFilter =>
      _openedRange != null || _closedRange != null || _statusFilter.isNotEmpty;

  Future<void> _pickRange({required bool opened}) async {
    final now = DateTime.now();
    final current = opened ? _openedRange : _closedRange;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: current,
      helpText: opened
          ? 'Período de abertura'
          : 'Período de conclusão',
      saveText: 'Aplicar',
    );
    if (picked == null) return;
    setState(() {
      if (opened) {
        _openedRange = picked;
      } else {
        _closedRange = picked;
      }
    });
  }

  Widget _statusChip(String label, _ReqStatus status, Color color) {
    final selected = _statusFilter.contains(status);
    final count = _myRequests.where((r) => _statusOf(r) == status).length;
    return InkWell(
      onTap: () => setState(() {
        if (!_statusFilter.remove(status)) _statusFilter.add(status);
      }),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? color : color.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : color)),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withOpacity(0.25)
                  : color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : color)),
          ),
        ]),
      ),
    );
  }

  Widget _dateFilterChip({
    required String label,
    required IconData icon,
    required DateTimeRange? range,
    required bool opened,
  }) {
    final active = range != null;
    final text = active
        ? '${_dateFmt.format(range.start)} – ${_dateFmt.format(range.end)}'
        : label;
    return InkWell(
      onTap: () => _pickRange(opened: opened),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _navy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? _navy : Colors.grey.shade400),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 15, color: active ? Colors.white : Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : Colors.grey.shade800,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() {
                if (opened) {
                  _openedRange = null;
                } else {
                  _closedRange = null;
                }
              }),
              child: const Icon(Icons.close, size: 15, color: Colors.white),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _filterBar(int shown, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _statusChip('Aguardando', _ReqStatus.aguardando,
                  const Color(0xFFF57C00)),
              _statusChip('Em andamento', _ReqStatus.andamento,
                  const Color(0xFF1565C0)),
              _statusChip('Concluído', _ReqStatus.concluido,
                  const Color(0xFF2E7D32)),
              _statusChip('Recusado', _ReqStatus.recusado,
                  const Color(0xFFD32F2F)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _dateFilterChip(
                label: 'Abertura',
                icon: Icons.event_available,
                range: _openedRange,
                opened: true,
              ),
              _dateFilterChip(
                label: 'Conclusão',
                icon: Icons.task_alt,
                range: _closedRange,
                opened: false,
              ),
              if (_hasDateFilter)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _openedRange = null;
                    _closedRange = null;
                    _statusFilter.clear();
                  }),
                  icon: const Icon(Icons.filter_alt_off, size: 16),
                  label: const Text('Limpar',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
          if (_hasDateFilter)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Mostrando $shown de $total pedido${total != 1 ? "s" : ""}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _requestsView() {
    final filtered = _filteredRequests;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _header(
              subtitle: 'Meus pedidos',
              onBack: () => _setStep(_Step.menu)),
        ),
        if (_myRequests.isNotEmpty)
          _filterBar(filtered.length, _myRequests.length),
        Expanded(
          child: _myRequests.isEmpty
              ? const Center(
                  child: Text('Você ainda não fez pedidos.',
                      style: TextStyle(color: Colors.grey)))
              : filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhum pedido no período selecionado.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _RequestCard(filtered[i]),
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

  static final _fmt = DateFormat('dd/MM/yyyy HH:mm');

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
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.event_available,
                  size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text('Aberta: ${_fmt.format(item.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            if (item.resolvedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  const Icon(Icons.task_alt, size: 13, color: Colors.green),
                  const SizedBox(width: 4),
                  Text('Concluída: ${_fmt.format(item.resolvedAt!)}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            // Notas da montadora (aprovação, manutenção, recusa) e as fotos do
            // serviço — mesmo widget usado no app, para o texto ser idêntico.
            PendingNotes(item: item, compact: true),
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
