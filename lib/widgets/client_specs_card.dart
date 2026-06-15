import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

/// Displays stand specifications (filled by the consultant) in read-only mode.
/// Handles its own async loading. Shows nothing while loading or when empty.
class ClientSpecsCard extends StatefulWidget {
  final String clientId;
  // Legacy rowId key used before stable firestoreId was introduced.
  // If set and clientId yields no data, this key is tried as fallback.
  final String? legacyClientId;
  const ClientSpecsCard({super.key, required this.clientId, this.legacyClientId});

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
    var specs = await FirestoreService.getClientSpecs(widget.clientId);
    if (specs == null && widget.legacyClientId != null &&
        widget.legacyClientId != widget.clientId) {
      specs = await FirestoreService.getClientSpecs(widget.legacyClientId!);
    }
    if (mounted) setState(() { _specs = specs; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _specs == null) return const SizedBox.shrink();
    final s = _specs!;

    final revestimento = (s['revestimento'] as String?) ?? '';
    final corRevestimento = (s['corRevestimento'] as String?) ?? '';
    final iluminacao = (s['iluminacao'] as String?) ?? '';
    final paredes = (s['paredes'] as String?) ?? '';
    final teto = (s['teto'] as String?) ?? '';
    final testeira = (s['testeira'] as String?) ?? '';
    final pisoElevado = (s['pisoElevado'] as bool?) ?? false;
    final alturaElevacao = (s['alturaElevacao'] as String?) ?? '';
    final tipoPiso = (s['tipoPiso'] as String?) ?? '';
    final corPiso = (s['corPiso'] as String?) ?? '';
    final anotacoes = (s['anotacoes'] as String?) ?? '';

    final hasAny = revestimento.isNotEmpty || corRevestimento.isNotEmpty ||
        iluminacao.isNotEmpty || paredes.isNotEmpty || teto.isNotEmpty ||
        testeira.isNotEmpty || pisoElevado || tipoPiso.isNotEmpty ||
        corPiso.isNotEmpty || anotacoes.isNotEmpty;

    if (!hasAny) return const SizedBox.shrink();

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balcões
              if (revestimento.isNotEmpty || corRevestimento.isNotEmpty) ...[
                _sectionLabel('BALCÕES'),
                _SpecCard(children: [
                  if (revestimento.isNotEmpty)
                    _SpecRow(label: 'Revestimento',
                        value: revestimento == 'napa' ? 'Napa' : 'Formica'),
                  if (revestimento.isNotEmpty && corRevestimento.isNotEmpty)
                    const Divider(height: 16),
                  if (corRevestimento.isNotEmpty)
                    _SpecRow(label: 'Cor do revestimento', value: corRevestimento),
                ]),
                const SizedBox(height: 10),
              ],
              // Iluminação
              if (iluminacao.isNotEmpty) ...[
                _sectionLabel('ILUMINAÇÃO'),
                _SpecCard(children: [
                  _SpecRow(label: 'Tipo',
                      value: iluminacao == 'branca' ? 'Branca' : 'Quente'),
                ]),
                const SizedBox(height: 10),
              ],
              // Cores
              if (paredes.isNotEmpty || teto.isNotEmpty || testeira.isNotEmpty) ...[
                _sectionLabel('CORES'),
                _SpecCard(children: [
                  if (paredes.isNotEmpty) _SpecRow(label: 'Paredes', value: paredes),
                  if (paredes.isNotEmpty && teto.isNotEmpty) const Divider(height: 16),
                  if (teto.isNotEmpty) _SpecRow(label: 'Teto', value: teto),
                  if ((paredes.isNotEmpty || teto.isNotEmpty) && testeira.isNotEmpty)
                    const Divider(height: 16),
                  if (testeira.isNotEmpty) _SpecRow(label: 'Testeira', value: testeira),
                ]),
                const SizedBox(height: 10),
              ],
              // Piso
              _sectionLabel('PISO'),
              _SpecCard(children: [
                _SpecRow(label: 'Piso elevado', value: pisoElevado ? 'Sim' : 'Não',
                    valueColor: pisoElevado ? Colors.orange : Colors.grey),
                if (pisoElevado && alturaElevacao.isNotEmpty) ...[
                  const Divider(height: 16),
                  _SpecRow(label: 'Altura da elevação', value: alturaElevacao),
                ],
                if (tipoPiso.isNotEmpty) ...[
                  const Divider(height: 16),
                  _SpecRow(label: 'Tipo do piso', value: tipoPiso),
                ],
                if (corPiso.isNotEmpty) ...[
                  const Divider(height: 16),
                  _SpecRow(label: 'Cor do piso', value: corPiso),
                ],
              ]),
              // Anotações
              if (anotacoes.isNotEmpty) ...[
                const SizedBox(height: 10),
                _sectionLabel('ANOTAÇÕES DIVERSAS'),
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(anotacoes,
                        style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
      );
}

class _SpecCard extends StatelessWidget {
  final List<Widget> children;
  const _SpecCard({required this.children});

  @override
  Widget build(BuildContext context) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SpecRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.black87)),
          ),
        ],
      );
}
