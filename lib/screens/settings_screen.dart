import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../utils/admin_pin.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBusy = false;
  List<String> _producers = [];
  Map<String, String?> _pins = {};

  // Team leaders
  List<String> _leaderNames = [];
  Map<String, String> _leaderTeams = {};
  Map<String, String?> _leaderPins = {};

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

  Future<void> _loadPins() async {
    final fairId = context.read<AppProvider>().currentFair?.id ?? 1;
    // Load producer names from local DB (if synced) and from Firestore (if PINs set)
    final localProducers = await DatabaseService.getProducers(fairId: fairId);
    final firestoreProducers = await FirestoreService.getProducersWithPins();
    final allProducers = {...localProducers, ...firestoreProducers}.toList()..sort();

    final pins = <String, String?>{};
    for (final p in allProducers) {
      pins[p] = await FirestoreService.getProducerPin(p);
    }

    final leaderList = await FirestoreService.getTeamLeadersWithPins();
    final lNames = leaderList.map((l) => l['name']!).toList();
    final lTeams = { for (final l in leaderList) l['name']!: l['team']! };
    final lPins = <String, String?>{};
    for (final name in lNames) {
      lPins[name] = await FirestoreService.getTeamLeaderPin(name);
    }

    if (mounted) {
      setState(() {
        _producers = allProducers;
        _pins = pins;
        _leaderNames = lNames;
        _leaderTeams = lTeams;
        _leaderPins = lPins;
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
      await FirestoreService.deleteProducerPin(producerName);
    } else {
      await FirestoreService.setProducerPin(producerName, result);
    }
    await _loadPins();
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
      await FirestoreService.setTeamLeaderPin(name, '', selectedTeam);
    } else {
      await FirestoreService.setTeamLeaderPin(name, pinCtrl.text, selectedTeam);
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
    await FirestoreService.setTeamLeaderPin(name, pinCtrl.text, selectedTeam);
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
    await FirestoreService.deleteTeamLeaderPin(name);
    await _loadPins();
  }

  Future<void> _changeAdminPin() async {
    final currentPin = await getAdminPin();
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
              await saveAdminPin(newCtrl.text);
              Navigator.pop(ctx);
              _snack('PIN de administrador alterado!');
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

            // Sync section
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

            // Admin PIN management
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
                subtitle: const Text('Altere o PIN de acesso admin',
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
