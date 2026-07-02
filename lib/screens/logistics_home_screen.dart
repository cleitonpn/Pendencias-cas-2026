import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../widgets/app_drawer.dart';
import 'login_screen.dart';
import 'freight_requests_screen.dart';

class LogisticsHomeScreen extends StatelessWidget {
  final String logisticsName;
  const LogisticsHomeScreen({super.key, required this.logisticsName});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final fairs = provider.fairs.where((f) => f.sheetMode != 'mestra').toList();
    final isSyncing = provider.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(showGallery: false),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(logisticsName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
            const Text('Logística',
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
                  onPressed: fairs.isEmpty
                      ? null
                      : () => context.read<AppProvider>().syncAllFairs(),
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
      body: fairs.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 72, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Nenhuma feira cadastrada',
                      style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: fairs.length,
              itemBuilder: (context, i) {
                final fair = fairs[i];
                return _FairCard(
                  fair: fair,
                  logisticsName: logisticsName,
                );
              },
            ),
    );
  }
}

class _FairCard extends StatelessWidget {
  final Fair fair;
  final String logisticsName;
  const _FairCard({required this.fair, required this.logisticsName});

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
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FreightRequestsScreen(
              fairId: fair.id!,
              fairName: fair.name,
              viewerRole: 'logistica',
              viewerName: logisticsName,
            ),
          ),
        ),
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
                child: Icon(Icons.local_shipping_outlined,
                    color: _modeColor, size: 28),
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
