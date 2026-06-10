import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import 'login_screen.dart';
import 'producer_hangar_list_screen.dart';

class ProducerHomeScreen extends StatefulWidget {
  final String producerName;
  const ProducerHomeScreen({super.key, required this.producerName});

  @override
  State<ProducerHomeScreen> createState() => _ProducerHomeScreenState();
}

class _ProducerHomeScreenState extends State<ProducerHomeScreen> {
  AppProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider = context.read<AppProvider>();
      _provider!.addListener(_onFairsChanged);
      _syncReminder();
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onFairsChanged);
    super.dispose();
  }

  void _onFairsChanged() => _syncReminder();

  void _syncReminder() {
    final fairs = context.read<AppProvider>().fairs;
    NotificationService.syncMontageReminder(fairs);
  }

  @override
  Widget build(BuildContext context) {
    final fairs = context.watch<AppProvider>().fairs;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(widget.producerName,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sair',
            onPressed: () async {
              await NotificationService.syncMontageReminder([]);
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
                  fairName: fair.name,
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
  final String fairName;
  final VoidCallback onTap;
  const _FairCard({required this.fairName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  color: const Color(0xFF1E3A5F).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event,
                    color: Color(0xFF1E3A5F), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(fairName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
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
