import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../services/database_service.dart';
import 'consultant_client_list_screen.dart';

class ConsultantHangarListScreen extends StatefulWidget {
  final String consultantName;

  const ConsultantHangarListScreen({super.key, required this.consultantName});

  @override
  State<ConsultantHangarListScreen> createState() =>
      _ConsultantHangarListScreenState();
}

class _ConsultantHangarListScreenState
    extends State<ConsultantHangarListScreen> {
  Map<String, int> _pendingCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  Future<void> _loadCounts() async {
    final clients = _allClients;
    if (clients.isEmpty) return;
    final counts = await DatabaseService.getPendingCounts(
        clients.map((c) => c.rowId).toList());
    if (mounted) setState(() => _pendingCounts = counts);
  }

  bool _matchesConsultant(Client c) =>
      c.atendimento.toLowerCase().trim() ==
      widget.consultantName.toLowerCase().trim();

  List<Client> get _allClients {
    final all = context.read<AppProvider>().clients;
    return all.where(_matchesConsultant).toList()
      ..sort((a, b) {
        final h = a.hangar.compareTo(b.hangar);
        if (h != 0) return h;
        return a.local.compareTo(b.local);
      });
  }

  List<String> _hangarsFor(List<Client> clients) {
    final seen = <String>{};
    final result = <String>[];
    for (final c in clients) {
      final h = c.hangar.isEmpty ? 'Todos os Stands' : c.hangar;
      if (seen.add(h)) result.add(h);
    }
    result.sort((a, b) {
      if (a == 'Todos os Stands') return 1;
      if (b == 'Todos os Stands') return -1;
      return a.compareTo(b);
    });
    return result;
  }

  List<Client> _clientsInHangar(List<Client> all, String hangar) {
    return all.where((c) {
      final h = c.hangar.isEmpty ? 'Todos os Stands' : c.hangar;
      return h == hangar;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final clients = _allClients;
    final hangars = _hangarsFor(clients);

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
          IconButton(
            icon: provider.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Sincronizar',
            onPressed: provider.isLoading
                ? null
                : () async {
                    await context.read<AppProvider>().syncFromSheets();
                    await _loadCounts();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (provider.lastSync == null)
            Container(
              color: Colors.orange.shade100,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off, size: 14, color: Colors.orange),
                  SizedBox(width: 6),
                  Text('Dados não sincronizados. Toque em sincronizar.',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
                ],
              ),
            )
          else
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done, size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    'Última sync: ${DateFormat('dd/MM HH:mm').format(provider.lastSync!)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          if (clients.isEmpty && !provider.isLoading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warehouse_outlined,
                        size: 72, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('Nenhum cliente sob sua responsabilidade',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () =>
                          context.read<AppProvider>().syncFromSheets(),
                      icon: const Icon(Icons.sync),
                      label: const Text('Sincronizar Planilha'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A5F),
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: hangars.length,
                itemBuilder: (context, i) {
                  final hangar = hangars[i];
                  final hangarClients = _clientsInHangar(clients, hangar);
                  final pendingInHangar = hangarClients.fold<int>(
                      0,
                      (sum, c) => sum + (_pendingCounts[c.rowId] ?? 0));

                  return _HangarCard(
                    hangar: hangar,
                    clientCount: hangarClients.length,
                    pendingCount: pendingInHangar,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConsultantClientListScreen(
                            hangar: hangar,
                            consultantName: widget.consultantName,
                          ),
                        ),
                      );
                      await _loadCounts();
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

class _HangarCard extends StatelessWidget {
  final String hangar;
  final int clientCount;
  final int pendingCount;
  final VoidCallback onTap;

  const _HangarCard({
    required this.hangar,
    required this.clientCount,
    required this.pendingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        pendingCount > 0 ? Colors.orange : const Color(0xFF1E3A5F);

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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.warehouse, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        (hangar == 'Todos os Stands')
                            ? hangar
                            : 'Hangar $hangar',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                        '$clientCount cliente${clientCount != 1 ? "s" : ""}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
              if (pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$pendingCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
