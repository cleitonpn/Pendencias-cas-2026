import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../services/admin_api.dart';
import '../utils/stand_link.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBusy = false;
  List<String> _producers = [];
  Map<String, String?> _pins = {};

  // Consultants
  List<String> _consultants = [];
  Map<String, String?> _consultantPins = {};

  // Organizers
  List<String> _organizers = [];
  Map<String, String?> _organizerPins = {};
  Map<String, List<int>> _organizerFairIds = {};
  List<Map<String, dynamic>> _allFairs = [];

  // Team leaders
  List<String> _leaderNames = [];
  Map<String, String> _leaderTeams = {};
  Map<String, String?> _leaderPins = {};

  // Managers
  List<String> _managerNames = [];
  Map<String, String?> _managerPins = {};

  // Analysts
  List<String> _analystNames = [];
  Map<String, String?> _analystPins = {};

  // Admins
  List<String> _adminUsers = [];
  Map<String, String?> _adminPins = {};

  // Logistics
  List<String> _logisticsUsers = [];
  Map<String, String?> _logisticsPins = {};

  static const _availableTeams = [
    'Elétrica',
    'Marcenaria',
    'Tapeçaria',
    'Limpeza',
    'Vidraceiro',
    'Comunicação Visual',
  ];

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  /// Executa uma gravação de cadastro avisando quando ela falha.
  ///
  /// A gestão passou a ir pelo servidor, então gravar pode falhar por rede ou
  /// por sessão vencida. Sem isto o erro sumiria e a tela recarregaria o valor
  /// antigo, dando a impressão de que a alteração simplesmente não pegou.
  Future<bool> _guard(Future<void> Function() op) async {
    try {
      await op();
      return true;
    } catch (e) {
      if (mounted) {
        _snack(
          AdminApi.isSessionError(e)
              ? 'Sua sessão de administrador expirou. Entre de novo.'
              : 'Não foi possível salvar. Confira a conexão e tente de novo.',
          isError: true,
        );
      }
      return false;
    }
  }

  /// Carrega os cadastros. A gestão passa por Cloud Function e exige sessão
  /// de administrador — se ela caiu, a tela avisa e volta em vez de ficar
  /// vazia sem explicação.
  Future<void> _loadPins() async {
    try {
      await _loadPinsInner();
    } catch (e) {
      if (!mounted) return;
      final expired = AdminApi.isSessionError(e);
      _snack(
        expired
            ? 'Sua sessão de administrador expirou. Entre de novo.'
            : 'Não foi possível carregar os cadastros. Confira a conexão.',
        isError: true,
      );
      if (expired) Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadPinsInner() async {
    // Os nomes vêm de TODAS as feiras, não só da aberta. Filtrar pela feira
    // atual escondia quem só existe na planilha mestra — os clientes dela são
    // gravados sob as feiras derivadas, nunca sob o id da mestra — e escondia
    // todo mundo quando nenhuma feira estava aberta.

    // Producers: merge local DB names with Firestore PIN holders
    final firestoreProducers = await FirestoreService.getProducersWithPins();
    final localProducers = await DatabaseService.getAllProducers();
    final allProducers = {...localProducers, ...firestoreProducers}.toList()..sort();
    final pins = <String, String?>{};
    for (final p in allProducers) {
      pins[p] = await FirestoreService.getProducerPin(p);
    }

    // Consultants
    final firestoreConsultants = await FirestoreService.getConsultantsWithPins();
    final localConsultants = await DatabaseService.getAllConsultants();
    final allConsultants =
        {...localConsultants, ...firestoreConsultants}.toList()..sort();
    final consultantPins = <String, String?>{};
    for (final c in allConsultants) {
      consultantPins[c] = await FirestoreService.getConsultantPin(c);
    }

    // Organizers
    final firestoreOrganizers = await FirestoreService.getOrganizersWithPins();
    final localOrganizers = await DatabaseService.getAllOrganizers();
    final allOrganizers =
        {...localOrganizers, ...firestoreOrganizers}.toList()..sort();
    final organizerPins = <String, String?>{};
    final organizerFairIds = <String, List<int>>{};
    for (final o in allOrganizers) {
      organizerPins[o] = await FirestoreService.getOrganizerPin(o);
      organizerFairIds[o] = await FirestoreService.getOrganizerFairIds(o);
    }
    final allFairs = await FirestoreService.getFairs();

    final leaderList = await FirestoreService.getTeamLeadersWithPins();
    final lNames = leaderList.map((l) => l['name']!).toList();
    final lTeams = { for (final l in leaderList) l['name']!: l['team']! };
    final lPins = <String, String?>{};
    for (final name in lNames) {
      lPins[name] = await FirestoreService.getTeamLeaderPin(name);
    }

    final mgrList = await FirestoreService.getManagersWithPins();
    final mgrPins = <String, String?>{};
    for (final name in mgrList) {
      mgrPins[name] = await FirestoreService.getManagerPin(name);
    }

    final analystList = await FirestoreService.getAnalystsWithPins();
    final analystPins = <String, String?>{};
    for (final name in analystList) {
      analystPins[name] = await FirestoreService.getAnalystPin(name);
    }

    final adminList = await FirestoreService.getAdminUsers();
    final adminPins = <String, String?>{};
    for (final name in adminList) {
      adminPins[name] = await FirestoreService.getAdminUserPin(name);
    }

    final logisticsList = await FirestoreService.getLogisticsUsers();
    final logisticsPins = <String, String?>{};
    for (final name in logisticsList) {
      logisticsPins[name] = await FirestoreService.getLogisticsUserPin(name);
    }

    if (mounted) {
      setState(() {
        _producers = allProducers;
        _pins = pins;
        _consultants = allConsultants;
        _consultantPins = consultantPins;
        _organizers = allOrganizers;
        _organizerPins = organizerPins;
        _organizerFairIds = organizerFairIds;
        _allFairs = allFairs;
        _leaderNames = lNames;
        _leaderTeams = lTeams;
        _leaderPins = lPins;
        _managerNames = mgrList;
        _managerPins = mgrPins;
        _analystNames = analystList;
        _analystPins = analystPins;
        _adminUsers = adminList;
        _adminPins = adminPins;
        _logisticsUsers = logisticsList;
        _logisticsPins = logisticsPins;
      });
    }
  }

  Future<void> _sync() async {
    setState(() => _isBusy = true);
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    await provider.syncFromSheets();
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (provider.error != null) {
      _snack('Erro: ${provider.error}', isError: true);
    } else {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Dados sincronizados com sucesso!'),
        backgroundColor: Colors.green,
      ));
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<void> _editPin(String producerName) async {
    final currentPin = _pins[producerName];
    final ctrl = TextEditingController(text: currentPin ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('PIN — $producerName'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o PIN (4–6 dígitos)',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          if (currentPin != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Remover', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result.isEmpty) {
      await _guard(() => FirestoreService.deleteProducerPin(producerName));
    } else {
      await _guard(() => FirestoreService.setProducerPin(producerName, result));
    }
    await _loadPins();
  }

  Future<void> _editConsultantPin(String name) async {
    final currentPin = _consultantPins[name];
    final ctrl = TextEditingController(text: currentPin ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('PIN — $name'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o PIN (4–6 dígitos)',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          if (currentPin != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Remover', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result.isEmpty) {
      await _guard(() => FirestoreService.deleteConsultantPin(name));
    } else {
      await _guard(() => FirestoreService.setConsultantPin(name, result));
    }
    await _loadPins();
  }

  /// Resumo mostrado no card: PIN e quantas feiras estão vinculadas.
  ///
  /// Com mais de uma feira por organizadora, saber só que "tem PIN" não
  /// basta — o erro que interessa é ter esquecido de marcar uma das feiras.
  String _organizerSubtitle(String name, bool hasPin) {
    if (!hasPin) return 'Sem PIN';
    final ids = _organizerFairIds[name] ?? const <int>[];
    if (ids.isEmpty) return 'PIN configurado · todas as feiras da planilha';
    if (ids.length == 1) {
      final f = _allFairs.where((e) => e['id'] == ids.first);
      final nome = f.isEmpty ? 'feira removida' : f.first['name'] as String;
      return 'PIN configurado · $nome';
    }
    return 'PIN configurado · ${ids.length} feiras';
  }

  Future<void> _editOrganizerPin(String name) async {
    final currentPin = _organizerPins[name];
    final ctrl = TextEditingController(text: currentPin ?? '');
    // Uma organizadora pode tocar várias feiras ao mesmo tempo — a NMB tem
    // três na mesma semana. Antes só cabia uma, e marcar a segunda apagava a
    // primeira.
    final selected = {...?_organizerFairIds[name]};

    final fairs = _allFairs
        .where((f) =>
            f['id'] != null &&
            (f['spreadsheetId'] as String? ?? '').isNotEmpty &&
            // A mestra não é uma feira, é o guarda-chuva das derivadas.
            // Vincular a organizadora a ela abriria os expositores de todas
            // as feiras da planilha de uma vez.
            f['sheetMode'] != 'mestra')
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    final result = await showDialog<_OrganizerPinResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Organizadora — $name'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_outlined,
                        size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      selected.isEmpty
                          ? 'Feiras vinculadas — nenhuma'
                          : 'Feiras vinculadas — ${selected.length}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sem nenhuma marcada, ela enxerga as feiras onde o nome '
                  'dela aparece na planilha.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: fairs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Nenhuma feira cadastrada.',
                              style: TextStyle(color: Colors.grey)),
                        )
                      : Scrollbar(
                          child: ListView(
                            shrinkWrap: true,
                            children: fairs.map((f) {
                              final id = f['id'] as int;
                              return CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: selected.contains(id),
                                title: Text(f['name'] as String,
                                    style: const TextStyle(fontSize: 14)),
                                onChanged: (v) => setDialogState(() {
                                  if (v == true) {
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                }),
                              );
                            }).toList(),
                          ),
                        ),
                ),
                const Divider(),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  decoration: const InputDecoration(
                    hintText: 'PIN (4–6 dígitos)',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onSubmitted: (_) => Navigator.pop(ctx,
                      _OrganizerPinResult(ctrl.text, selected.toList())),
                ),
              ],
            ),
          ),
          actions: [
            if (currentPin != null)
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, const _OrganizerPinResult('', [])),
                child:
                    const Text('Remover', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, _OrganizerPinResult(ctrl.text, selected.toList())),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    if (result.pin.isEmpty) {
      await _guard(() => FirestoreService.deleteOrganizerPin(name));
    } else {
      await _guard(() => FirestoreService.setOrganizerPin(name, result.pin));
      // Sempre grava, inclusive vazio: é assim que se desfaz um vínculo.
      await _guard(
          () => FirestoreService.setOrganizerFairIds(name, result.fairIds));
    }
    await _loadPins();
  }

  Future<void> _copyOrganizerLink() async {
    // Link único: serve para todas as organizadoras. Cada uma se identifica
    // com seu nome + PIN e vê apenas as feiras dela.
    final url = buildOrganizerUrl();
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _snack('Link da organizadora copiado!');
  }

  Future<void> _editLeader(String name) async {
    final currentPin = _leaderPins[name];
    final currentTeam = _leaderTeams[name] ?? _availableTeams.first;
    final pinCtrl = TextEditingController(text: currentPin ?? '');
    String selectedTeam = currentTeam;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Líder — $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedTeam,
                decoration: const InputDecoration(
                  labelText: 'Equipe',
                  prefixIcon: Icon(Icons.groups_outlined),
                ),
                items: _availableTeams.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setDialogState(() => selectedTeam = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                autofocus: false,
                decoration: const InputDecoration(
                  hintText: 'Digite o PIN (4–6 dígitos)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
            ],
          ),
          actions: [
            if (currentPin != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Remover PIN', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    if (result == false) {
      // Remove PIN but keep leader entry with team
      await _guard(() => FirestoreService.setTeamLeaderPin(name, '', selectedTeam));
    } else {
      await _guard(() => FirestoreService.setTeamLeaderPin(name, pinCtrl.text, selectedTeam));
    }
    await _loadPins();
  }

  Future<void> _addLeader() async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String selectedTeam = _availableTeams.first;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Adicionar Líder de Equipe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome do líder',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedTeam,
                decoration: const InputDecoration(
                  labelText: 'Equipe',
                  prefixIcon: Icon(Icons.groups_outlined),
                ),
                items: _availableTeams.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setDialogState(() => selectedTeam = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: 'PIN (4–6 dígitos)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white),
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await _guard(() => FirestoreService.setTeamLeaderPin(name, pinCtrl.text, selectedTeam));
    await _loadPins();
  }

  Future<void> _deleteLeader(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remover Líder'),
        content: Text('Remover "$name" da lista de líderes?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(() => FirestoreService.deleteTeamLeaderPin(name));
    await _loadPins();
  }

  Future<void> _editManagerPin(String name) async {
    final currentPin = _managerPins[name];
    final ctrl = TextEditingController(text: currentPin ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('PIN — $name'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o PIN (4–6 dígitos)',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          if (currentPin != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Remover', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result.isEmpty) {
      await _guard(() => FirestoreService.deleteManagerPin(name));
    } else {
      await _guard(() => FirestoreService.setManagerPin(name, result));
    }
    await _loadPins();
  }

  Future<void> _addManager() async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Adicionar Gerente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome do gerente',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'PIN (4–6 dígitos)',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await _guard(() => FirestoreService.setManagerPin(name, pinCtrl.text));
    await _loadPins();
  }

  Future<void> _deleteManager(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remover Gerente'),
        content: Text('Remover "$name" da lista de gerentes?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(() => FirestoreService.deleteManagerPin(name));
    await _loadPins();
  }

  Future<void> _editAnalystPin(String name) async {
    final currentPin = _analystPins[name];
    final ctrl = TextEditingController(text: currentPin ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('PIN — $name'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o PIN (4–6 dígitos)',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          if (currentPin != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Remover', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result.isEmpty) {
      await _guard(() => FirestoreService.deleteAnalystPin(name));
    } else {
      await _guard(() => FirestoreService.setAnalystPin(name, result));
    }
    await _loadPins();
  }

  Future<void> _addAnalyst() async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Adicionar Analista'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome do analista',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'PIN (4–6 dígitos)',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await _guard(() => FirestoreService.setAnalystPin(name, pinCtrl.text));
    await _loadPins();
  }

  Future<void> _deleteAnalyst(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remover Analista'),
        content: Text('Remover "$name" da lista de analistas?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(() => FirestoreService.deleteAnalystPin(name));
    await _loadPins();
  }

  Future<void> _addAdminUser() async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Adicionar Administrador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome do administrador',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'PIN (4–6 dígitos)',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await _guard(() => FirestoreService.saveAdminUser(name, pinCtrl.text));
    await _loadPins();
  }

  Future<void> _deleteAdminUser(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remover Administrador'),
        content: Text('Remover "$name" da lista de administradores?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(() => FirestoreService.deleteAdminUser(name));
    await _loadPins();
  }

  Future<void> _editAdminUserPin(String name) async {
    final currentPin = _adminPins[name];
    final ctrl = TextEditingController(text: currentPin ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('PIN — $name'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o PIN (4–6 dígitos)',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    await _guard(() => FirestoreService.saveAdminUser(name, result));
    await _loadPins();
  }

  Future<void> _addLogisticsUser() async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Adicionar Usuário de Logística'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'PIN (4–6 dígitos)',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await _guard(() => FirestoreService.saveLogisticsUser(name, pinCtrl.text));
    await _loadPins();
  }

  Future<void> _editLogisticsPin(String name) async {
    final currentPin = _logisticsPins[name];
    final ctrl = TextEditingController(text: currentPin ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('PIN — $name'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o PIN (4–6 dígitos)',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          if (currentPin != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Remover', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result.isEmpty) {
      await _guard(() => FirestoreService.deleteLogisticsUser(name));
    } else {
      await _guard(() => FirestoreService.saveLogisticsUser(name, result));
    }
    await _loadPins();
  }

  Future<void> _deleteLogisticsUser(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remover Usuário de Logística'),
        content: Text('Remover "$name" da lista de logística?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(() => FirestoreService.deleteLogisticsUser(name));
    await _loadPins();
  }

  /// Troca o PIN do administrador que está logado.
  ///
  /// Antes isto gravava um PIN só naquele aparelho, com um valor padrão
  /// escrito no código do app. Agora altera o cadastro no servidor, valendo
  /// para todos os aparelhos — é o mesmo PIN usado para entrar no app.
  Future<void> _changeAdminPin() async {
    final session = await SessionService.get();
    final adminName = session?['name'] ?? '';
    if (adminName.isEmpty || session?['role'] != 'admin') {
      _snack('Entre como administrador para alterar o seu PIN.',
          isError: true);
      return;
    }
    final currentPin = await FirestoreService.getAdminUserPin(adminName);
    if (currentPin == null) {
      _snack('Cadastro de administrador não encontrado.', isError: true);
      return;
    }
    if (!mounted) return;
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.admin_panel_settings, color: Color(0xFF1E3A5F)),
          SizedBox(width: 8),
          Text('Alterar PIN Admin'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'PIN atual', prefixIcon: Icon(Icons.lock)),
            ),
            TextField(
              controller: newCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Novo PIN', prefixIcon: Icon(Icons.lock_open)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (currentCtrl.text != currentPin) {
                Navigator.pop(ctx);
                _snack('PIN atual incorreto.', isError: true);
                return;
              }
              if (newCtrl.text.length < 4) {
                _snack('O novo PIN deve ter ao menos 4 dígitos.',
                    isError: true);
                return;
              }
              final ok = await _guard(
                  () => FirestoreService.saveAdminUser(adminName, newCtrl.text));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (ok) _snack('PIN de administrador alterado!');
              await _loadPins();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Alterar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fair = context.watch<AppProvider>().currentFair;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Configurações',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fair != null) ...[
              const Text('FEIRA ATUAL',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.event, color: Color(0xFF1E3A5F), size: 20),
                        const SizedBox(width: 8),
                        Text(fair.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 6),
                      Text('Aba: ${fair.sheetName}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Sync section — only shown when a fair is active
            if (fair != null) ...[
              const Text('SINCRONIZAÇÃO',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _step('1', 'Abra a planilha no Google Sheets'),
                      _step('2', 'Clique em Compartilhar'),
                      _step('3',
                          'Mude para "Qualquer pessoa com o link"\ne selecione "Visualizador"'),
                      _step('4', 'Toque em Sincronizar abaixo'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isBusy ? null : _sync,
                          icon: _isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.sync, color: Colors.white),
                          label: Text(
                              _isBusy ? 'Sincronizando...' : 'Sincronizar Planilha',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const Text('SINCRONIZAÇÃO',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(Icons.info_outline, color: Colors.grey, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'Abra uma feira na tela anterior para sincronizar a planilha.',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                  ]),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Producer PINs
            const Text('PINs DOS PRODUTORES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'Configure um PIN para que cada produtor possa acessar suas pendências.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            _producers.isEmpty
                ? Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Nenhum produtor encontrado. Sincronize a planilha primeiro.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: _producers.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        final pin = _pins[p];
                        final hasPin = pin != null;
                        return Column(
                          children: [
                            if (i > 0) const Divider(height: 1, indent: 16),
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: hasPin
                                    ? Colors.green.shade100
                                    : Colors.grey.shade100,
                                child: Icon(
                                    hasPin ? Icons.lock : Icons.lock_open,
                                    color: hasPin ? Colors.green : Colors.grey,
                                    size: 20),
                              ),
                              title: Text(p,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  hasPin ? 'PIN configurado' : 'Sem PIN',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: hasPin ? Colors.green : Colors.grey)),
                              trailing: TextButton(
                                onPressed: () => _editPin(p),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

            const SizedBox(height: 24),

            // Consultant PINs
            const Text('PINs DOS CONSULTORES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'Configure um PIN para cada consultor (coluna "atendimento") acessar seus clientes e criar pendências.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            _consultants.isEmpty
                ? Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Nenhum consultor encontrado. Sincronize a planilha primeiro.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: _consultants.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        final pin = _consultantPins[p];
                        final hasPin = pin != null;
                        return Column(
                          children: [
                            if (i > 0) const Divider(height: 1, indent: 16),
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: hasPin
                                    ? Colors.green.shade100
                                    : Colors.grey.shade100,
                                child: Icon(
                                    hasPin ? Icons.lock : Icons.lock_open,
                                    color: hasPin ? Colors.green : Colors.grey,
                                    size: 20),
                              ),
                              title: Text(p,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  hasPin ? 'PIN configurado' : 'Sem PIN',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: hasPin ? Colors.green : Colors.grey)),
                              trailing: TextButton(
                                onPressed: () => _editConsultantPin(p),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

            const SizedBox(height: 24),

            // Organizer PINs
            const Text('PINs DAS ORGANIZADORAS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'A organizadora (coluna "organizadora") acessa por um link único no '
                'navegador, identifica-se com nome + PIN e vê só as feiras dela. '
                'Cria pedidos para qualquer stand e o atendimento aprova ou recusa.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            _organizers.isEmpty
                ? Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Nenhuma organizadora encontrada. Adicione a coluna "organizadora" na planilha e sincronize.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: _organizers.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        final pin = _organizerPins[p];
                        final hasPin = pin != null;
                        return Column(
                          children: [
                            if (i > 0) const Divider(height: 1, indent: 16),
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: hasPin
                                    ? Colors.green.shade100
                                    : Colors.grey.shade100,
                                child: Icon(
                                    hasPin ? Icons.lock : Icons.lock_open,
                                    color: hasPin ? Colors.green : Colors.grey,
                                    size: 20),
                              ),
                              title: Text(p,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  _organizerSubtitle(p, hasPin),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          hasPin ? Colors.green : Colors.grey)),
                              trailing: TextButton(
                                onPressed: () => _editOrganizerPin(p),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _copyOrganizerLink,
                icon: const Icon(Icons.link),
                label: const Text('Copiar link da organizadora'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade800,
                  side: BorderSide(color: Colors.orange.shade300),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Team Leader PINs
            const Text('PINs DOS LÍDERES DE EQUIPE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'Configure um PIN para que cada líder de equipe possa acessar suas pendências.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            if (_leaderNames.isEmpty)
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Nenhum líder cadastrado. Use o botão abaixo para adicionar.',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: _leaderNames.asMap().entries.map((entry) {
                    final i = entry.key;
                    final name = entry.value;
                    final pin = _leaderPins[name];
                    final team = _leaderTeams[name] ?? '';
                    final hasPin = pin != null && pin.isNotEmpty;
                    return Column(
                      children: [
                        if (i > 0) const Divider(height: 1, indent: 16),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: hasPin
                                ? Colors.green.shade100
                                : Colors.grey.shade100,
                            child: Icon(
                                hasPin ? Icons.lock : Icons.lock_open,
                                color: hasPin ? Colors.green : Colors.grey,
                                size: 20),
                          ),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            team.isNotEmpty
                                ? '$team · ${hasPin ? 'PIN configurado' : 'Sem PIN'}'
                                : (hasPin ? 'PIN configurado' : 'Sem PIN'),
                            style: TextStyle(
                                fontSize: 12,
                                color: hasPin ? Colors.green : Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _editLeader(name),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Remover',
                                onPressed: () => _deleteLeader(name),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addLeader,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Adicionar Líder de Equipe'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A5F),
                  side: const BorderSide(color: Color(0xFF1E3A5F)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Manager PINs
            const Text('PINs DOS GERENTES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'O gerente pode criar pendências e ver todas as informações, mas não pode criar novas feiras.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            if (_managerNames.isEmpty)
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Nenhum gerente cadastrado. Use o botão abaixo para adicionar.',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: _managerNames.asMap().entries.map((entry) {
                    final i = entry.key;
                    final name = entry.value;
                    final pin = _managerPins[name];
                    final hasPin = pin != null && pin.isNotEmpty;
                    return Column(
                      children: [
                        if (i > 0) const Divider(height: 1, indent: 16),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: hasPin
                                ? Colors.green.shade100
                                : Colors.grey.shade100,
                            child: Icon(
                                hasPin ? Icons.lock : Icons.lock_open,
                                color: hasPin ? Colors.green : Colors.grey,
                                size: 20),
                          ),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            hasPin ? 'PIN configurado' : 'Sem PIN',
                            style: TextStyle(
                                fontSize: 12,
                                color: hasPin ? Colors.green : Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _editManagerPin(name),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Remover',
                                onPressed: () => _deleteManager(name),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addManager,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Adicionar Gerente'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A5F),
                  side: const BorderSide(color: Color(0xFF1E3A5F)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Analyst PINs
            const Text('PINs DOS ANALISTAS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'O analista pode visualizar todas as informações e adicionar considerações, mas não envia pendências nem conclui projetos.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            if (_analystNames.isEmpty)
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Nenhum analista cadastrado. Use o botão abaixo para adicionar.',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: _analystNames.asMap().entries.map((entry) {
                    final i = entry.key;
                    final name = entry.value;
                    final pin = _analystPins[name];
                    final hasPin = pin != null && pin.isNotEmpty;
                    return Column(
                      children: [
                        if (i > 0) const Divider(height: 1, indent: 16),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: hasPin
                                ? Colors.purple.shade100
                                : Colors.grey.shade100,
                            child: Icon(
                                hasPin ? Icons.analytics : Icons.analytics_outlined,
                                color: hasPin ? Colors.purple : Colors.grey,
                                size: 20),
                          ),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            hasPin ? 'PIN configurado' : 'Sem PIN',
                            style: TextStyle(
                                fontSize: 12,
                                color: hasPin ? Colors.purple : Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _editAnalystPin(name),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Remover',
                                onPressed: () => _deleteAnalyst(name),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addAnalyst,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Adicionar Analista'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purple.shade700,
                  side: BorderSide(color: Colors.purple.shade300),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Admin Users
            const Text('ADMINISTRADORES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'Cada administrador tem seu próprio nome e PIN para login.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            if (_adminUsers.isEmpty)
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Nenhum administrador individual cadastrado. Use o botão abaixo para adicionar.',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: _adminUsers.asMap().entries.map((entry) {
                    final i = entry.key;
                    final name = entry.value;
                    final pin = _adminPins[name];
                    final hasPin = pin != null && pin.isNotEmpty;
                    return Column(
                      children: [
                        if (i > 0) const Divider(height: 1, indent: 16),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF1E3A5F).withOpacity(0.15),
                            child: const Icon(Icons.admin_panel_settings,
                                color: Color(0xFF1E3A5F), size: 20),
                          ),
                          title: Text(name,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            hasPin ? 'PIN configurado' : 'Sem PIN',
                            style: TextStyle(
                                fontSize: 12,
                                color: hasPin ? Colors.green : Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _editAdminUserPin(name),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Remover',
                                onPressed: () => _deleteAdminUser(name),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addAdminUser,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Adicionar Administrador'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A5F),
                  side: const BorderSide(color: Color(0xFF1E3A5F)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Logistics Users
            const Text('LOGÍSTICA',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            const Text(
                'Usuários do time de logística que gerenciam solicitações de frete.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            if (_logisticsUsers.isEmpty)
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Nenhum usuário de logística cadastrado. Use o botão abaixo para adicionar.',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: _logisticsUsers.asMap().entries.map((entry) {
                    final i = entry.key;
                    final name = entry.value;
                    final pin = _logisticsPins[name];
                    final hasPin = pin != null && pin.isNotEmpty;
                    return Column(
                      children: [
                        if (i > 0) const Divider(height: 1, indent: 16),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: hasPin
                                ? Colors.teal.shade100
                                : Colors.grey.shade100,
                            child: Icon(
                                hasPin
                                    ? Icons.local_shipping
                                    : Icons.local_shipping_outlined,
                                color: hasPin ? Colors.teal : Colors.grey,
                                size: 20),
                          ),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            hasPin ? 'PIN configurado' : 'Sem PIN',
                            style: TextStyle(
                                fontSize: 12,
                                color: hasPin ? Colors.teal : Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _editLogisticsPin(name),
                                child: Text(hasPin ? 'Alterar' : 'Definir PIN',
                                    style: const TextStyle(
                                        color: Color(0xFF1E3A5F))),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Remover',
                                onPressed: () => _deleteLogisticsUser(name),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addLogisticsUser,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Adicionar Usuário de Logística'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal.shade700,
                  side: BorderSide(color: Colors.teal.shade300),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Admin PIN management (legacy shared PIN)
            const Text('ADMINISTRADOR',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1E3A5F),
                  child: Icon(Icons.admin_panel_settings,
                      color: Colors.white, size: 20),
                ),
                title: const Text('PIN de Administrador',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Altere o seu PIN de acesso (vale em todos os aparelhos)',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                trailing: TextButton(
                  onPressed: _changeAdminPin,
                  child: const Text('Alterar',
                      style: TextStyle(color: Color(0xFF1E3A5F))),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _step(String num, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withOpacity(0.1),
                  shape: BoxShape.circle),
              child: Center(
                  child: Text(num,
                      style: const TextStyle(
                          color: Color(0xFF1E3A5F),
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(color: Colors.black87, fontSize: 13))),
          ],
        ),
      );
}

class _OrganizerPinResult {
  final String pin;
  final List<int> fairIds;
  const _OrganizerPinResult(this.pin, this.fairIds);
}
