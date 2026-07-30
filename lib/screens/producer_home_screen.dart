import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../widgets/inbox_bell.dart';
import 'global_search_screen.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../widgets/app_drawer.dart';
import 'login_screen.dart';
import 'producer_hangar_list_screen.dart';
import 'freight_request_form_screen.dart';
import 'freight_requests_screen.dart';

class ProducerHomeScreen extends StatefulWidget {
  final String producerName;
  const ProducerHomeScreen({super.key, required this.producerName});

  @override
  State<ProducerHomeScreen> createState() => _ProducerHomeScreenState();
}

class _ProducerHomeScreenState extends State<ProducerHomeScreen> {
  AppProvider? _provider;
  List<int> _fairIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider = context.read<AppProvider>();
      _provider!.addListener(_onFairsChanged);
      _syncReminder();
      _loadFairIds();
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onFairsChanged);
    super.dispose();
  }

  void _onFairsChanged() {
    _syncReminder();
    _loadFairIds();
  }

  void _syncReminder() {
    final fairs = context.read<AppProvider>().fairs;
    NotificationService.syncMontageReminder(fairs);
  }

  Future<void> _loadFairIds() async {
    var ids =
        await DatabaseService.getFairIdsWithProducer(widget.producerName);
    // Ver comentário em ConsultantHomeScreen: sem isto, aparelho novo não
    // mostra feira nenhuma e não há como sair do lugar.
    if (ids.isEmpty && mounted) {
      final achou = await context.read<AppProvider>().ensurePersonFairs(
            role: 'producer',
            name: widget.producerName,
          );
      if (achou) {
        ids = await DatabaseService.getFairIdsWithProducer(widget.producerName);
      }
    }
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
        title: Text(widget.producerName,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        actions: [
          const InboxBell(),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            tooltip: 'Buscar stand',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const GlobalSearchScreen())),
          ),
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
                  // Desabilitar quando a lista está vazia trancava o botão
                  // justamente no aparelho novo, que é quando ele é preciso.
                  onPressed: () => context.read<AppProvider>().syncAllFairs(),
                ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sair',
            onPressed: () async {
              try {
                await NotificationService.syncMontageReminder([]);
              } catch (_) {}
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
      body: fairs.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: fairs.length,
              itemBuilder: (context, i) {
                final fair = fairs[i];
                return _FairCard(
                  fair: fair,
                  producerName: widget.producerName,
                  onTap: () async {
                    await context.read<AppProvider>().selectFair(fair);
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProducerHangarListScreen(
                              producerName: widget.producerName),
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
  final String producerName;
  final VoidCallback onTap;
  const _FairCard({required this.fair, required this.producerName, required this.onTap});

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
          child: Column(
            children: [
              Row(
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
                            style: TextStyle(
                                fontSize: 12, color: _modeColor)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.local_shipping_outlined, size: 18),
                      label: const Text('Solicitar Logística'),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FreightRequestFormScreen(
                              fairId: fair.id!,
                              fairName: fair.name,
                              requestedBy: producerName,
                              requestedByRole: 'producer',
                            ),
                          )),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E3A5F)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: const Text('Fretes'),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FreightRequestsScreen(
                            fairId: fair.id!,
                            fairName: fair.name,
                            viewerRole: 'producer',
                            viewerName: producerName,
                          ),
                        )),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A5F)),
                  ),
                ],
              ),
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
