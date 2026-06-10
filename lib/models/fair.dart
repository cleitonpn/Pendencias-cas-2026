class Fair {
  final int? id;
  final String name;
  final String spreadsheetId;
  final String sheetName;
  final DateTime createdAt;
  // 'pre_producao' (sem notificações) | 'producao' (equipe monta, lembrete
  // diário ao produtor) | 'manutencao' (evento aberto ao expositor pelo QR)
  final String mode;

  const Fair({
    this.id,
    required this.name,
    required this.spreadsheetId,
    required this.sheetName,
    required this.createdAt,
    this.mode = 'producao',
  });

  bool get isMaintenance => mode == 'manutencao';
  bool get isProduction => mode == 'producao';
  bool get isPreProduction => mode == 'pre_producao';

  Fair copyWith({String? mode}) => Fair(
        id: id,
        name: name,
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
        createdAt: createdAt,
        mode: mode ?? this.mode,
      );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'spreadsheet_id': spreadsheetId,
    'sheet_name': sheetName,
    'created_at': createdAt.toIso8601String(),
    'mode': mode,
  };

  factory Fair.fromMap(Map<String, dynamic> map) => Fair(
    id: map['id'] as int?,
    name: map['name'] as String,
    spreadsheetId: map['spreadsheet_id'] as String,
    sheetName: map['sheet_name'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    mode: (map['mode'] as String?) ?? 'producao',
  );
}
