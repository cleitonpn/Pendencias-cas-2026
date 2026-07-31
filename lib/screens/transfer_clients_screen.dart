import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

/// Passa stands de um produtor para outro.
///
/// A planilha diz quem PODE ser dono de cada stand — mais de um nome na
/// coluna `produtor`, separados por vírgula. Quem É dono agora muda aqui,
/// quantas vezes for preciso, e volta atrás do mesmo jeito.
///
/// Foi assim que a gente resolveu dois produtores no mesmo stand sem duplicar
/// métrica: em vez de dividir a responsabilidade, ela passa de mão.
class TransferClientsScreen extends StatefulWidget {
  final String producerName;
  const TransferClientsScreen({super.key, required this.producerName});

  @override
  State<TransferClientsScreen> createState() => _TransferClientsScreenState();
}

class _TransferClientsScreenState extends State<TransferClientsScreen> {
  static const _navy = Color(0xFF1E3A5F);

  List<Client> _meus = [];
  final Set<String> _selecionados = {};
  String? _destino;
  bool _carregando = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final fair = context.read<AppProvider>().currentFair;
    if (fair?.id == null) {
      setState(() => _carregando = false);
      return;
    }
    final todos = await DatabaseService.getClients(fairId: fair!.id!);
    final eu = widget.producerName.toLowerCase().trim();
    if (!mounted) return;
    setState(() {
      // Só os stands que são meus AGORA e que têm para quem ir: um stand com
      // um nome só na planilha não tem destino possível.
      _meus = todos
          .where((c) =>
              c.produtor.toLowerCase().trim() == eu && c.produtores.length > 1)
          .toList()
        ..sort((a, b) => a.nome.compareTo(b.nome));
      _carregando = false;
    });
  }

  /// Para quem dá para transferir os stands escolhidos.
  ///
  /// Só entra quem está habilitado em TODOS eles — mandar um lote para alguém
  /// que não pode assumir metade deixaria o trabalho num limbo.
  List<String> get _destinosPossiveis {
    final escolhidos =
        _meus.where((c) => _selecionados.contains(c.firestoreId)).toList();
    if (escolhidos.isEmpty) return [];
    final eu = widget.producerName.toLowerCase().trim();

    Set<String> comuns = escolhidos.first.produtores
        .where((n) => n.toLowerCase().trim() != eu)
        .toSet();
    for (final c in escolhidos.skip(1)) {
      final outros = c.produtores
          .where((n) => n.toLowerCase().trim() != eu)
          .map((n) => n)
          .toSet();
      comuns = comuns.intersection(outros);
    }
    return comuns.toList()..sort();
  }

  Future<void> _transferir() async {
    final destino = _destino;
    if (destino == null || _selecionados.isEmpty) return;
    final fair = context.read<AppProvider>().currentFair;
    if (fair == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Transferir stands?'),
        content: Text(
          '${_selecionados.length} stand(s) passam para $destino.\n\n'
          'A partir de agora as pendências deles aparecem para $destino, que '
          'pode devolver a qualquer momento.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navy, foregroundColor: Colors.white),
            child: const Text('Transferir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _enviando = true);
    try {
      await FirestoreService.transferClients(
        clientFirestoreIds: _selecionados.toList(),
        toProducer: destino,
        fairName: fair.name,
        by: widget.producerName,
      );
      // Sem sincronizar, os stands transferidos continuariam aparecendo como
      // meus até o próximo sync — e a pessoa acharia que não funcionou.
      if (mounted) await context.read<AppProvider>().syncFromSheets();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text('Stands transferidos para $destino.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Não foi possível transferir: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinos = _destinosPossiveis;
    if (_destino != null && !destinos.contains(_destino)) _destino = null;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Transferir stands',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_meus.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (_selecionados.length == _meus.length) {
                  _selecionados.clear();
                } else {
                  _selecionados
                    ..clear()
                    ..addAll(_meus.map((c) => c.firestoreId));
                }
              }),
              child: Text(
                _selecionados.length == _meus.length ? 'Limpar' : 'Todos',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _meus.isEmpty
              ? const _Vazio()
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _meus.length,
                        itemBuilder: (context, i) {
                          final c = _meus[i];
                          final outros = c.produtores
                              .where((n) =>
                                  n.toLowerCase().trim() !=
                                  widget.producerName.toLowerCase().trim())
                              .join(', ');
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            child: CheckboxListTile(
                              value: _selecionados.contains(c.firestoreId),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selecionados.add(c.firestoreId);
                                } else {
                                  _selecionados.remove(c.firestoreId);
                                }
                              }),
                              title: Text(c.nome,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              subtitle: Text(
                                [
                                  if (c.local.isNotEmpty) 'Stand ${c.local}',
                                  if (c.hangar.isNotEmpty) c.hangar,
                                  'pode ir para: $outros',
                                ].join(' · '),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _rodape(destinos),
                  ],
                ),
    );
  }

  Widget _rodape(List<String> destinos) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_selecionados.length} selecionado(s)',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              if (_selecionados.isEmpty)
                const Text('Escolha os stands que quer passar adiante.',
                    style: TextStyle(fontSize: 12, color: Colors.grey))
              else if (destinos.isEmpty)
                const Text(
                  'Os stands escolhidos não têm nenhum produtor em comum '
                  'para receber. Selecione um grupo menor.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                )
              else
                DropdownButtonFormField<String>(
                  value: _destino,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Transferir para',
                    prefixIcon: Icon(Icons.swap_horiz),
                    isDense: true,
                  ),
                  items: destinos
                      .map((n) =>
                          DropdownMenuItem<String>(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) => setState(() => _destino = v),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.swap_horiz),
                  label: Text(_enviando ? 'Transferindo…' : 'Transferir'),
                  onPressed: (_enviando || _destino == null) ? null : _transferir,
                ),
              ),
            ],
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
              Icon(Icons.swap_horiz, size: 56, color: Colors.grey),
              SizedBox(height: 14),
              Text(
                'Nenhum stand para transferir.\n\n'
                'Só aparecem aqui os stands que são seus agora e que têm '
                'outro produtor habilitado na planilha — o segundo nome vai '
                'na coluna "produtor", separado por vírgula.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
}
