class Fair {
  final int? id;
  final String name;
  final String spreadsheetId;
  final String sheetName;
  final DateTime createdAt;

  const Fair({
    this.id,
    required this.name,
    required this.spreadsheetId,
    required this.sheetName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'spreadsheet_id': spreadsheetId,
    'sheet_name': sheetName,
    'created_at': createdAt.toIso8601String(),
  };

  factory Fair.fromMap(Map<String, dynamic> map) => Fair(
    id: map['id'] as int?,
    name: map['name'] as String,
    spreadsheetId: map['spreadsheet_id'] as String,
    sheetName: map['sheet_name'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
