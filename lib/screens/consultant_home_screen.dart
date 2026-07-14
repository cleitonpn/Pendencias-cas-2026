import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../widgets/app_drawer.dart';
import 'login_screen.dart';
import 'consultant_hangar_list_screen.dart';
import 'organizer_approval_screen.dart';

class ConsultantHomeScreen extends StatefulWidget {
  final String consultantName;
  const ConsultantHomeScreen({super.key, required this.consultantName});

  @override
  State<ConsultantHomeScreen> createState() => _ConsultantHomeScreenState();
}

class _ConsultantHomeScreenState extends State<ConsultantHomeScreen> {
  AppProvider? _provider;
  List<int> _fairIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider = context.read<AppProvider>();
      _provider!.addListener(_onFairsChanged);
      _loadFairIds();
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onFairsChanged);
    super.dispose();
  }

  void _onFairsChanged() => _loadFairIds();

  Future<void> _loadFairIds() async {
    final ids = await DatabaseService.getFairIdsWithConsultant(widget.consultantName);
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
            Text(widget.consultantName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
            const Text('Consultor',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
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
                  onPressed: () => context.read<AppProvider>().syncAllFairs(),
                ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sair',
            onPressed: () async {
              final s = await SessionService.get();
              await FirestoreService.clearPresence(
                  s?['name'] ?? '', s?['role'] ?? '');
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
      body: Column(
        children: [
          // ── Approval banner (Firestore stream, always live) ─────────────────
          _ApprovalBanner(consultantName: widget.consultantName),
          // ── Fairs list ──────────────────────────────────────────────────────
          Expanded(
            child: fairs.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                                builder: (_) => ConsultantHangarListScreen(
                                    consultantName: widget.consultantName),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Approval banner ──────────────────────────────────────────────────────────

class _ApprovalBanner extends StatelessWidget {
  final String consultantName;
  const _ApprovalBanner({required this.consultantName});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PendingItem>>(
      stream: FirestoreService.streamAllPendingApprovals(),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0 && snap.connectionState != ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTap: count == 0
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrganizerApprovalScreen(
                          consultantName: consultantName),
                    ),
                  ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: count > 0
                  ? Colors.orange.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: count > 0
                      ? Colors.orange.shade300
                      : Colors.grey.shade300,
                  width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined,
                    color: count > 0 ? Colors.orange.shade800 : Colors.grey,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const Text('Verificando pedidos da organizadora…',
                          style: TextStyle(color: Colors.grey, fontSize: 13))
                      : Text(
                          count == 0
                              ? 'Nenhum pedido aguardando aprovação'
                              : count == 1
                                  ? '1 pedido da organizadora aguardando aprovação'
                                  : '$count pedidos da organizadora aguardando aprovação',
                          style: TextStyle(
                              color: count > 0
                                  ? Colors.orange.shade900
                                  : Colors.grey,
                              fontWeight: count > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 13),
                        ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade800,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      color: Colors.orange.shade800, size: 20),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Fair card ────────────────────────────────────────────────────────────────

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
          Text('Nenhuma feira com seus clientes',
              style: TextStyle(color: Colors.grey, fontSize: 18)),
          SizedBox(height: 8),
          Text('Sincronize para atualizar os dados.',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
