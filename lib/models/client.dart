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
  final String organizadora; // organizadora do evento (faz o link com o cliente)
  final String pin;          // PIN de acesso do stand (adesivo), lido da planilha
  final String marceneiro;
  final String tapeceiro;
  final String eletricista;
  final String faxineira;
  final String teto50;
  final String projectLink;
  final String linkCv;
  final String mobilario;

  // Event-level info columns (same for all clients in a fair)
  final String pavilhao;
  final String dataMontagem;
  final String dataEvento;
  final String dataDesmontagem;
  final String linkPlanta;

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
    this.organizadora = '',
    this.pin = '',
    required this.marceneiro,
    required this.tapeceiro,
    required this.eletricista,
    required this.faxineira,
    required this.teto50,
    this.projectLink = '',
    this.linkCv = '',
    this.mobilario = '',
    this.pavilhao = '',
    this.dataMontagem = '',
    this.dataEvento = '',
    this.dataDesmontagem = '',
    this.linkPlanta = '',
    this.isCompleted = false,
    this.completedAt,
  });

  /// Returns a new Client with updated fairId and rowId (used when assigning
  /// derived fair IDs after reading from a master sheet).
  Client reidentify(int newFairId, String newRowId) => Client(
        fairId: newFairId,
        rowId: newRowId,
        nome: nome,
        montagem: montagem,
        local: local,
        hangar: hangar,
        area: area,
        deck: deck,
        totalArea: totalArea,
        mezanino: mezanino,
        produtor: produtor,
        atendimento: atendimento,
        organizadora: organizadora,
        pin: pin,
        marceneiro: marceneiro,
        tapeceiro: tapeceiro,
        eletricista: eletricista,
        faxineira: faxineira,
        teto50: teto50,
        projectLink: projectLink,
        linkCv: linkCv,
        mobilario: mobilario,
        pavilhao: pavilhao,
        dataMontagem: dataMontagem,
        dataEvento: dataEvento,
        dataDesmontagem: dataDesmontagem,
        linkPlanta: linkPlanta,
        isCompleted: isCompleted,
        completedAt: completedAt,
      );

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
        'organizadora': organizadora,
        'pin': pin,
        'marceneiro': marceneiro,
        'tapeceiro': tapeceiro,
        'eletricista': eletricista,
        'faxineira': faxineira,
        'teto50': teto50,
        'project_link': projectLink,
        'link_cv': linkCv,
        'mobilario': mobilario,
        'pavilhao': pavilhao,
        'data_montagem': dataMontagem,
        'data_evento': dataEvento,
        'data_desmontagem': dataDesmontagem,
        'link_planta': linkPlanta,
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
        organizadora: map['organizadora'] ?? '',
        pin: map['pin'] ?? '',
        marceneiro: map['marceneiro'] ?? '',
        tapeceiro: map['tapeceiro'] ?? '',
        eletricista: map['eletricista'] ?? '',
        faxineira: map['faxineira'] ?? '',
        teto50: map['teto50'] ?? '',
        projectLink: map['project_link'] ?? '',
        linkCv: map['link_cv'] ?? '',
        mobilario: map['mobilario'] ?? '',
        pavilhao: map['pavilhao'] ?? '',
        dataMontagem: map['data_montagem'] ?? '',
        dataEvento: map['data_evento'] ?? '',
        dataDesmontagem: map['data_desmontagem'] ?? '',
        linkPlanta: map['link_planta'] ?? '',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        completedAt: map['completed_at'] != null
            ? DateTime.tryParse(map['completed_at'] as String)
            : null,
      );

  String get displayName => nome.isNotEmpty ? nome : 'Stand $local';

  String get standLabel => local.isNotEmpty ? local : rowId;
}
