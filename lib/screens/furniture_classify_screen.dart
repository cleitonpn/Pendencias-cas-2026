import 'package:flutter/material.dart';
import '../models/client.dart';
import '../services/actor.dart';
import '../services/firestore_service.dart';
import '../utils/furniture_items.dart';

/// Divide o mobiliário de um stand entre interno e externo.
///
/// A planilha diz QUAIS itens o stand tem. Quem decide o que sai do estoque e
/// o que é sublocado é a equipe de mobiliário, durante a operação — por isso
/// a classificação mora no app.
///
/// A tela mostra a quebra da coluna item por item, do jeito que o app
/// entendeu. Se a barra tiver sido digitada fora do padrão, a equipe vê aqui
/// e corrige na planilha, em vez de descobrir quando a OS sair errada.
class FurnitureClassifyScreen extends StatefulWidget {
  final Client client;
  final String fairName;

  const FurnitureClassifyScreen({
    super.key,
    required this.client,
    required this.fairName,
  });

  @override
  State<FurnitureClassifyScreen> createState() =>
      _FurnitureClassifyScreenState();
}

class _FurnitureClassifyScreenState extends State<FurnitureClassifyScreen> {
  static const _navy = Color(0xFF1E3A5F);
  static const _interno = Color(0xFF00796B);
  static const _externo = Color(0xFFE65100);

  late final List<FurnitureItem> _itens =
      furnitureItemsFrom(widget.client.mobilario);

  /// chave do item → 'interno' | 'externo'
  Map<String, String> _classificacao = {};
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final atual =
          await FirestoreService.getFurnitureKinds(widget.client.firestoreId);
      if (mounted) {
        setState(() {
          _classificacao = atual;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = 'Não foi possível carregar a classificação salva. '
              'Confira a conexão antes de classificar, para não gravar por '
              'cima do que já existe.';
        });
      }
    }
  }

  int get _faltam =>
      _itens.where((i) => !_classificacao.containsKey(i.key)).length;

  void _definir(FurnitureItem item, FurnitureKind kind) {
    setState(() => _classificacao[item.key] = kind.code);
  }

  void _todos(FurnitureKind kind) {
    setState(() {
      for (final i in _itens) {
        _classificacao[i.key] = kind.code;
      }
    });
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      // Só o que está na planilha hoje: item removido de lá some da
      // classificação em vez de ficar pendurado para sempre.
      final vivos = {for (final i in _itens) i.key};
      final limpo = {
        for (final e in _classificacao.entries)
          if (vivos.contains(e.key)) e.key: e.value
      };
      await FirestoreService.setFurnitureKinds(
        clientFirestoreId: widget.client.firestoreId,
        fairName: widget.fairName,
        items: limpo,
        by: Actor.name,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Mobiliário classificado.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Não foi possível salvar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
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
            Text(widget.client.nome,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _itens.isEmpty
              ? const _Vazio()
              : Column(
                  children: [
                    if (_erro != null)
                      Container(
                        width: double.infinity,
                        color: const Color(0xFFFFEBEE),
                        padding: const EdgeInsets.all(12),
                        child: Text(_erro!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red)),
                      ),
                    _cabecalho(),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: _itens.length,
                        itemBuilder: (context, i) => _linha(_itens[i]),
                      ),
                    ),
                    _rodape(),
                  ],
                ),
    );
  }

  Widget _cabecalho() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_itens.length} item(ns) na planilha'
              '${_faltam == 0 ? '' : ' · $_faltam sem classificar'}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _faltam == 0 ? Colors.green.shade700 : _externo),
            ),
            const SizedBox(height: 2),
            const Text(
              'Confira se a quebra bate com a planilha. Se um item veio '
              'partido ou grudado, corrija a coluna e sincronize.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(
                onPressed: () => _todos(FurnitureKind.interno),
                icon: const Icon(Icons.inventory_2_outlined, size: 16),
                label: const Text('Todos internos',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _interno),
              ),
              TextButton.icon(
                onPressed: () => _todos(FurnitureKind.externo),
                icon: const Icon(Icons.local_shipping_outlined, size: 16),
                label: const Text('Todos externos',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _externo),
              ),
            ]),
          ],
        ),
      );

  Widget _linha(FurnitureItem item) {
    final atual = furnitureKindFrom(_classificacao[item.key]);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.raw,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                if (atual == null)
                  const Icon(Icons.help_outline, size: 16, color: _externo),
              ],
            ),
            if (item.suspeito)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Confira este item na planilha',
                    style: TextStyle(fontSize: 10.5, color: _externo)),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _botao(item, FurnitureKind.interno, atual, _interno,
                    Icons.inventory_2_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _botao(item, FurnitureKind.externo, atual, _externo,
                    Icons.local_shipping_outlined),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _botao(FurnitureItem item, FurnitureKind kind, FurnitureKind? atual,
      Color cor, IconData icone) {
    final sel = atual == kind;
    return OutlinedButton.icon(
      onPressed: () => _definir(item, kind),
      icon: Icon(icone, size: 16, color: sel ? Colors.white : cor),
      label: Text(kind.label,
          style: TextStyle(fontSize: 12, color: sel ? Colors.white : cor)),
      style: OutlinedButton.styleFrom(
        backgroundColor: sel ? cor : null,
        side: BorderSide(color: cor),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  Widget _rodape() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              // Salvar parcial é permitido de propósito: numa feira grande a
              // classificação acontece aos poucos, e obrigar a terminar tudo
              // de uma vez faria a equipe perder o que já decidiu.
              label: Text(_salvando
                  ? 'Salvando…'
                  : _faltam == 0
                      ? 'Salvar classificação'
                      : 'Salvar ($_faltam ainda sem classificar)'),
              onPressed: _salvando ? null : _salvar,
            ),
          ),
        ),
      );
}

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chair_alt, size: 56, color: Colors.grey),
              SizedBox(height: 14),
              Text(
                'Este stand não tem mobiliário na planilha.\n\n'
                'A lista vem da coluna "mobiliário locado", com os itens '
                'separados por barra.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
}
