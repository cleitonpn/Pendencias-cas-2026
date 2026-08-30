import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client.dart';
import '../services/actor.dart';
import '../services/firestore_service.dart';
import '../services/pdf_service.dart';
import '../utils/furniture_items.dart';
import '../utils/stand_street.dart';
import '../widgets/analyst_notes_widget.dart';
import '../widgets/client_specs_card.dart';

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
  static const _descartado = Color(0xFF757575);

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
          await FirestoreService.getFurnitureKinds(
              widget.client.firestoreId,
              clientKey: widget.client.clientKey,
              nome: widget.client.nome);
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
        clientKey: widget.client.clientKey,
        nome: widget.client.nome,
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
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 12),
                        children: [
                          // As informações do stand vêm antes da lista: quem
                          // classifica precisa saber onde é, quem responde e o
                          // que o consultor combinou — senão a decisão de
                          // interno x externo é feita no escuro.
                          _infoCliente(),
                          _cabecalho(),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(children: _itens.map(_linha).toList()),
                          ),
                        ],
                      ),
                    ),
                    _botoesOS(),
                    _rodape(),
                  ],
                ),
    );
  }

  /// Onde é, quem responde e o que já foi combinado sobre este stand.
  ///
  /// A equipe de mobiliário chega no stand sem ter acompanhado o projeto. Sem
  /// isto, descobrir quem é o produtor ou ler a consideração do consultor
  /// exigia sair do app e perguntar no grupo.
  Widget _infoCliente() {
    final c = widget.client;
    final rua = ruaDe(c.local);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // ClientSpecsCard e AnalystNotesWidget trazem o próprio recuo de
            // 16; só o que é desta tela precisa do recuo aqui.
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A localização em destaque: é o dado que a pessoa usa primeiro, ao
                // sair para o pavilhão.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBD0EC)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.place_outlined, color: _navy, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // O nome do cliente vem primeiro: num stand ainda
                          // sem localização na planilha, o destaque era um
                          // "Sem stand" que não dizia de quem era a ficha.
                          Text(
                            c.nome,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _navy),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (c.hangar.isNotEmpty) 'Hangar ${c.hangar}',
                              if (c.local.isNotEmpty)
                                'Stand ${c.local}'
                              else
                                'Sem stand',
                            ].join('  ·  '),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _navy),
                          ),
                          Text(
                            [
                              if (rua != semRua) 'Rua $rua' else semRua,
                              if (c.area.isNotEmpty) '${c.area} m²',
                              if (c.tipo.isNotEmpty) c.tipo,
                            ].join('  ·  '),
                            style: const TextStyle(fontSize: 12, color: _navy),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                _campo(Icons.engineering_outlined, 'Produtor',
                    c.produtores.isEmpty ? c.produtor : c.produtores.join(', ')),
                _campo(Icons.support_agent_outlined, 'Consultor', c.atendimento),
                _campo(Icons.apartment_outlined, 'Organizadora', c.organizadora),
                if (c.projectLink.isNotEmpty)
                  _link(Icons.link, 'Ver projeto', c.projectLink, Colors.blue),
                if (c.linkMemorial.isNotEmpty)
                  _link(Icons.description_outlined, 'Ver memorial descritivo',
                      c.linkMemorial, Colors.teal),
              ],
            ),
          ),
          // Especificações do stand: é aqui que ficam as considerações que o
          // consultor deixou, e elas costumam mudar o que a equipe leva.
          ClientSpecsCard(
              clientId: c.firestoreId,
              legacyClientId: c.rowId,
              clientKey: c.clientKey,
              clientName: c.nome),
          // A equipe de mobiliário também anota: o que faltou, o que foi
          // trocado no lugar. Sem poder escrever, essa informação ficava no
          // WhatsApp e sumia.
          AnalystNotesWidget(
            clientId: c.firestoreId,
            clientKey: c.clientKey,
            clientName: c.nome,
            canEdit: true,
            editorName: Actor.name,
          ),
        ],
      ),
    );
  }

  Widget _campo(IconData icone, String rotulo, String valor) {
    if (valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text('$rotulo: ',
            style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(valor,
              style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
        ),
      ]),
    );
  }

  Widget _link(IconData icone, String rotulo, String url, MaterialColor cor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Não foi possível abrir o link.')),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cor.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cor.shade200),
          ),
          child: Row(children: [
            Icon(icone, color: cor.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(rotulo,
                  style: TextStyle(
                      color: cor.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
            Icon(Icons.open_in_new, color: cor.shade400, size: 15),
          ]),
        ),
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
            const SizedBox(height: 6),
            // Saída para o que a coluna recebeu mas não é item: observação,
            // texto solto, linha que sobrou. Sai da fila sem virar OS.
            SizedBox(
              width: double.infinity,
              child: _botao(item, FurnitureKind.naoMobiliario, atual,
                  _descartado, Icons.block),
            ),
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

  /// Pergunta a data de entrega antes de gerar. É preenchida por quem emite a
  /// OS, não vem da planilha — depende do combinado com o fornecedor.
  Future<DateTime?> _pedirDataEntrega() async {
    final hoje = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: hoje,
      firstDate: hoje.subtract(const Duration(days: 30)),
      lastDate: hoje.add(const Duration(days: 365)),
      helpText: 'Data de entrega',
    );
  }

  Future<void> _gerarOS(FurnitureKind kind) async {
    final doTipo = _itens
        .where((i) => furnitureKindFrom(_classificacao[i.key]) == kind)
        .toList();
    if (doTipo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nenhum item ${kind.label.toLowerCase()} '
            'classificado neste stand.')),
      );
      return;
    }
    final entrega = await _pedirDataEntrega();
    if (entrega == null || !mounted) return;

    await PdfService.generateAndShow(
      context,
      () => PdfService.generateFurnitureOrder(
        fairName: widget.fairName,
        client: widget.client,
        itens: doTipo,
        kind: kind,
        entrega: entrega,
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

  /// Só aparece depois que há o que imprimir. Um botão de OS num stand sem
  /// classificação geraria papel em branco.
  Widget _botoesOS() {
    final temInterno = _classificacao.containsValue('interno');
    final temExterno = _classificacao.containsValue('externo');
    if (!temInterno && !temExterno) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(children: [
        if (temInterno)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _gerarOS(FurnitureKind.interno),
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text('OS interna', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: _interno),
            ),
          ),
        if (temInterno && temExterno) const SizedBox(width: 8),
        if (temExterno)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _gerarOS(FurnitureKind.externo),
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text('OS externa', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: _externo),
            ),
          ),
      ]),
    );
  }
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
