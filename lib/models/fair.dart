class Fair {
  final int? id;
  final String name;
  final String spreadsheetId;
  final String sheetName;
  final DateTime createdAt;
  // 'pre_producao' (sem notificações) | 'producao' (equipe monta, lembrete
  // diário ao produtor) | 'manutencao' (evento aberto ao expositor pelo QR)
  final String mode;
  // 'individual' | 'mestra' | 'mestra_child'
  final String sheetMode;
  final bool archived;

  const Fair({
    this.id,
    required this.name,
    required this.spreadsheetId,
    required this.sheetName,
    required this.createdAt,
    this.mode = 'producao',
    this.sheetMode = 'individual',
    this.archived = false,
  });

  bool get isMaintenance => mode == 'manutencao';
  bool get isProduction => mode == 'producao';
  bool get isPreProduction => mode == 'pre_producao';

  bool get isMestra => sheetMode == 'mestra';
  bool get isMestraChild => sheetMode == 'mestra_child';

  Fair copyWith({String? mode, String? sheetMode, bool? archived}) => Fair(
        id: id,
        name: name,
        spreadsheetId: spreadsheetId,
        sheetName: sheetName,
        createdAt: createdAt,
        mode: mode ?? this.mode,
        sheetMode: sheetMode ?? this.sheetMode,
        archived: archived ?? this.archived,
      );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'spreadsheet_id': spreadsheetId,
    'sheet_name': sheetName,
    'created_at': createdAt.toIso8601String(),
    'mode': mode,
    'sheet_mode': sheetMode,
    'archived': archived ? 1 : 0,
  };

  factory Fair.fromMap(Map<String, dynamic> map) => Fair(
    id: map['id'] as int?,
    name: map['name'] as String,
    spreadsheetId: map['spreadsheet_id'] as String,
    sheetName: map['sheet_name'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    mode: (map['mode'] as String?) ?? 'producao',
    sheetMode: ((map['sheet_mode'] as String?) ?? '').isNotEmpty
        ? map['sheet_mode'] as String
        : 'individual',
    archived: (map['archived'] as int? ?? 0) == 1,
  );
}
