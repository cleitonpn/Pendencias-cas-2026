import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/fair.dart';
import '../services/session_service.dart';
import '../services/firestore_service.dart';
import '../utils/admin_pin.dart';
import '../widgets/app_drawer.dart';
import 'hangar_list_screen.dart';
import 'add_fair_screen.dart';
import 'login_screen.dart';
import 'producer_login_screen.dart';
import 'settings_screen.dart';
import 'sticker_generator_screen.dart';
import 'spec_edit_requests_screen.dart';
import 'archived_fairs_screen.dart';
import 'freight_requests_screen.dart';
import 'freight_report_screen.dart';
import 'organizer_approval_screen.dart';

class FairSelectionScreen extends StatelessWidget {
  final bool canManage;
  const FairSelectionScreen({super.key, this.canManage = true});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    // Hide master fairs — they're containers only; derived fairs are shown instead
    final fairs = provider.fairs.where((f) => f.sheetMode != 'mestra').toList();
    final isSyncing = provider.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(showGallery: true),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Selecionar Feira',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (canManage) ...[
            IconButton(
              icon: const Icon(Icons.badge_outlined, color: Colors.white),
              tooltip: 'Acesso Produtor',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const ProducerLoginScreen())),
            ),
            IconButton(
              icon: const Icon(Icons.archive_outlined, color: Colors.white),
              tooltip: 'Feiras Arquivadas',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ArchivedFairsScreen())),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              tooltip: 'Configurações',
              onPressed: () async {
                final ok = await requireAdminPin(context);
                if (ok && context.mounted) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()));
                }
              },
            ),
          ],
          // Sync all button — visible to any authenticated role
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
                  // Desabilitar com a lista vazia trancava o botão justamente
                  // no aparelho novo, que é quando ele é preciso.
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
          if (isSyncing)
            const LinearProgressIndicator(
              backgroundColor: Color(0xFFD0D8E4),
              color: Color(0xFF1E3A5F),
            ),
          if (provider.lastGlobalSync != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFE8F0FB),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Último sync: ${_fmt(provider.lastGlobalSync!)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF1E3A5F)),
              ),
            ),
          if (provider.error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFEBEE),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                provider.error!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          if (canManage) const _SpecEditRequestsBanner(),
          if (canManage) const OrganizerApprovalBanner(),
          Expanded(
            child: fairs.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: fairs.length,
                    itemBuilder: (context, i) =>
                        _FairCard(fair: fairs[i], canManage: canManage),
                  ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
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
                  style:
                      TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  static String _fmt(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d/$mo $h:$mi';
  }
}

class _FairCard extends StatelessWidget {
  final Fair fair;
  final bool canManage;
  const _FairCard({required this.fair, this.canManage = true});

  Color get _modeColor {
    if (fair.isMaintenance) return Colors.orange;
    if (fair.isProduction) return Colors.green;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _modeColor.withOpacity(0.6), width: 1.5),
      ),
      child: InkWell(
        onTap: () async {
          await context.read<AppProvider>().selectFair(fair);
          if (context.mounted) {
            Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => HangarListScreen(canManage: canManage)));
          }
        },
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
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_2, color: Color(0xFF1E3A5F)),
                    tooltip: 'Gerar adesivos',
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                StickerGeneratorScreen(fair: fair))),
                  ),
                  if (canManage) ...[
                    IconButton(
                      icon: const Icon(Icons.archive_outlined, color: Colors.blueGrey),
                      tooltip: 'Arquivar feira',
                      onPressed: () => _confirmArchive(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDelete(context),
                    ),
                  ],
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              if (canManage) ...[
                const Divider(height: 18),
                _ModeToggle(fair: fair),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.local_shipping_outlined,
                            size: 16),
                        label: const Text('Fretes'),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FreightRequestsScreen(
                                fairId: fair.id!,
                                fairName: fair.name,
                                viewerRole: 'admin',
                                viewerName: 'Admin',
                              ),
                            )),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E3A5F),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bar_chart_outlined, size: 16),
                        label: const Text('Relatório'),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FreightReportScreen(
                                fairId: fair.id!,
                                fairName: fair.name,
                              ),
                            )),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal.shade700,
                          side: BorderSide(color: Colors.teal.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arquivar feira?'),
        content: Text(
            '"${fair.name}" será ocultada da lista principal. Você pode restaurá-la depois.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
            child: const Text('Arquivar'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppProvider>().archiveFair(fair);
    }
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

class _ModeToggle extends StatelessWidget {
  final Fair fair;
  const _ModeToggle({required this.fair});

  String get _subtitle {
    if (fair.isMaintenance) {
      return 'Evento: expositores pedem manutenção pelo QR';
    }
    if (fair.isProduction) {
      return 'Equipe montando — lembrete diário de foto ao produtor às 18h';
    }
    return 'Pré-produção — sem notificações';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _seg(context, 'pre_producao', 'Pré-prod.', Icons.schedule,
                Colors.blueGrey),
            const SizedBox(width: 6),
            _seg(context, 'producao', 'Produção', Icons.handyman,
                Colors.green),
            const SizedBox(width: 6),
            _seg(context, 'manutencao', 'Manutenção', Icons.construction,
                Colors.orange),
          ],
        ),
        const SizedBox(height: 6),
        Text(_subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const Divider(height: 18),
        // Aprovação automática: pedidos da organizadora entram já liberados,
        // sem passar por consultor/admin.
        Row(children: [
          Icon(
            fair.autoApprove ? Icons.flash_on : Icons.how_to_reg,
            size: 16,
            color: fair.autoApprove ? Colors.amber.shade800 : Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aprovação automática',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(
                  fair.autoApprove
                      ? 'Pedidos da organizadora entram já aprovados'
                      : 'Pedidos da organizadora aguardam aprovação',
                  style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                ),
              ],
            ),
          ),
          Switch(
            value: fair.autoApprove,
            activeColor: Colors.amber.shade800,
            onChanged: fair.id == null
                ? null
                : (v) => context
                    .read<AppProvider>()
                    .setFairAutoApprove(fair.id!, v),
          ),
        ]),
      ],
    );
  }

  Widget _seg(BuildContext context, String mode, String label, IconData icon,
      Color color) {
    final selected = fair.mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: selected
            ? null
            : () => context.read<AppProvider>().setFairMode(fair, mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? color : Colors.grey.shade300,
                width: selected ? 1.5 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: selected ? color : Colors.grey),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? color : Colors.grey.shade600)),
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
    final provider = context.watch<AppProvider>();
    final syncing = provider.isLoading;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(syncing ? Icons.cloud_sync : Icons.event_busy,
                size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            Text(syncing ? 'Sincronizando planilhas…' : 'Nenhuma feira aqui',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              syncing
                  ? 'A primeira carga demora um pouco. Pode deixar aberto.'
                  : 'Num aparelho novo os dados ainda não foram baixados. '
                      'Toque abaixo para carregar.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            if (syncing)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              ElevatedButton.icon(
                onPressed: () => context.read<AppProvider>().syncAllFairs(),
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar planilhas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Loads pending spec-edit requests from Firestore and shows a tappable
/// banner when there are any. Hides itself when count == 0.
class _SpecEditRequestsBanner extends StatefulWidget {
  const _SpecEditRequestsBanner();

  @override
  State<_SpecEditRequestsBanner> createState() =>
      _SpecEditRequestsBannerState();
}

class _SpecEditRequestsBannerState extends State<_SpecEditRequestsBanner> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await FirestoreService.getPendingSpecEditRequests();
    if (mounted) setState(() => _count = list.length);
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const SpecEditRequestsScreen()),
        );
        _load();
      },
      child: Container(
        color: Colors.orange.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_note,
                  color: Colors.orange.shade800, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$_count solicitaç${_count == 1 ? 'ão' : 'ões'} de edição pendente${_count == 1 ? '' : 's'}',
                style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.orange.shade600),
          ],
        ),
      ),
    );
  }
}
