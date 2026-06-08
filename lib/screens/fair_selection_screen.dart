import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/fair.dart';
import '../utils/admin_pin.dart';
import 'hangar_list_screen.dart';
import 'add_fair_screen.dart';
import 'producer_login_screen.dart';

class FairSelectionScreen extends StatelessWidget {
  const FairSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final fairs = provider.fairs;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Selecionar Feira',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.badge_outlined, color: Colors.white),
            tooltip: 'Acesso Produtor',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const ProducerLoginScreen())),
          ),
        ],
      ),
      body: fairs.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: fairs.length,
              itemBuilder: (context, i) => _FairCard(fair: fairs[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await requireAdminPin(context);
          if (ok && context.mounted) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddFairScreen()));
          }
        },
        backgroundColor: const Color(0xFF1E3A5F),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nova Feira',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _FairCard extends StatelessWidget {
  final Fair fair;
  const _FairCard({required this.fair});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () async {
          await context.read<AppProvider>().selectFair(fair);
          if (context.mounted) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HangarListScreen()));
          }
        },
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fair.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Aba: ${fair.sheetName}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
              if (fair.id != 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(context),
                ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await requireAdminPin(context);
    if (!ok || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir feira?'),
        content: Text(
            'Todos os clientes e pendências de "${fair.name}" serão excluídos permanentemente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppProvider>().deleteFair(fair.id!);
    }
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
          Text('Toque em "Nova Feira" para começar',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
