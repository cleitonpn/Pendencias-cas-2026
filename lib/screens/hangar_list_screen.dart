import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import 'client_list_screen.dart';
import 'settings_screen.dart';
import 'reports_screen.dart';

class HangarListScreen extends StatelessWidget {
  const HangarListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        elevation: 0,
        title: const Text('CAS 2026',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment_outlined, color: Colors.white),
            tooltip: 'Relatórios',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReportsScreen())),
          ),
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
                : () => context.read<AppProvider>().syncFromSheets(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          _SyncBar(provider: provider),
          if (provider.error != null)
            _ErrorBanner(message: provider.error!),
          Expanded(child: _Body(provider: provider)),
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
          Text(
            'Última sync: ${DateFormat('dd/MM HH:mm').format(provider.lastSync!)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (provider.isLoading) ...[
            const SizedBox(width: 12),
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.red, fontSize: 13))),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final AppProvider provider;
  const _Body({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.hangars.isEmpty && !provider.isLoading) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.warehouse_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Nenhum dado carregado',
              style: TextStyle(fontSize: 18, color: Colors.grey)),
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
        ]),
      );
    }

    final hangars = provider.hangars;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: hangars.length,
      itemBuilder: (context, i) {
        final hangar = hangars[i];
        final clients = provider.getClientsByHangar(hangar);
        final completed = clients.where((c) => c.isCompleted).length;
        final progress =
            clients.isEmpty ? 0.0 : completed / clients.length;
        return _HangarCard(
          hangar: hangar,
          total: clients.length,
          completed: completed,
          progress: progress,
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ClientListScreen(hangar: hangar))),
        );
      },
    );
  }
}

class _HangarCard extends StatelessWidget {
  final String hangar;
  final int total;
  final int completed;
  final double progress;
  final VoidCallback onTap;

  const _HangarCard({
    required this.hangar,
    required this.total,
    required this.completed,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = progress == 1.0
        ? Colors.green
        : progress > 0.5
            ? Colors.orange
            : const Color(0xFF1E3A5F);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                        Text('Hangar $hangar',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text('$total stands',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$completed/$total',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontSize: 18)),
                      const Text('concluídos',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
