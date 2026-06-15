import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/session_service.dart';
import '../widgets/app_drawer.dart';
import 'login_screen.dart';
import 'team_leader_hangar_list_screen.dart';

class TeamLeaderHomeScreen extends StatefulWidget {
  final String leaderName;
  final String team;
  const TeamLeaderHomeScreen(
      {super.key, required this.leaderName, required this.team});

  @override
  State<TeamLeaderHomeScreen> createState() => _TeamLeaderHomeScreenState();
}

class _TeamLeaderHomeScreenState extends State<TeamLeaderHomeScreen> {
  List<int> _fairIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFairs());
  }

  Future<void> _loadFairs() async {
    final ids = await DatabaseService.getFairIdsWithLeader(
        widget.leaderName, widget.team);
    if (mounted) setState(() => _fairIds = ids);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final fairs = provider.fairs
        .where((f) => f.sheetMode != 'mestra' && _fairIds.contains(f.id))
        .toList();
    final isSyncing = provider.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.leaderName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
            Text(widget.team,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          isSyncing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.sync, color: Colors.white),
                  tooltip: 'Sincronizar todas as feiras',
                  onPressed: fairs.isEmpty && _fairIds.isEmpty
                      ? null
                      : () async {
                          await context.read<AppProvider>().syncAllFairs();
                          await _loadFairs();
                        },
                ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sair',
            onPressed: () async {
              await SessionService.clear();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false);
              }
            },
          ),
        ],
      ),
      body: fairs.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: fairs.length,
              itemBuilder: (context, i) {
                final fair = fairs[i];
                return _FairCard(
                  fair: fair,
                  onTap: () async {
                    await context.read<AppProvider>().selectFair(fair);
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeamLeaderHangarListScreen(
                              leaderName: widget.leaderName, team: widget.team),
                        ),
                      );
                    }
                  },
                );
              },
            ),
    );
  }
}

class _FairCard extends StatelessWidget {
  final Fair fair;
  final VoidCallback onTap;
  const _FairCard({required this.fair, required this.onTap});

  Color get _modeColor {
    if (fair.isMaintenance) return Colors.orange;
    if (fair.isProduction) return Colors.green;
    return Colors.blueGrey;
  }

  String get _modeLabel {
    if (fair.isMaintenance) return 'Manutenção';
    if (fair.isProduction) return 'Produção';
    return 'Pré-produção';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _modeColor.withOpacity(0.5), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _modeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.event, color: _modeColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fair.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(_modeLabel,
                        style: TextStyle(fontSize: 12, color: _modeColor)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 72, color: Colors.grey),
          SizedBox(height: 16),
          Text('Nenhuma feira cadastrada',
              style: TextStyle(color: Colors.grey, fontSize: 18)),
          SizedBox(height: 8),
          Text('Contate o administrador.',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
