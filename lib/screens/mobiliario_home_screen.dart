import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/pdf_service.dart';
import '../services/session_service.dart';
import '../utils/furniture_items.dart';
import '../utils/client_key.dart';
import '../utils/stand_street.dart';
import '../widgets/app_drawer.dart';
import '../widgets/fair_info_header.dart';
import '../widgets/inbox_bell.dart';
import 'furniture_classify_screen.dart';
import 'furniture_pending_screen.dart';
import 'global_search_screen.dart';
import 'login_screen.dart';

/// A classificação que pertence a ESTE stand.
///
/// O documento mora sob o `firestoreId`, que é a posição na planilha. Depois
/// de uma linha inserida, o que está naquele id é a classificação do vizinho —
/// e contá-la mostraria o stand como pronto sem ninguém ter classificado, ou
/// mandaria para a OS a lista de outro. Documento que se identifica como de
/// outro vale como não existente.
Map<String, String> _classificacaoDe(
    Map<String, FurnitureKindsDoc> todos, Client c) {
  final doc = todos[c.firestoreId];
  if (doc == null) return const {};
  if (!documentoDoCliente(doc.identidade,
      clientKey: c.clientKey, nome: c.nome)) {
    return const {};
  }
  return doc.items;
}

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

  /// Chamados de mobiliário em aberto, somando todas as feiras. Null enquanto
  /// não deu para saber — diferente de zero, que quer dizer "conferido, não
  /// tem nada".
  int? _chamadosAbertos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final provider = context.read<AppProvider>();
    final resumo = <int, ({int comMobiliario, int faltando})>{};

    int? abertos;
    try {
      final chamados =
          await FirestoreService.getPendingItemsByTeam('Mobiliário');
      abertos = chamados.where((i) => !i.isPendingApproval).length;
    } catch (_) {
      // Fica sem número em vez de mostrar zero: "nenhum chamado" quando na
      // verdade a consulta falhou faria a equipe parar de olhar.
    }

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
          final jaFeito = _classificacaoDe(classificados, c);
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
        _chamadosAbertos = abertos;
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
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Os chamados vêm antes da classificação: classificar é
                  // trabalho de preparação, chamado é gente esperando no
                  // stand.
                  _cardChamados(),
                  const SizedBox(height: 16),
                  if (feiras.isEmpty)
                    _vazio(provider)
                  else
                    ...feiras.map(_cardFeira),
                ],
              ),
            ),
    );
  }

  Widget _vazio(AppProvider provider) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            // Vive dentro de uma ListView, onde a altura é infinita: sem o
            // min, o Column tenta ocupar tudo e o layout estoura.
            mainAxisSize: MainAxisSize.min,
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

  /// Porta de entrada para os chamados de mobiliário de todas as feiras.
  Widget _cardChamados() {
    final n = _chamadosAbertos;
    final tem = (n ?? 0) > 0;
    final cor = tem ? Colors.orange : Colors.green;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cor.shade200, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FurniturePendingScreen(name: widget.name),
            ),
          );
          await _carregar();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.build_circle_outlined, color: cor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Chamados de mobiliário',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  Text(
                    n == null
                        ? 'Não deu para conferir agora — toque para abrir'
                        : (tem
                            ? '$n em aberto'
                            : 'Nenhum chamado em aberto'),
                    style: TextStyle(
                        fontSize: 12,
                        color: n == null
                            ? Colors.grey
                            : (tem ? Colors.orange.shade900 : Colors.green.shade700),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

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
  static const _interno = Color(0xFF00796B);
  static const _externo = Color(0xFFE65100);

  List<Client> _clientes = [];
  List<Client> _todosClientes = [];
  Map<String, FurnitureKindsDoc> _classificados = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final todos = await DatabaseService.getClients(fairId: widget.fair.id!);
    Map<String, FurnitureKindsDoc> classif = {};
    try {
      classif =
          await FirestoreService.getFurnitureKindsForFair(widget.fair.name);
    } catch (_) {
      // Sem a classificação, a lista ainda serve para abrir os stands.
    }
    if (!mounted) return;
    setState(() {
      // O cabeçalho da feira lê datas e links do primeiro cliente. Passar só
      // os que têm mobiliário esconderia o cabeçalho inteiro quando esse
      // primeiro fosse justamente um sem as datas preenchidas.
      _todosClientes = todos;
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
    final feito = _classificacaoDe(_classificados, c);
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
          : Column(children: [
              // Datas, pavilhão, planta e Drive da feira. A equipe de
              // mobiliário programa a entrega por essas datas e precisa da
              // planta para saber onde fica cada rua — sem isso, tinha de
              // procurar em outra tela.
              FairInfoHeader(clients: _todosClientes, showDriveLink: true),
              _osDaFeira(),
              Expanded(child: _lista()),
            ]),
    );
  }

  /// OS de toda a feira, separada por rua.
  ///
  /// Fazer stand por stand numa feira de cem expositores é inviável — e o
  /// fornecedor não quer cem papéis, quer a folha da rua dele.
  Widget _osDaFeira() {
    final temInterno = _classificados.values
        .any((d) => d.items.containsValue('interno'));
    final temExterno = _classificados.values
        .any((d) => d.items.containsValue('externo'));
    if (!temInterno && !temExterno) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OS DA FEIRA — UMA FOLHA POR RUA',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Row(children: [
            if (temInterno)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _gerarOSDaFeira(FurnitureKind.interno),
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text('Interna', style: TextStyle(fontSize: 12)),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: _interno),
                ),
              ),
            if (temInterno && temExterno) const SizedBox(width: 8),
            if (temExterno)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _gerarOSDaFeira(FurnitureKind.externo),
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text('Externa', style: TextStyle(fontSize: 12)),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: _externo),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Future<void> _gerarOSDaFeira(FurnitureKind kind) async {
    // Só o que foi classificado como deste tipo. Item sem classificação fica
    // de fora: mandar para o fornecedor algo que ninguém conferiu é pior do
    // que a linha faltar e alguém perguntar.
    final porRua = <String, List<({Client client, List<FurnitureItem> itens})>>{};
    for (final c in _clientes) {
      final feito = _classificacaoDe(_classificados, c);
      final doTipo = furnitureItemsFrom(c.mobilario)
          .where((i) => furnitureKindFrom(feito[i.key]) == kind)
          .toList();
      if (doTipo.isEmpty) continue;
      porRua.putIfAbsent(ruaDe(c.local), () => []).add(
          (client: c, itens: doTipo));
    }
    if (porRua.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nenhum item ${kind.label.toLowerCase()} '
              'classificado nesta feira.')));
      return;
    }
    for (final lista in porRua.values) {
      lista.sort((a, b) => compararStands(a.client.local, b.client.local));
    }
    final ruas = porRua.keys.toList()..sort(compararRuas);

    final entrega = await _pedirDataEntrega();
    if (entrega == null || !mounted) return;

    await PdfService.generateAndShow(
      context,
      () => PdfService.generateFurnitureOrderByStreet(
        fairName: widget.fair.name,
        ruas: [
          for (final r in ruas) (rua: r, stands: porRua[r]!),
        ],
        kind: kind,
        entrega: entrega,
      ),
    );
  }

  Future<DateTime?> _pedirDataEntrega() {
    final hoje = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: hoje,
      firstDate: hoje.subtract(const Duration(days: 30)),
      lastDate: hoje.add(const Duration(days: 365)),
      helpText: 'Data de entrega',
    );
  }

  Widget _lista() {
    return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _clientes.length,
              itemBuilder: (context, i) {
                final c = _clientes[i];
                final itens = furnitureItemsFrom(c.mobilario);
                final feito = _classificacaoDe(_classificados, c);
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
            );
  }
}
