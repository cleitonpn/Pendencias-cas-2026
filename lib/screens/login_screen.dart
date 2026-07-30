import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../services/admin_api.dart';
import 'fair_selection_screen.dart';
import 'producer_home_screen.dart';
import 'team_leader_home_screen.dart';
import 'consultant_home_screen.dart';
import 'analyst_home_screen.dart';
import 'logistics_home_screen.dart';
import '../services/auth_bootstrap.dart';
import '../services/pin_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _role = 'producer'; // 'producer'|'consultant'|'manager'|'leader'|'analyst'|'admin'|'logistica'

  // Producer
  List<String> _producers = [];
  String? _selectedProducer;
  bool _loadingProducers = true;

  // Consultant
  List<String> _consultants = [];
  String? _selectedConsultant;
  bool _loadingConsultants = true;

  // Manager
  List<String> _managers = [];
  String? _selectedManager;
  bool _loadingManagers = true;

  // Leader
  List<Map<String, String>> _leaders = [];
  String? _selectedLeader;
  bool _loadingLeaders = true;

  // Analyst
  List<String> _analysts = [];
  String? _selectedAnalyst;
  bool _loadingAnalysts = true;

  // Admin
  List<String> _admins = [];
  String? _selectedAdmin;
  bool _loadingAdmins = true;

  // Logistics
  List<String> _logistics = [];
  String? _selectedLogistics;
  bool _loadingLogistics = true;

  final _pinCtrl = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducers();
    _loadConsultants();
    _loadManagers();
    _loadLeaders();
    _loadAnalysts();
    _loadAdmins();
    _loadLogistics();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  /// Verdadeiro quando alguma lista falhou ao carregar (ou a sessão anônima
  /// não subiu). Sem isso a tela dizia "nenhum cadastrado" para um problema
  /// de conexão, mandando o usuário procurar o administrador à toa.
  bool _loadFailed = false;

  bool get _cannotRead => _loadFailed || !AuthBootstrap.signedIn;

  /// Confere o PIN pelo servidor. Devolve null quando não deve prosseguir —
  /// já tendo posto a mensagem certa na tela. Sem reserva para a leitura
  /// direta de propósito: se a função falhar, precisamos saber agora, e não
  /// depois de fechar as regras do Firestore.
  Future<PinResult?> _checkPin(String role, String name) async {
    final r = await PinService.verify(
        role: role, name: name, pin: _pinCtrl.text);
    if (!mounted) return null;
    if (r.ok) return r;
    setState(() {
      switch (r.reason) {
        case 'nao_cadastrado':
          _error = 'PIN não configurado. Contate o administrador.';
          break;
        case 'pin_incorreto':
          _error = 'PIN incorreto.';
          _pinCtrl.clear();
          break;
        case 'bloqueado':
          _error = 'Muitas tentativas erradas. '
              'Aguarde 15 minutos e tente de novo.';
          _pinCtrl.clear();
          break;
        default:
          _error = 'Não foi possível verificar agora. '
              'Confira a conexão e tente de novo.';
      }
    });
    return null;
  }

  Future<void> _retryAll() async {
    setState(() => _loadFailed = false);
    await AuthBootstrap.ensureSignedIn();
    _loadProducers();
    _loadConsultants();
    _loadManagers();
    _loadLeaders();
    _loadAnalysts();
  }

  Future<void> _loadProducers() async {
    try {
      final r = await PinService.listNames('producer');
      if (mounted) {
        setState(() {
          _producers = r.names;
          _loadingProducers = false;
          if (r.failed) _loadFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingProducers = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadConsultants() async {
    try {
      final r = await PinService.listNames('consultant');
      if (mounted) {
        setState(() {
          _consultants = r.names;
          _loadingConsultants = false;
          if (r.failed) _loadFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingConsultants = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadManagers() async {
    try {
      final r = await PinService.listNames('manager');
      if (mounted) {
        setState(() {
          _managers = r.names;
          _loadingManagers = false;
          if (r.failed) _loadFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingManagers = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadLeaders() async {
    try {
      final r = await PinService.listUsers('leader');
      if (mounted) {
        setState(() {
          _leaders = r.users
              .map((u) => {
                    'name': (u['name'] as String?) ?? '',
                    'team': (u['team'] as String?) ?? '',
                  })
              .where((u) => (u['name'] ?? '').isNotEmpty)
              .toList();
          _loadingLeaders = false;
          if (r.failed) _loadFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingLeaders = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadAnalysts() async {
    try {
      final r = await PinService.listNames('analyst');
      if (mounted) {
        setState(() {
          _analysts = r.names;
          _loadingAnalysts = false;
          if (r.failed) _loadFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingAnalysts = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadAdmins() async {
    try {
      final r = await PinService.listNames('admin');
      if (mounted) {
        setState(() {
          _admins = r.names;
          _loadingAdmins = false;
          if (r.failed) _loadFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingAdmins = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadLogistics() async {
    try {
      final r = await PinService.listNames('logistica');
      if (mounted) {
        setState(() {
          _logistics = r.names;
          _loadingLogistics = false;
          if (r.failed) _loadFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingLogistics = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _setRole(String role) {
    setState(() {
      _role = role;
      _error = null;
      _pinCtrl.clear();
      if (role != 'producer') _selectedProducer = null;
      if (role != 'consultant') _selectedConsultant = null;
      if (role != 'manager') _selectedManager = null;
      if (role != 'leader') _selectedLeader = null;
      if (role != 'analyst') _selectedAnalyst = null;
      if (role != 'admin') _selectedAdmin = null;
      if (role != 'logistica') _selectedLogistics = null;
    });
  }

  Future<void> _enter() async {
    setState(() { _error = null; _verifying = true; });
    try {
      if (_role == 'admin') {
        await _enterAdmin();
      } else if (_role == 'producer') {
        await _enterProducer();
      } else if (_role == 'consultant') {
        await _enterConsultant();
      } else if (_role == 'manager') {
        await _enterManager();
      } else if (_role == 'analyst') {
        await _enterAnalyst();
      } else if (_role == 'logistica') {
        await _enterLogistics();
      } else {
        await _enterLeader();
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _enterAdmin() async {
    if (_admins.isNotEmpty && _selectedAdmin == null) {
      setState(() => _error = 'Selecione seu nome.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite o PIN de administrador.');
      return;
    }

    // O antigo caminho alternativo comparava com um PIN gravado no aparelho,
    // cujo padrão estava escrito no código do app — quem abrisse o APK entrava
    // como admin. Agora só o servidor decide.
    if (_admins.isEmpty || _selectedAdmin == null) {
      setState(() => _error = 'Não foi possível carregar a lista de '
          'administradores. Confira a conexão e tente de novo.');
      return;
    }

    final adminName = _selectedAdmin!;
    final r = await PinService.verify(
        role: 'admin', name: adminName, pin: _pinCtrl.text);

    if (r.reason == 'erro' || r.reason == 'bloqueado') {
      if (mounted) {
        setState(() => _error = r.reason == 'bloqueado'
            ? 'Muitas tentativas erradas. Aguarde 15 minutos e tente de novo.'
            : 'Não foi possível verificar agora. '
                'Confira a conexão e tente de novo.');
      }
      return;
    }
    if (!r.ok) {
      setState(() => _error = 'PIN incorreto.');
      _pinCtrl.clear();
      return;
    }
    // Sessão de gestão já vem do login: quem entrou como admin não precisa
    // digitar o PIN de novo para abrir Configurações.
    if (r.token != null) await AdminApi.saveToken(r.token!);
    if (!mounted) return;
    await NotificationService.subscribeAdmin();
    await SessionService.save(role: 'admin', name: adminName);
    await FirestoreService.updatePresence(
      name: adminName,
      role: 'admin',
      team: '',
      online: true,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const FairSelectionScreen()));
  }

  Future<void> _enterProducer() async {
    if (_selectedProducer == null) {
      setState(() => _error = 'Selecione seu nome.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite seu PIN.');
      return;
    }
    final pinRes = await _checkPin('producer', _selectedProducer!);
    if (pinRes == null) return;
    if (!mounted) return;
    await NotificationService.subscribeProducer(_selectedProducer!);
    await SessionService.save(role: 'producer', name: _selectedProducer!);
    await FirestoreService.updatePresence(
      name: _selectedProducer!,
      role: 'producer',
      team: '',
      online: true,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(
            builder: (_) => ProducerHomeScreen(producerName: _selectedProducer!)));
  }

  Future<void> _enterConsultant() async {
    if (_selectedConsultant == null) {
      setState(() => _error = 'Selecione seu nome.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite seu PIN.');
      return;
    }
    final pinRes = await _checkPin('consultant', _selectedConsultant!);
    if (pinRes == null) return;
    if (!mounted) return;
    await NotificationService.subscribeConsultant(_selectedConsultant!);
    await SessionService.save(role: 'consultant', name: _selectedConsultant!);
    await FirestoreService.updatePresence(
      name: _selectedConsultant!,
      role: 'consultant',
      team: '',
      online: true,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(
            builder: (_) =>
                ConsultantHomeScreen(consultantName: _selectedConsultant!)));
  }

  Future<void> _enterManager() async {
    if (_selectedManager == null) {
      setState(() => _error = 'Selecione seu nome.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite seu PIN.');
      return;
    }
    final pinRes = await _checkPin('manager', _selectedManager!);
    if (pinRes == null) return;
    if (!mounted) return;
    await NotificationService.subscribeAdmin();
    await SessionService.save(role: 'manager', name: _selectedManager!);
    await FirestoreService.updatePresence(
      name: _selectedManager!,
      role: 'manager',
      team: '',
      online: true,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(
            builder: (_) => const FairSelectionScreen(canManage: false)));
  }

  Future<void> _enterAnalyst() async {
    if (_selectedAnalyst == null) {
      setState(() => _error = 'Selecione seu nome.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite seu PIN.');
      return;
    }
    final pinRes = await _checkPin('analyst', _selectedAnalyst!);
    if (pinRes == null) return;
    if (!mounted) return;
    await NotificationService.subscribeAnalyst(_selectedAnalyst!);
    await SessionService.save(role: 'analyst', name: _selectedAnalyst!);
    await FirestoreService.updatePresence(
      name: _selectedAnalyst!,
      role: 'analyst',
      team: '',
      online: true,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(
            builder: (_) => AnalystHomeScreen(analystName: _selectedAnalyst!)));
  }

  Future<void> _enterLogistics() async {
    if (_selectedLogistics == null) {
      setState(() => _error = 'Selecione seu nome.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite seu PIN.');
      return;
    }
    final pinRes = await _checkPin('logistica', _selectedLogistics!);
    if (pinRes == null) return;
    if (!mounted) return;
    await NotificationService.subscribeLogistics(_selectedLogistics!);
    await SessionService.save(role: 'logistica', name: _selectedLogistics!);
    await FirestoreService.updatePresence(
      name: _selectedLogistics!,
      role: 'logistica',
      team: '',
      online: true,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                LogisticsHomeScreen(logisticsName: _selectedLogistics!)));
  }

  Future<void> _enterLeader() async {
    if (_selectedLeader == null) {
      setState(() => _error = 'Selecione seu nome.');
      return;
    }
    if (_pinCtrl.text.isEmpty) {
      setState(() => _error = 'Digite seu PIN.');
      return;
    }
    final pinRes = await _checkPin('leader', _selectedLeader!);
    if (pinRes == null) return;
    // A equipe vem junto da verificação — evita reler a coleção de PIN, que
    // é justamente o que queremos fechar.
    final team = pinRes.team;
    if (!mounted) return;
    if ((team ?? '').isNotEmpty) {
      await NotificationService.subscribeLeader(_selectedLeader!, team!);
    }
    if (!mounted) return;
    await SessionService.save(
        role: 'leader', name: _selectedLeader!, team: team ?? '');
    await FirestoreService.updatePresence(
      name: _selectedLeader!,
      role: 'leader',
      team: team ?? '',
      online: true,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(
            builder: (_) => TeamLeaderHomeScreen(
                leaderName: _selectedLeader!, team: team ?? '')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F64),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Center(
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('MONTAGEM USET',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3)),
                  const SizedBox(height: 4),
                  const Text('Gestão de Pendências',
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                ],
              ),
            ),
            const Spacer(flex: 2),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Role toggle (3 options)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    // Mesmos papéis no app e na web: uma experiência só, sem
                    // ramificação por plataforma.
                    child: Row(
                      children: [
                        _ToggleBtn(
                            label: 'Produtor',
                            icon: Icons.badge_outlined,
                            active: _role == 'producer',
                            onTap: () => _setRole('producer')),
                        _ToggleBtn(
                            label: 'Consultor',
                            icon: Icons.support_agent_outlined,
                            active: _role == 'consultant',
                            onTap: () => _setRole('consultant')),
                        _ToggleBtn(
                            label: 'Gerente',
                            icon: Icons.manage_accounts_outlined,
                            active: _role == 'manager',
                            onTap: () => _setRole('manager')),
                        _ToggleBtn(
                            label: 'Líder',
                            icon: Icons.groups_outlined,
                            active: _role == 'leader',
                            onTap: () => _setRole('leader')),
                        _ToggleBtn(
                            label: 'Analista',
                            icon: Icons.analytics_outlined,
                            active: _role == 'analyst',
                            onTap: () => _setRole('analyst')),
                        _ToggleBtn(
                            label: 'Admin',
                            icon: Icons.admin_panel_settings_outlined,
                            active: _role == 'admin',
                            onTap: () => _setRole('admin')),
                        _ToggleBtn(
                            label: 'Logística',
                            icon: Icons.local_shipping_outlined,
                            active: _role == 'logistica',
                            onTap: () => _setRole('logistica')),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Faixa única de nova tentativa: as listas vêm do Firestore,
                  // e sem a sessão anônima nenhuma delas carrega. No Safari do
                  // iPhone isso acontece com alguma frequência.
                  if (_cannotRead) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(children: [
                        const Text(
                          'Não foi possível conectar ao servidor.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _retryAll,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Tentar de novo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ]),
                    ),
                  ],

                  // Producer name pills
                  if (_role == 'producer') ...[
                    const Text('SEU NOME',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _loadingProducers
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : _producers.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200)),
                                child: Text(
                                    _cannotRead
                                        ? 'Não foi possível carregar a lista.\n'
                                            'Verifique sua conexão e toque em Tentar de novo.'
                                        : 'Nenhum produtor cadastrado.\nContate o administrador.',
                                    style: const TextStyle(
                                        color: Colors.orange, fontSize: 13)),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _producers.map((p) {
                                  final sel = _selectedProducer == p;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedProducer = p;
                                      _error = null;
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: sel ? const Color(0xFF1E3A5F) : Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: sel
                                              ? const Color(0xFF1E3A5F)
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(p,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: sel ? Colors.white : Colors.black87,
                                              fontSize: 13)),
                                    ),
                                  );
                                }).toList(),
                              ),
                    const SizedBox(height: 16),
                  ],

                  // Consultant name pills
                  if (_role == 'consultant') ...[
                    const Text('SEU NOME',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _loadingConsultants
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : _consultants.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200)),
                                child: Text(
                                    _cannotRead
                                        ? 'Não foi possível carregar a lista.\n'
                                            'Verifique sua conexão e toque em Tentar de novo.'
                                        : 'Nenhum consultor cadastrado.\nContate o administrador.',
                                    style: const TextStyle(
                                        color: Colors.orange, fontSize: 13)),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _consultants.map((p) {
                                  final sel = _selectedConsultant == p;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedConsultant = p;
                                      _error = null;
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: sel ? const Color(0xFF1E3A5F) : Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: sel
                                              ? const Color(0xFF1E3A5F)
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(p,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: sel ? Colors.white : Colors.black87,
                                              fontSize: 13)),
                                    ),
                                  );
                                }).toList(),
                              ),
                    const SizedBox(height: 16),
                  ],

                  // Manager name pills
                  if (_role == 'manager') ...[
                    const Text('SEU NOME',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _loadingManagers
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : _managers.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200)),
                                child: Text(
                                    _cannotRead
                                        ? 'Não foi possível carregar a lista.\n'
                                            'Verifique sua conexão e toque em Tentar de novo.'
                                        : 'Nenhum gerente cadastrado.\nContate o administrador.',
                                    style: const TextStyle(
                                        color: Colors.orange, fontSize: 13)),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _managers.map((p) {
                                  final sel = _selectedManager == p;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedManager = p;
                                      _error = null;
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: sel ? const Color(0xFF1E3A5F) : Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: sel
                                              ? const Color(0xFF1E3A5F)
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(p,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: sel ? Colors.white : Colors.black87,
                                              fontSize: 13)),
                                    ),
                                  );
                                }).toList(),
                              ),
                    const SizedBox(height: 16),
                  ],

                  // Leader dropdown
                  if (_role == 'leader') ...[
                    const Text('SEU NOME',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _loadingLeaders
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : _leaders.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200)),
                                child: Text(
                                    _cannotRead
                                        ? 'Não foi possível carregar a lista.\n'
                                            'Verifique sua conexão e toque em Tentar de novo.'
                                        : 'Nenhum líder cadastrado.\nContate o administrador.',
                                    style: const TextStyle(
                                        color: Colors.orange, fontSize: 13)),
                              )
                            : DropdownButtonFormField<String>(
                                value: _selectedLeader,
                                hint: const Text('Selecione seu nome'),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                ),
                                items: _leaders.map((l) {
                                  return DropdownMenuItem<String>(
                                    value: l['name'],
                                    child: Text('${l['name']} (${l['team']})'),
                                  );
                                }).toList(),
                                onChanged: (v) => setState(() {
                                  _selectedLeader = v;
                                  _error = null;
                                }),
                              ),
                    const SizedBox(height: 16),
                  ],

                  // Analyst name pills
                  if (_role == 'analyst') ...[
                    const Text('SEU NOME',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _loadingAnalysts
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : _analysts.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200)),
                                child: Text(
                                    _cannotRead
                                        ? 'Não foi possível carregar a lista.\n'
                                            'Verifique sua conexão e toque em Tentar de novo.'
                                        : 'Nenhum analista cadastrado.\nContate o administrador.',
                                    style: const TextStyle(
                                        color: Colors.orange, fontSize: 13)),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _analysts.map((p) {
                                  final sel = _selectedAnalyst == p;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedAnalyst = p;
                                      _error = null;
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: sel ? const Color(0xFF1E3A5F) : Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: sel
                                              ? const Color(0xFF1E3A5F)
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(p,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: sel ? Colors.white : Colors.black87,
                                              fontSize: 13)),
                                    ),
                                  );
                                }).toList(),
                              ),
                    const SizedBox(height: 16),
                  ],

                  // Admin name pills
                  if (_role == 'admin' && !_loadingAdmins && _admins.isNotEmpty) ...[
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
                      children: _admins.map((p) {
                        final sel = _selectedAdmin == p;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedAdmin = p;
                            _error = null;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFF1E3A5F) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFF1E3A5F)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(p,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : Colors.black87,
                                    fontSize: 13)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_role == 'admin' && _loadingAdmins) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Logistics name pills
                  if (_role == 'logistica') ...[
                    const Text('SEU NOME',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _loadingLogistics
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : _logistics.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.orange.shade200)),
                                child: Text(
                                    _cannotRead
                                        ? 'Não foi possível carregar a lista.\n'
                                            'Verifique sua conexão e toque em Tentar de novo.'
                                        : 'Nenhum usuário de logística cadastrado.\nContate o administrador.',
                                    style: TextStyle(
                                        color: Colors.orange, fontSize: 13)),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _logistics.map((p) {
                                  final sel = _selectedLogistics == p;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedLogistics = p;
                                      _error = null;
                                    }),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: sel
                                            ? const Color(0xFF1E3A5F)
                                            : Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                          color: sel
                                              ? const Color(0xFF1E3A5F)
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(p,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: sel
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontSize: 13)),
                                    ),
                                  );
                                }).toList(),
                              ),
                    const SizedBox(height: 16),
                  ],

                  // PIN field
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
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: _role == 'admin' ? 'PIN de administrador' : 'Seu PIN de acesso',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      counterText: '',
                    ),
                    onSubmitted: (_) => _enter(),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200)),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red, fontSize: 13))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 20),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _verifying ? null : _enter,
                      icon: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: Text(_verifying ? 'Verificando...' : 'Entrar',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
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
          ],
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ToggleBtn(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1E3A5F) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: active ? Colors.white : Colors.grey, size: 20),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

