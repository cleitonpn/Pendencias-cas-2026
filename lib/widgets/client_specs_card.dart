import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

/// Displays stand specifications (filled by the consultant) in read-only mode.
/// Handles its own async loading. Shows nothing while loading or when empty.
class ClientSpecsCard extends StatefulWidget {
  final String clientId;
  const ClientSpecsCard({super.key, required this.clientId});

  @override
  State<ClientSpecsCard> createState() => _ClientSpecsCardState();
}

class _ClientSpecsCardState extends State<ClientSpecsCard> {
  Map<String, dynamic>? _specs;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final specs = await FirestoreService.getClientSpecs(widget.clientId);
    if (mounted) setState(() { _specs = specs; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _specs == null) return const SizedBox.shrink();

    final bagum = (_specs!['corBagum'] as String?) ?? '';
    final piso = (_specs!['corPiso'] as String?) ?? '';
    final pisoElevado = (_specs!['pisoElevado'] as bool?) ?? false;
    final elevacao = (_specs!['elevacao'] as String?) ?? '';

    if (bagum.isEmpty && piso.isEmpty && !pisoElevado) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('ESPECIFICAÇÕES DO STAND',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                  letterSpacing: 1)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bagum.isNotEmpty)
                    _SpecRow(label: 'Cor Bagum', value: bagum),
                  if (piso.isNotEmpty) ...[
                    if (bagum.isNotEmpty) const Divider(height: 16),
                    _SpecRow(label: 'Cor Piso', value: piso),
                  ],
                  const Divider(height: 16),
                  _SpecRow(
                    label: 'Piso Elevado',
                    value: pisoElevado ? 'Sim' : 'Não',
                    valueColor:
                        pisoElevado ? Colors.orange : Colors.grey,
                  ),
                  if (pisoElevado && elevacao.isNotEmpty) ...[
                    const Divider(height: 16),
                    _SpecRow(label: 'Elevação', value: elevacao),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SpecRow(
      {required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Colors.grey)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? Colors.black87)),
        ],
      );
}
