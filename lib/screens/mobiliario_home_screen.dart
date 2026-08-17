import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../utils/furniture_items.dart';
import '../widgets/app_drawer.dart';
import '../widgets/inbox_bell.dart';
import 'furniture_classify_screen.dart';
import 'global_search_screen.dart';
import 'login_screen.dart';

/// Tela da equipe de mobiliário.
///
/// Diferente dos outros papéis, esta equipe atende TODAS as feiras ao mesmo
/// tempo — o estoque é um só e a sublocação também. Por isso a tela abre pela
/// feira e mostra, de cara, quanto falta classificar: é a fila de trabalho
/// deles.
class MobiliarioHomeScreen extends StatefulWidget {
  final String name;
  const MobiliarioHomeScreen({super.key, required this.name});

  @override
  State<MobiliarioHomeScreen> createState() => _MobiliarioHomeScreenState();
}

class _MobiliarioHomeScreenState extends State<MobiliarioHomeScreen> {
  static const _navy = Color(0xFF1E3A5F);

  /// fairId → (com mobiliário, sem classificar)
  final Map<int, ({int comMobiliario, int faltando})> _resumo = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final provider = context.read<AppProvider>();
    final resumo = <int, ({int comMobiliario, int faltando})>{};

    for (final f in provider.fairs.where((f) => !f.isMestra)) {
      if (f.id == null) continue;
      try {
        final clientes = await DatabaseService.getClients(fairId: f.id!);
        final comMob = clientes
            .where((c) => c.mobilario.trim().isNotEmpty)
            .toList();
        if (comMob.isEmpty) continue;

        final classificados =
            await FirestoreService.getFurnitureKindsForFair(f.name);
        var faltando = 0;
        for (final c in comMob) {
          final itens = furnitureItemsFrom(c.mobilario);
          final jaFeito = classificados[c.firestoreId] ?? const {};
          if (itens.any((i) => !jaFeito.containsKey(i.key))) faltando++;
        }
        resumo[f.id!] = (comMobiliario: comMob.length, faltando: faltando);
      } catch (_) {
        // Feira indisponível agora; as outras continuam aparecendo.
      }
    }

    if (mounted) {
      setState(() {
        _resumo
          ..clear()
          ..addAll(resumo);
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final feiras = provider.fairs
        .where((f) => !f.isMestra && _resumo.containsKey(f.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: _navy,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
            const Text('Mobiliário',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          const InboxBell(),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            tooltip: 'Buscar stand',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GlobalSearchScreen())),
          ),
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
                  tooltip: 'Sincronizar todas as feiras',
                  onPressed: () async {
                    await context.read<AppProvider>().syncAllFairs();
                    await _carregar();
                  },
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
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : feiras.isEmpty
              ? _vazio(provider)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: feiras.length,
                    itemBuilder: (context, i) => _cardFeira(feiras[i]),
                  ),
                ),
    );
  }

  Widget _vazio(AppProvider provider) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chair_alt, size: 72, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Nenhuma feira com mobiliário',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 18)),
              const SizedBox(height: 8),
              const Text(
                'Só aparecem aqui as feiras que têm stand com a coluna '
                '"mobiliário locado" preenchida. Num aparelho novo, '
                'sincronize primeiro.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  await provider.syncAllFairs();
                  await _carregar();
                },
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar planilhas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _cardFeira(Fair fair) {
    final r = _resumo[fair.id]!;
    final completo = r.faltando == 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: completo ? Colors.green.shade200 : Colors.orange.shade300,
            width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await context.read<AppProvider>().selectFair(fair);
          if (!context.mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _FurnitureFairScreen(fair: fair),
            ),
          );
          await _carregar();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (completo ? Colors.green : Colors.orange)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(completo ? Icons.check_circle : Icons.pending_actions,
                    color: completo ? Colors.green : Colors.orange, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fair.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(
                      completo
                          ? '${r.comMobiliario} stand(s) · tudo classificado'
                          : '${r.faltando} de ${r.comMobiliario} stand(s) '
                              'sem classificar',
                      style: TextStyle(
                          fontSize: 12,
                          color: completo
                              ? Colors.green.shade700
                              : Colors.orange.shade900,
                          fontWeight: FontWeight.w600),
                    ),
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

/// Stands com mobiliário de uma feira, com quem já foi classificado no fim.
class _FurnitureFairScreen extends StatefulWidget {
  final Fair fair;
  const _FurnitureFairScreen({required this.fair});

  @override
  State<_FurnitureFairScreen> createState() => _FurnitureFairScreenState();
}

class _FurnitureFairScreenState extends State<_FurnitureFairScreen> {
  static const _navy = Color(0xFF1E3A5F);

  List<Client> _clientes = [];
  Map<String, Map<String, String>> _classificados = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final todos = await DatabaseService.getClients(fairId: widget.fair.id!);
    Map<String, Map<String, String>> classif = {};
    try {
      classif =
          await FirestoreService.getFurnitureKindsForFair(widget.fair.name);
    } catch (_) {
      // Sem a classificação, a lista ainda serve para abrir os stands.
    }
    if (!mounted) return;
    setState(() {
      _clientes = todos
          .where((c) => c.mobilario.trim().isNotEmpty)
          .toList();
      _classificados = classif;
      _carregando = false;
      // Quem ainda falta primeiro: é a fila de trabalho da equipe.
      _clientes.sort((a, b) {
        final fa = _falta(a) ? 0 : 1;
        final fb = _falta(b) ? 0 : 1;
        return fa != fb ? fa - fb : a.nome.compareTo(b.nome);
      });
    });
  }

  bool _falta(Client c) {
    final itens = furnitureItemsFrom(c.mobilario);
    final feito = _classificados[c.firestoreId] ?? const {};
    return itens.any((i) => !feito.containsKey(i.key));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mobiliário',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Text(widget.fair.name,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _clientes.length,
              itemBuilder: (context, i) {
                final c = _clientes[i];
                final itens = furnitureItemsFrom(c.mobilario);
                final feito = _classificados[c.firestoreId] ?? const {};
                final faltam =
                    itens.where((it) => !feito.containsKey(it.key)).length;
                final internos = feito.values
                    .where((v) => v == 'interno')
                    .length;
                final externos = feito.values
                    .where((v) => v == 'externo')
                    .length;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: faltam == 0
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      child: Icon(
                          faltam == 0 ? Icons.check : Icons.pending_actions,
                          color: faltam == 0 ? Colors.green : Colors.orange,
                          size: 20),
                    ),
                    title: Text(c.nome,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(
                      [
                        if (c.local.isNotEmpty) 'Stand ${c.local}',
                        '${itens.length} item(ns)',
                        if (faltam > 0) '$faltam sem classificar',
                        if (faltam == 0)
                          '$internos interno(s) · $externos externo(s)',
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              faltam > 0 ? Colors.orange.shade900 : Colors.grey),
                    ),
                    trailing: const Icon(Icons.chevron_right,
                        color: Colors.grey, size: 20),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FurnitureClassifyScreen(
                            client: c,
                            fairName: widget.fair.name,
                          ),
                        ),
                      );
                      await _carregar();
                    },
                  ),
                );
              },
            ),
    );
  }
}
