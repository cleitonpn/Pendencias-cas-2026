class Client {
  final String rowId;
  final String nome;        // B - nome do cliente
  final String montagem;    // C - empresa de montagem (USET, D44...)
  final String local;       // D - código do stand (I74, I76, I02...)
  final String hangar;      // E - hangar (1, 3, 4, EXT 1, EXT 3...)
  final String area;        // F - m²
  final String deck;        // G - Deck
  final String totalArea;   // H - mt total
  final String mezanino;    // I - mezanino

  // Colunas O-T: responsáveis por equipe
  final String produtor;    // O - PRODUTOR
  final String marceneiro;  // P - marceneiro
  final String tapeceiro;   // Q - tapeceiro
  final String eletricista; // R - eletricista
  final String faxineira;   // S - faxineira
  final String teto50;      // T - teto 50

  bool isCompleted;
  DateTime? completedAt;

  Client({
    required this.rowId,
    required this.nome,
    required this.montagem,
    required this.local,
    required this.hangar,
    required this.area,
    required this.deck,
    required this.totalArea,
    required this.mezanino,
    required this.produtor,
    required this.marceneiro,
    required this.tapeceiro,
    required this.eletricista,
    required this.faxineira,
    required this.teto50,
    this.isCompleted = false,
    this.completedAt,
  });

  static String _s(List<dynamic> list, int index) {
    if (index < list.length) return list[index]?.toString().trim() ?? '';
    return '';
  }

  factory Client.fromSheetRow(
      List<dynamic> bToI, List<dynamic> oToT, int rowIndex) {
    return Client(
      rowId: rowIndex.toString(),
      nome: _s(bToI, 0),       // B
      montagem: _s(bToI, 1),   // C
      local: _s(bToI, 2),      // D
      hangar: _s(bToI, 3),     // E  ← hangar está na coluna E (índice 3)
      area: _s(bToI, 4),       // F
      deck: _s(bToI, 5),       // G
      totalArea: _s(bToI, 6),  // H
      mezanino: _s(bToI, 7),   // I
      produtor: _s(oToT, 0),   // O
      marceneiro: _s(oToT, 1), // P
      tapeceiro: _s(oToT, 2),  // Q
      eletricista: _s(oToT, 3),// R
      faxineira: _s(oToT, 4),  // S
      teto50: _s(oToT, 5),     // T
    );
  }

  Map<String, dynamic> toMap() => {
        'row_id': rowId,
        'nome': nome,
        'montagem': montagem,
        'local': local,
        'hangar': hangar,
        'area': area,
        'deck': deck,
        'total_area': totalArea,
        'mezanino': mezanino,
        'produtor': produtor,
        'marceneiro': marceneiro,
        'tapeceiro': tapeceiro,
        'eletricista': eletricista,
        'faxineira': faxineira,
        'teto50': teto50,
        'is_completed': isCompleted ? 1 : 0,
        'completed_at': completedAt?.toIso8601String(),
      };

  factory Client.fromMap(Map<String, dynamic> map) => Client(
        rowId: map['row_id'] as String,
        nome: map['nome'] ?? '',
        montagem: map['montagem'] ?? '',
        local: map['local'] ?? '',
        hangar: map['hangar'] ?? '',
        area: map['area'] ?? '',
        deck: map['deck'] ?? '',
        totalArea: map['total_area'] ?? '',
        mezanino: map['mezanino'] ?? '',
        produtor: map['produtor'] ?? '',
        marceneiro: map['marceneiro'] ?? '',
        tapeceiro: map['tapeceiro'] ?? '',
        eletricista: map['eletricista'] ?? '',
        faxineira: map['faxineira'] ?? '',
        teto50: map['teto50'] ?? '',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        completedAt: map['completed_at'] != null
            ? DateTime.tryParse(map['completed_at'] as String)
            : null,
      );

  String get displayName => nome.isNotEmpty ? nome : 'Stand $local';

  String get standLabel => local.isNotEmpty ? local : rowId;
}
