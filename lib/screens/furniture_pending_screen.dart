import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/pending_item.dart';
import '../services/firestore_service.dart';
import '../utils/furniture_items.dart';
import '../widgets/furniture_pick_chips.dart';
import '../widgets/pending_status.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/resolution_dialog.dart';

/// Os chamados de mobiliário, de todas as feiras.
///
/// A equipe de mobiliário não é de uma feira só — o estoque é um e a
/// sublocação também. Por isso a lista vem direto da nuvem por equipe, e não
/// do banco local, que só conhece a feira aberta.
///
/// Sem esta tela a etapa 3 ficava pela metade: o chamado chegava no celular
/// deles por notificação e não havia onde abrir.
class FurniturePendingScreen extends StatefulWidget {
  final String name;
  const FurniturePendingScreen({super.key, required this.name});

  @override
  State<FurniturePendingScreen> createState() => _FurniturePendingScreenState();
}

/// Como o chamado chega para esta equipe.
enum _Lado { todos, interno, externo }

class _FurniturePendingScreenState extends State<FurniturePendingScreen> {
  static const _navy = Color(0xFF1E3A5F);
  static const _interno = Color(0xFF00796B);
  static const _externo = Color(0xFFE65100);

  List<PendingItem> _itens = [];
  bool _carregando = true;
  String? _erro;
  _Lado _lado = _Lado.todos;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final itens =
          await FirestoreService.getPendingItemsByTeam('Mobiliário');
      if (!mounted) return;
      setState(() {
        // Pedido da organizadora ainda sem aprovação não é serviço liberado:
        // aparecer aqui mandaria a equipe atender algo que pode ser recusado.
        _itens = itens.where((i) => !i.isPendingApproval).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Erro visível: uma lista vazia por falha de rede seria lida como "não
      // tem serviço", e o serviço existe.
      setState(() {
        _erro = 'Não foi possível carregar os chamados. '
            'Verifique a conexão e tente de novo.';
        _carregando = false;
      });
    }
  }

  /// Um chamado conta como interno/externo pelo que foi marcado nele.
  /// Chamado sem item marcado fica só em "Todos" — não dá para adivinhar o
  /// lado, e chutar sujaria a contagem que a filtragem existe para dar.
  bool _doLado(PendingItem p, _Lado lado) {
    if (lado == _Lado.todos) return true;
    final alvo =
        lado == _Lado.interno ? FurnitureKind.interno : FurnitureKind.externo;
    return p.furnitureItems.any((f) => f.kind == alvo);
  }

  Future<void> _marcarFeita(PendingItem item) async {
    final id = item.firestoreId ?? '';
    if (id.isEmpty) return;
    final fairId = int.tryParse(item.clientId.split('_').first) ?? 1;
    final r = await showResolutionDialog(
      context,
      fairId: fairId,
      title: 'Marcar como atendido?',
      message: 'O chamado vai para validação da administração. '
          'Você pode registrar uma nota e fotos do que foi feito.',
      confirmLabel: 'Marcar como feita',
    );
    if (r == null || !mounted) return;
    try {
      if (r.note.isNotEmpty || r.photoUrls.isNotEmpty) {
        await FirestoreService.setResolutionNote(id,
            note: r.note, photoUrls: r.photoUrls);
      }
      await FirestoreService.markAwaitingValidation(id);
    } catch (_) {
      if (!mounted) return;
      _aviso('Não foi possível salvar. Tente de novo.', erro: true);
      return;
    }
    if (!mounted) return;
    _aviso('Marcado. Aguardando validação da administração.');
    await _carregar();
  }

  void _aviso(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? Colors.red : Colors.green,
    ));
  }

  void _copiar(PendingItem item) {
    Clipboard.setData(ClipboardData(text: item.toWhatsAppText()));
    _aviso('Texto copiado! Cole no WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    final lista = _itens.where((p) => _doLado(p, _lado)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chamados de mobiliário',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Text('${widget.name} · todas as feiras',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
          ),
        ],
      ),
      body: Column(
        children: [
          _filtros(),
          Expanded(child: _corpo(lista)),
        ],
      ),
    );
  }

  Widget _filtros() {
    Widget chip(_Lado l, String label, Color cor) {
      final n = _itens.where((p) => _doLado(p, l)).length;
      final sel = _lado == l;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: sel,
          onSelected: (_) => setState(() => _lado = l),
          selectedColor: cor.withOpacity(0.15),
          label: Text('$label ($n)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: sel ? cor : Colors.black87)),
          side: BorderSide(color: sel ? cor : Colors.grey.shade300),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip(_Lado.todos, 'Todos', _navy),
          chip(_Lado.interno, 'Interno', _interno),
          chip(_Lado.externo, 'Externo', _externo),
        ]),
      ),
    );
  }

  Widget _corpo(List<PendingItem> lista) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 44, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(_erro!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              _lado == _Lado.todos
                  ? 'Nenhum chamado de mobiliário em aberto.'
                  : 'Nenhum chamado deste lado em aberto.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: lista.length,
        itemBuilder: (context, i) => _cartao(lista[i]),
      ),
    );
  }

  Widget _cartao(PendingItem item) {
    final data = DateFormat('dd/MM HH:mm').format(item.createdAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(item.clientName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              PendingStatusBadge(item: item, fontSize: 11),
            ]),
            const SizedBox(height: 2),
            Text(
              [
                if (item.fairName.isNotEmpty) item.fairName,
                if (item.hangar.isNotEmpty) 'Hangar ${item.hangar}',
                if (item.local.isNotEmpty) 'Stand ${item.local}',
                data,
              ].join(' · '),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(item.description, style: const TextStyle(fontSize: 14)),
            FurniturePickChips(items: item.furnitureItems),
            if (item.furnitureItems.isEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Sem item marcado — confira com quem abriu o chamado.',
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.orange.shade900),
              ),
            ],
            if (item.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              PhotoStrip(urls: item.photoUrls),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copiar(item),
                  icon: const Icon(Icons.copy, size: 15),
                  label: const Text('WhatsApp',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: item.awaitingValidation
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.hourglass_bottom, size: 15),
                        label: const Text('Em validação',
                            style: TextStyle(fontSize: 12)),
                      )
                    : ElevatedButton.icon(
                        onPressed: () => _marcarFeita(item),
                        icon: const Icon(Icons.check, size: 15),
                        label: const Text('Marcar feita',
                            style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
