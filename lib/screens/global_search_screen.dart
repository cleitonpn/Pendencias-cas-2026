import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/session_service.dart';
import 'client_detail_screen.dart';
import 'producer_client_detail_screen.dart';
import 'consultant_client_detail_screen.dart';
import 'analyst_client_detail_screen.dart';

/// Busca um expositor em qualquer feira.
///
/// Antes, achar um stand exigia lembrar de qual feira ele era, entrar nela e
/// procurar no pavilhão certo. Em quem administra várias feiras ao mesmo
/// tempo, isso é a diferença entre responder na hora e responder depois.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const _navy = Color(0xFF1E3A5F);

  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  bool _buscou = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    // Sem a espera, cada tecla dispararia uma consulta e a lista piscaria.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _buscar(v));
  }

  Future<void> _buscar(String v) async {
    if (v.trim().length < 2) {
      setState(() {
        _resultados = [];
        _buscou = false;
      });
      return;
    }
    setState(() => _buscando = true);
    final r = await DatabaseService.searchClients(v);
    if (mounted) {
      setState(() {
        _resultados = r;
        _buscando = false;
        _buscou = true;
      });
    }
  }

  Future<void> _abrir(Map<String, dynamic> row) async {
    final client = Client.fromMap(row);
    final provider = context.read<AppProvider>();

    // A busca atravessa feiras: antes de abrir o stand, a feira dele precisa
    // ser a feira aberta, senão a tela de detalhe mostra o contexto errado.
    if (provider.currentFair?.id != client.fairId) {
      Fair? alvo;
      for (final f in provider.fairs) {
        if (f.id == client.fairId) alvo = f;
      }
      if (alvo != null) await provider.selectFair(alvo);
    }

    final s = await SessionService.get();
    final role = s?['role'] ?? 'admin';
    final name = s?['name'] ?? '';
    if (!mounted) return;

    final tela = switch (role) {
      'producer' =>
        ProducerClientDetailScreen(client: client, producerName: name),
      'consultant' =>
        ConsultantClientDetailScreen(client: client, consultantName: name),
      'analyst' =>
        AnalystClientDetailScreen(client: client, analystName: name),
      // Logística e mobiliário abrem a mesma ficha de leitura. As duas telas
      // já tinham o botão de busca, mas o resultado não abria nada: o toque
      // simplesmente não fazia efeito, sem aviso nenhum.
      'logistica' || 'mobiliario' => AnalystClientDetailScreen(
          client: client, analystName: name, podeAnotar: false),
      'admin' || 'manager' || 'leader' => ClientDetailScreen(client: client),
      _ => null,
    };
    if (tela == null) return;
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Buscar stand',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Nome do expositor, stand ou pavilhão…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          _buscar('');
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
              ),
            ),
          ),
          if (_buscando) const LinearProgressIndicator(),
          Expanded(child: _corpo()),
        ],
      ),
    );
  }

  Widget _corpo() {
    if (!_buscou) {
      return const _Aviso(
        icone: Icons.search,
        texto: 'Digite ao menos duas letras.\n\n'
            'A busca cobre todas as feiras já carregadas neste aparelho.',
      );
    }
    if (_resultados.isEmpty) {
      return const _Aviso(
        icone: Icons.search_off,
        texto: 'Nenhum stand encontrado.\n\n'
            'Se ele for de uma feira que este aparelho ainda não carregou, '
            'abra a feira uma vez e busque de novo.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _resultados.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = _resultados[i];
        final nome = (r['nome'] as String?) ?? '';
        final local = (r['local'] as String?) ?? '';
        final hangar = (r['hangar'] as String?) ?? '';
        final feira = (r['fair_name'] as String?) ?? '';
        final produtor = (r['produtor'] as String?) ?? '';

        return Card(
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8F0FB),
              child: Icon(Icons.storefront, color: _navy, size: 20),
            ),
            title: Text(nome,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (feira.isNotEmpty)
                  Text(feira,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _navy,
                          fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (local.isNotEmpty) 'Stand $local',
                    if (hangar.isNotEmpty) hangar,
                    if (produtor.isNotEmpty) produtor,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _abrir(r),
          ),
        );
      },
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final String texto;
  const _Aviso({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 56, color: Colors.grey),
              const SizedBox(height: 14),
              Text(texto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      );
}
