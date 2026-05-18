class Client {
  final String rowId;
  final String nome;
  final String stand;
  final String hangar;
  final String block;
  final String hangarLabel;
  final String montagem;
  final String respProdutos;
  final String respMontagem;
  final String respTapecaria;
  final String respEletrica;
  final String respLaminacao;
  final String respMK;
  bool isCompleted;
  DateTime? completedAt;

  Client({
    required this.rowId,
    required this.nome,
    required this.stand,
    required this.hangar,
    required this.block,
    required this.hangarLabel,
    required this.montagem,
    required this.respProdutos,
    required this.respMontagem,
    required this.respTapecaria,
    required this.respEletrica,
    required this.respLaminacao,
    required this.respMK,
    this.isCompleted = false,
    this.completedAt,
  });

  static String _safe(List<dynamic> list, int index) {
    if (index < list.length) return list[index]?.toString().trim() ?? '';
    return '';
  }

  factory Client.fromSheetRow(List<dynamic> bToI, List<dynamic> oToT, int rowIndex) {
    return Client(
      rowId: rowIndex.toString(),
      nome: _safe(bToI, 0),      // B - Montagem company/name
      stand: _safe(bToI, 1),     // C - Stand number
      hangar: _safe(bToI, 2),    // D - Hangar number
      block: _safe(bToI, 4),     // F - Block
      hangarLabel: _safe(bToI, 5), // G - HANGAR label
      montagem: _safe(bToI, 6),  // H - Montagem type
      respProdutos: _safe(oToT, 0),  // O
      respMontagem: _safe(oToT, 1),  // P
      respTapecaria: _safe(oToT, 2), // Q
      respEletrica: _safe(oToT, 3),  // R
      respLaminacao: _safe(oToT, 4), // S
      respMK: _safe(oToT, 5),        // T
    );
  }

  Map<String, dynamic> toMap() => {
        'row_id': rowId,
        'nome': nome,
        'stand': stand,
        'hangar': hangar,
        'block': block,
        'hangar_label': hangarLabel,
        'montagem': montagem,
        'resp_produtos': respProdutos,
        'resp_montagem': respMontagem,
        'resp_tapecaria': respTapecaria,
        'resp_eletrica': respEletrica,
        'resp_laminacao': respLaminacao,
        'resp_mk': respMK,
        'is_completed': isCompleted ? 1 : 0,
        'completed_at': completedAt?.toIso8601String(),
      };

  factory Client.fromMap(Map<String, dynamic> map) => Client(
        rowId: map['row_id'] as String,
        nome: map['nome'] ?? '',
        stand: map['stand'] ?? '',
        hangar: map['hangar'] ?? '',
        block: map['block'] ?? '',
        hangarLabel: map['hangar_label'] ?? '',
        montagem: map['montagem'] ?? '',
        respProdutos: map['resp_produtos'] ?? '',
        respMontagem: map['resp_montagem'] ?? '',
        respTapecaria: map['resp_tapecaria'] ?? '',
        respEletrica: map['resp_eletrica'] ?? '',
        respLaminacao: map['resp_laminacao'] ?? '',
        respMK: map['resp_mk'] ?? '',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        completedAt: map['completed_at'] != null
            ? DateTime.tryParse(map['completed_at'] as String)
            : null,
      );

  String get displayName =>
      nome.isNotEmpty ? nome : 'Stand $stand';
}
