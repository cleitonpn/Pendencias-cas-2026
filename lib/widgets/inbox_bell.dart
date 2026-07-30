import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/inbox_service.dart';
import '../services/notification_router.dart';

/// Sino de novidades, para a AppBar.
///
/// Nasceu para o app web: consultores e líderes de iPhone acessam por ele e
/// não recebem notificação nenhuma. Sem isto, a única forma de saber que
/// chegou serviço era ficar abrindo as telas para conferir.
///
/// No Android também serve, porque a notificação some da barra depois de
/// tocada e aqui a lista continua.
class InboxBell extends StatefulWidget {
  const InboxBell({super.key});

  @override
  State<InboxBell> createState() => _InboxBellState();
}

class _InboxBellState extends State<InboxBell> {
  List<InboxItem> _itens = [];
  bool _carregando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    if (_carregando) return;
    setState(() => _carregando = true);
    final provider = context.read<AppProvider>();
    final desde = await InboxService.lastSeen();
    final itens = await InboxService.load(
      desde: desde,
      // Só as feiras que este aparelho conhece: varrer todas as feiras de
      // todos os tempos deixaria a abertura da tela lenta sem necessidade.
      fairNames: provider.fairs
          .where((f) => !f.isMestra)
          .map((f) => f.name)
          .toList(),
    );
    if (mounted) {
      setState(() {
        _itens = itens;
        _carregando = false;
      });
    }
  }

  Future<void> _abrir() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _InboxSheet(itens: _itens),
    );
    // Abrir marca como visto; fechar limpa o contador.
    await InboxService.markSeen();
    if (mounted) setState(() => _itens = []);
  }

  @override
  Widget build(BuildContext context) {
    final n = _itens.length;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          tooltip: 'Novidades',
          onPressed: _abrir,
        ),
        if (n > 0)
          Positioned(
            right: 6,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                n > 99 ? '99+' : '$n',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

class _InboxSheet extends StatelessWidget {
  final List<InboxItem> itens;

  const _InboxSheet({required this.itens});

  static const _navy = Color(0xFF1E3A5F);

  IconData _icone(String tipo) => switch (tipo) {
        'aviso' => Icons.campaign_outlined,
        'meeting' => Icons.event_note_outlined,
        _ => Icons.assignment_outlined,
      };

  Future<void> _abrirItem(BuildContext context, InboxItem item) async {
    Navigator.pop(context);
    if (item.type == 'pending' && item.clientId.isNotEmpty) {
      // Reaproveita o roteador das notificações: ele já resolve o cliente em
      // qualquer feira e escolhe a tela certa para o papel de quem está
      // logado.
      NotificationRouter.handle({
        'type': 'pending',
        'clientId': item.clientId,
        'fairName': item.fairName,
      });
    } else if (item.type == 'meeting') {
      NotificationRouter.handle({'type': 'meeting'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.notifications_outlined,
                    color: _navy, size: 20),
                const SizedBox(width: 8),
                Text(
                  itens.isEmpty
                      ? 'Novidades'
                      : 'Novidades (${itens.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _navy),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: itens.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('Nada novo por aqui.',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 14)),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: itens.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 60),
                    itemBuilder: (context, i) {
                      final item = itens[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE8F0FB),
                          child: Icon(_icone(item.type),
                              color: _navy, size: 20),
                        ),
                        title: Text(item.title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          item.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Text(
                          DateFormat('dd/MM HH:mm').format(item.at),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey),
                        ),
                        onTap: () => _abrirItem(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
