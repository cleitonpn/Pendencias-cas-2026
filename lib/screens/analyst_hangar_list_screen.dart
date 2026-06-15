import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../widgets/fair_info_header.dart';
import 'analyst_client_detail_screen.dart';

class AnalystHangarListScreen extends StatelessWidget {
  final String analystName;
  const AnalystHangarListScreen({super.key, required this.analystName});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final clients = provider.clients;
    final hangars = provider.hangars;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        elevation: 0,
        title: Text(provider.currentFairName,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        actions: [
          provider.isLoading
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
                  tooltip: 'Sincronizar',
                  onPressed: () => context.read<AppProvider>().syncFromSheets(),
                ),
        ],
      ),
      body: Column(
        children: [
          _SyncBar(provider: provider),
          FairInfoHeader(clients: clients, showDriveLink: true),
          if (hangars.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Nenhum cliente cadastrado.',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: hangars.length,
                itemBuilder: (context, i) {
                  final hangar = hangars[i];
                  final hangarClients = provider.getClientsByHangar(hangar);
                  return _HangarCard(
                    hangar: hangar,
                    clients: hangarClients,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AnalystClientDetailScreen(
                          clients: hangarClients,
                          hangar: hangar,
                          analystName: analystName,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SyncBar extends StatelessWidget {
  final AppProvider provider;
  const _SyncBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.lastSync == null) {
      return Container(
        color: Colors.orange.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: const Row(
          children: [
            Icon(Icons.cloud_off, size: 14, color: Colors.orange),
            SizedBox(width: 6),
            Text('Dados não sincronizados. Toque em sincronizar.',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
          ],
        ),
      );
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud_done, size: 14, color: Colors.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Última sync: ${DateFormat('dd/MM HH:mm').format(provider.lastSync!)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          if (provider.isLoading)
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}

class _HangarCard extends StatelessWidget {
  final String hangar;
  final List<dynamic> clients;
  final VoidCallback onTap;
  const _HangarCard(
      {required this.hangar, required this.clients, required this.onTap});

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
                child: const Icon(Icons.warehouse_outlined,
                    color: Color(0xFF1E3A5F), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hangar $hangar',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('${clients.length} clientes',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
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
