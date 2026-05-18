import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/client.dart';
import '../models/pending_item.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'cas2026.db');
    return openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clients (
        row_id TEXT PRIMARY KEY,
        nome TEXT, montagem TEXT, local TEXT, hangar TEXT,
        area TEXT, deck TEXT, total_area TEXT, mezanino TEXT,
        produtor TEXT, marceneiro TEXT, tapeceiro TEXT,
        eletricista TEXT, faxineira TEXT, teto50 TEXT,
        is_completed INTEGER DEFAULT 0, completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id TEXT, client_name TEXT, local TEXT, hangar TEXT,
        team TEXT, responsible TEXT, description TEXT,
        is_resolved INTEGER DEFAULT 0, created_at TEXT, resolved_at TEXT,
        FOREIGN KEY (client_id) REFERENCES clients(row_id)
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    await db.execute('DROP TABLE IF EXISTS clients');
    await db.execute('DROP TABLE IF EXISTS pending_items');
    await _onCreate(db, newV);
  }

  static Future<void> upsertClients(List<Client> clients) async {
    final database = await db;
    final batch = database.batch();
    for (final c in clients) {
      batch.insert('clients', c.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> updateClientStatus(String rowId, bool completed) async {
    final database = await db;
    await database.update(
      'clients',
      {
        'is_completed': completed ? 1 : 0,
        'completed_at': completed ? DateTime.now().toIso8601String() : null,
      },
      where: 'row_id = ?',
      whereArgs: [rowId],
    );
  }

  static Future<List<Client>> getClients() async {
    final database = await db;
    final maps = await database.query('clients', orderBy: 'hangar, local');
    return maps.map(Client.fromMap).toList();
  }

  static Future<List<String>> getHangars() async {
    final database = await db;
    final result = await database.rawQuery(
        "SELECT DISTINCT hangar FROM clients WHERE hangar != '' ORDER BY hangar");
    final hangars = result.map((r) => r['hangar'] as String).toList();
    // Fallback: clientes que ficaram sem hangar mapeado aparecem como grupo próprio
    final orphans = Sqflite.firstIntValue(await database.rawQuery(
        "SELECT COUNT(*) FROM clients WHERE hangar = ''")) ?? 0;
    if (orphans > 0) hangars.add('Externos');
    return hangars;
  }

  static Future<List<PendingItem>> getPendingItemsByClient(
      String clientId) async {
    final database = await db;
    final maps = await database.query('pending_items',
        where: 'client_id = ?',
        whereArgs: [clientId],
        orderBy: 'created_at DESC');
    return maps.map(PendingItem.fromMap).toList();
  }

  static Future<List<String>> getProducers() async {
    final database = await db;
    final result = await database.rawQuery(
        "SELECT DISTINCT produtor FROM clients WHERE produtor != '' ORDER BY produtor");
    return result.map((r) => r['produtor'] as String).toList();
  }

  static Future<List<PendingItem>> getPendingItemsByProdutor(
      String produtor) async {
    final database = await db;
    final clients = await database.query('clients',
        columns: ['row_id'], where: 'produtor = ?', whereArgs: [produtor]);
    if (clients.isEmpty) return [];
    final ids = clients.map((c) => "'${c['row_id']}'").join(',');
    final maps = await database.rawQuery(
      'SELECT * FROM pending_items WHERE client_id IN ($ids) AND is_resolved = 0 '
      'ORDER BY hangar, local, created_at',
    );
    return maps.map(PendingItem.fromMap).toList();
  }

  static Future<int> insertPendingItem(PendingItem item) async {
    final database = await db;
    return database.insert('pending_items', item.toMap());
  }

  static Future<void> resolvePendingItem(int id) async {
    final database = await db;
    await database.update(
      'pending_items',
      {'is_resolved': 1, 'resolved_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<PendingItem>> getAllPendingItems({bool? resolved}) async {
    final database = await db;
    final maps = await database.query(
      'pending_items',
      where: resolved != null ? 'is_resolved = ?' : null,
      whereArgs: resolved != null ? [resolved ? 1 : 0] : null,
      orderBy: 'hangar, local, created_at',
    );
    return maps.map(PendingItem.fromMap).toList();
  }

  static Future<Map<String, int>> getStats() async {
    final database = await db;
    int q(dynamic v) => (v as int?) ?? 0;
    return {
      'total': q(Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM clients'))),
      'completed': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(*) FROM clients WHERE is_completed = 1'))),
      'with_pending': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(DISTINCT client_id) FROM pending_items WHERE is_resolved = 0'))),
      'total_pending': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(*) FROM pending_items WHERE is_resolved = 0'))),
      'resolved_pending': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(*) FROM pending_items WHERE is_resolved = 1'))),
    };
  }
}
