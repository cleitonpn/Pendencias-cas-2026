class Client {
  final int fairId;          // which fair this client belongs to
  final String rowId;
  final String nome;
  final String montagem;
  final String local;
  final String hangar;
  final String area;
  final String deck;
  final String totalArea;
  final String mezanino;

  final String produtor;
  final String atendimento;  // consultor responsável pelo cliente
  final String marceneiro;
  final String tapeceiro;
  final String eletricista;
  final String faxineira;
  final String teto50;
  final String projectLink;
  final String linkCv;
  final String mobilario;

  bool isCompleted;
  DateTime? completedAt;

  Client({
    this.fairId = 1,
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
    this.atendimento = '',
    required this.marceneiro,
    required this.tapeceiro,
    required this.eletricista,
    required this.faxineira,
    required this.teto50,
    this.projectLink = '',
    this.linkCv = '',
    this.mobilario = '',
    this.isCompleted = false,
    this.completedAt,
  });

  static String _s(List<dynamic> list, int index) {
    if (index < list.length) return list[index]?.toString().trim() ?? '';
    return '';
  }

  factory Client.fromSheetRow(
      List<dynamic> bToI, List<dynamic> oToT, int rowIndex, {int fairId = 1}) {
    return Client(
      fairId: fairId,
      rowId: '${fairId}_$rowIndex',
      nome: _s(bToI, 0),
      montagem: _s(bToI, 1),
      local: _s(bToI, 2),
      hangar: _s(bToI, 3),
      area: _s(bToI, 4),
      deck: _s(bToI, 5),
      totalArea: _s(bToI, 6),
      mezanino: _s(bToI, 7),
      produtor: _s(oToT, 0),
      marceneiro: _s(oToT, 1),
      tapeceiro: _s(oToT, 2),
      eletricista: _s(oToT, 3),
      faxineira: _s(oToT, 4),
      teto50: _s(oToT, 5),
    );
  }

  Map<String, dynamic> toMap() => {
        'fair_id': fairId,
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
        'atendimento': atendimento,
        'marceneiro': marceneiro,
        'tapeceiro': tapeceiro,
        'eletricista': eletricista,
        'faxineira': faxineira,
        'teto50': teto50,
        'project_link': projectLink,
        'link_cv': linkCv,
        'mobilario': mobilario,
        'is_completed': isCompleted ? 1 : 0,
        'completed_at': completedAt?.toIso8601String(),
      };

  factory Client.fromMap(Map<String, dynamic> map) => Client(
        fairId: map['fair_id'] as int? ?? 1,
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
        atendimento: map['atendimento'] ?? '',
        marceneiro: map['marceneiro'] ?? '',
        tapeceiro: map['tapeceiro'] ?? '',
        eletricista: map['eletricista'] ?? '',
        faxineira: map['faxineira'] ?? '',
        teto50: map['teto50'] ?? '',
        projectLink: map['project_link'] ?? '',
        linkCv: map['link_cv'] ?? '',
        mobilario: map['mobilario'] ?? '',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        completedAt: map['completed_at'] != null
            ? DateTime.tryParse(map['completed_at'] as String)
            : null,
      );

  String get displayName => nome.isNotEmpty ? nome : 'Stand $local';

  String get standLabel => local.isNotEmpty ? local : rowId;
}
