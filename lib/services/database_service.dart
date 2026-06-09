import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'cas2026.db');
    return openDatabase(path, version: 10, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE fairs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        spreadsheet_id TEXT NOT NULL,
        sheet_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        mode TEXT DEFAULT 'producao'
      )
    ''');
    await db.execute('''
      INSERT INTO fairs (id, name, spreadsheet_id, sheet_name, created_at)
      VALUES (1, 'CAS 2026', '1Q5jLjT7zQ2zIlf2udS3XIHHLc4o4Qjz9LvZOEIJ3XkE', 'projetos', '2026-01-01T00:00:00.000')
    ''');
    await db.execute('''
      CREATE TABLE clients (
        row_id TEXT PRIMARY KEY,
        fair_id INTEGER DEFAULT 1,
        nome TEXT, montagem TEXT, local TEXT, hangar TEXT,
        area TEXT, deck TEXT, total_area TEXT, mezanino TEXT,
        produtor TEXT, atendimento TEXT DEFAULT '', pin TEXT DEFAULT '', marceneiro TEXT, tapeceiro TEXT,
        eletricista TEXT, faxineira TEXT, teto50 TEXT,
        project_link TEXT DEFAULT '',
        link_cv TEXT DEFAULT '',
        mobilario TEXT DEFAULT '',
        is_completed INTEGER DEFAULT 0, completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fair_id INTEGER DEFAULT 1,
        firestore_id TEXT,
        producer_name TEXT DEFAULT '',
        client_id TEXT, client_name TEXT, local TEXT, hangar TEXT,
        team TEXT, responsible TEXT, description TEXT,
        photo_urls TEXT DEFAULT '',
        origem TEXT DEFAULT 'equipe',
        is_resolved INTEGER DEFAULT 0,
        awaiting_validation INTEGER DEFAULT 0,
        created_at TEXT, resolved_at TEXT,
        FOREIGN KEY (client_id) REFERENCES clients(row_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE producer_pins (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        producer_name TEXT UNIQUE NOT NULL,
        pin TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 3) {
      try {
        await db.execute('ALTER TABLE clients ADD COLUMN fair_id INTEGER DEFAULT 1');
      } catch (_) {}
      await db.execute(
          "UPDATE clients SET row_id = '1_' || row_id WHERE instr(row_id, '_') = 0");
      try {
        await db.execute('ALTER TABLE pending_items ADD COLUMN fair_id INTEGER DEFAULT 1');
      } catch (_) {}
      await db.execute(
          "UPDATE pending_items SET client_id = '1_' || client_id WHERE instr(client_id, '_') = 0");
      await db.execute('''
        CREATE TABLE IF NOT EXISTS fairs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          spreadsheet_id TEXT NOT NULL,
          sheet_name TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO fairs (id, name, spreadsheet_id, sheet_name, created_at)
        VALUES (1, 'CAS 2026', '1Q5jLjT7zQ2zIlf2udS3XIHHLc4o4Qjz9LvZOEIJ3XkE', 'projetos', '2026-01-01T00:00:00.000')
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS producer_pins (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          producer_name TEXT UNIQUE NOT NULL,
          pin TEXT NOT NULL
        )
      ''');
    }
    if (oldV < 4) {
      try {
        await db.execute('ALTER TABLE pending_items ADD COLUMN firestore_id TEXT');
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN producer_name TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 5) {
      try {
        await db.execute('ALTER TABLE pending_items ADD COLUMN awaiting_validation INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN project_link TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 6) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN mobilario TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 7) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN link_cv TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 8) {
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN photo_urls TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 9) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN atendimento TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 10) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN pin TEXT DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE fairs ADD COLUMN mode TEXT DEFAULT 'producao'");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN origem TEXT DEFAULT 'equipe'");
      } catch (_) {}
    }
  }

  // ─── Fairs ──────────────────────────────────────────────────────────────────

  static Future<List<Fair>> getFairs() async {
    final database = await db;
    final maps = await database.query('fairs', orderBy: 'id');
    return maps.map(Fair.fromMap).toList();
  }

  static Future<int> insertFair(Fair fair) async {
    final database = await db;
    return database.insert('fairs', fair.toMap());
  }

  /// Inserts a fair preserving its original ID (used when syncing from Firestore).
  static Future<void> upsertFairById(Fair fair) async {
    if (fair.id == null) return;
    final database = await db;
    await database.insert('fairs', fair.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> updateFairMode(int id, String mode) async {
    final database = await db;
    await database.update('fairs', {'mode': mode},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteFair(int id) async {
    final database = await db;
    final clients = await database.query('clients',
        columns: ['row_id'], where: 'fair_id = ?', whereArgs: [id]);
    if (clients.isNotEmpty) {
      final ids = clients.map((c) => "'${c['row_id']}'").join(',');
      await database.rawDelete('DELETE FROM pending_items WHERE client_id IN ($ids)');
    }
    await database.delete('clients', where: 'fair_id = ?', whereArgs: [id]);
    await database.delete('fairs', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Clients ────────────────────────────────────────────────────────────────

  static Future<void> upsertClients(List<Client> clients) async {
    if (clients.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final c in clients) {
      batch.insert('clients', c.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await _syncPendingResponsibles(database, clients.first.fairId);
  }

  static Future<void> _syncPendingResponsibles(
      Database database, int fairId) async {
    await database.rawUpdate('''
      UPDATE pending_items
      SET responsible = (
        SELECT CASE pending_items.team
          WHEN 'Elétrica'           THEN COALESCE(NULLIF(c.eletricista, ''), pending_items.responsible)
          WHEN 'Limpeza'            THEN COALESCE(NULLIF(c.faxineira,   ''), pending_items.responsible)
          WHEN 'Marcenaria'         THEN COALESCE(NULLIF(c.marceneiro,  ''), pending_items.responsible)
          WHEN 'Tapeçaria'          THEN COALESCE(NULLIF(c.tapeceiro,   ''), pending_items.responsible)
          WHEN 'Vidraceiro'         THEN 'Rodrigo'
          WHEN 'Comunicação Visual' THEN 'Vinícius'
          ELSE pending_items.responsible
        END
        FROM clients c WHERE c.row_id = pending_items.client_id
      )
      WHERE is_resolved = 0 AND fair_id = ?
    ''', [fairId]);
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

  static Future<List<Client>> getClients({required int fairId}) async {
    final database = await db;
    final maps = await database.query('clients',
        where: 'fair_id = ?', whereArgs: [fairId], orderBy: 'hangar, local');
    return maps.map(Client.fromMap).toList();
  }

  static Future<Map<String, int>> getPendingCounts(
      List<String> clientIds) async {
    if (clientIds.isEmpty) return {};
    final database = await db;
    final ids = clientIds.map((id) => "'$id'").join(',');
    final rows = await database.rawQuery(
      'SELECT client_id, COUNT(*) as cnt FROM pending_items '
      'WHERE client_id IN ($ids) AND is_resolved = 0 GROUP BY client_id',
    );
    return {for (final r in rows) r['client_id'] as String: r['cnt'] as int};
  }

  static Future<Map<String, int>> getPendingCountsByTeam(
      List<String> clientIds, String team) async {
    if (clientIds.isEmpty) return {};
    final database = await db;
    final ids = clientIds.map((id) => "'$id'").join(',');
    final rows = await database.rawQuery(
      'SELECT client_id, COUNT(*) as cnt FROM pending_items '
      'WHERE client_id IN ($ids) AND is_resolved = 0 AND team = ? GROUP BY client_id',
      [team],
    );
    return {for (final r in rows) r['client_id'] as String: r['cnt'] as int};
  }

  static Future<List<String>> getHangars({required int fairId}) async {
    final database = await db;
    final result = await database.rawQuery(
        "SELECT DISTINCT hangar FROM clients WHERE hangar != '' AND fair_id = ? ORDER BY hangar",
        [fairId]);
    final hangars = result.map((r) => r['hangar'] as String).toList();
    final orphans = Sqflite.firstIntValue(await database.rawQuery(
            "SELECT COUNT(*) FROM clients WHERE hangar = '' AND fair_id = ?",
            [fairId])) ??
        0;
    if (orphans > 0) {
      hangars.add(hangars.isEmpty ? 'Todos os Stands' : 'Externos');
    }
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

  static Future<List<String>> getProducers({required int fairId}) async {
    final database = await db;
    final result = await database.rawQuery(
        "SELECT DISTINCT produtor FROM clients WHERE produtor != '' AND fair_id = ? ORDER BY produtor",
        [fairId]);
    return result.map((r) => r['produtor'] as String).toList();
  }

  static Future<List<String>> getConsultants({required int fairId}) async {
    final database = await db;
    final result = await database.rawQuery(
        "SELECT DISTINCT atendimento FROM clients WHERE atendimento != '' AND fair_id = ? ORDER BY atendimento",
        [fairId]);
    return result.map((r) => r['atendimento'] as String).toList();
  }

  static Future<List<PendingItem>> getPendingItemsByProdutor(
      String produtor, {required int fairId}) async {
    final database = await db;
    final clients = await database.query('clients',
        columns: ['row_id'],
        where: 'produtor = ? AND fair_id = ?',
        whereArgs: [produtor, fairId]);
    if (clients.isEmpty) return [];
    final ids = clients.map((c) => "'${c['row_id']}'").join(',');
    final maps = await database.rawQuery(
      'SELECT * FROM pending_items WHERE client_id IN ($ids) AND is_resolved = 0 '
      'ORDER BY hangar, local, created_at',
    );
    return maps.map(PendingItem.fromMap).toList();
  }

  static Future<List<PendingItem>> getPendingItemsByTeam(
      String team, {required int fairId}) async {
    final database = await db;
    final maps = await database.query(
      'pending_items',
      where: 'team = ? AND fair_id = ? AND is_resolved = 0',
      whereArgs: [team, fairId],
      orderBy: 'hangar, local, created_at',
    );
    return maps.map(PendingItem.fromMap).toList();
  }

  /// Inserts or updates a pending item that came from Firestore.
  /// Uses firestore_id as the stable key to avoid duplicates.
  static Future<void> upsertPendingFromFirestore(PendingItem item) async {
    if (item.firestoreId == null) return;
    final database = await db;
    final existing = await database.query('pending_items',
        where: 'firestore_id = ?', whereArgs: [item.firestoreId], limit: 1);
    if (existing.isNotEmpty) {
      await database.update(
        'pending_items',
        {
          'is_resolved': item.isResolved ? 1 : 0,
          'awaiting_validation': item.awaitingValidation ? 1 : 0,
          'resolved_at': item.resolvedAt?.toIso8601String(),
        },
        where: 'firestore_id = ?',
        whereArgs: [item.firestoreId],
      );
    } else {
      final fairId = int.tryParse(item.clientId.split('_').first) ?? 1;
      await database.insert(
        'pending_items',
        {...item.toMap(), 'fair_id': fairId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<int> insertPendingItem(PendingItem item) async {
    final database = await db;
    final fairId = int.tryParse(item.clientId.split('_').first) ?? 1;
    return database.insert(
        'pending_items', {...item.toMap(), 'fair_id': fairId});
  }

  static Future<void> updatePendingFirestoreId(
      int sqliteId, String firestoreId) async {
    final database = await db;
    await database.update(
      'pending_items',
      {'firestore_id': firestoreId},
      where: 'id = ?',
      whereArgs: [sqliteId],
    );
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

  static Future<void> markItemAwaitingValidation(int id) async {
    final database = await db;
    await database.update(
      'pending_items',
      {'awaiting_validation': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> resolvePendingItemByFirestoreId(String firestoreId) async {
    final database = await db;
    await database.update(
      'pending_items',
      {'is_resolved': 1, 'resolved_at': DateTime.now().toIso8601String()},
      where: 'firestore_id = ?',
      whereArgs: [firestoreId],
    );
  }

  static Future<List<PendingItem>> getAllPendingItems(
      {bool? resolved, required int fairId}) async {
    final database = await db;
    String where = 'fair_id = ?';
    final args = <Object?>[fairId];
    if (resolved != null) {
      where += ' AND is_resolved = ?';
      args.add(resolved ? 1 : 0);
    }
    final maps = await database.query(
      'pending_items',
      where: where,
      whereArgs: args,
      orderBy: 'hangar, local, created_at',
    );
    return maps.map(PendingItem.fromMap).toList();
  }

  static Future<Map<String, int>> getStats({required int fairId}) async {
    final database = await db;
    int q(dynamic v) => (v as int?) ?? 0;
    return {
      'total': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(*) FROM clients WHERE fair_id = ?', [fairId]))),
      'completed': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(*) FROM clients WHERE is_completed = 1 AND fair_id = ?',
          [fairId]))),
      'with_pending': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(DISTINCT client_id) FROM pending_items WHERE is_resolved = 0 AND fair_id = ?',
          [fairId]))),
      'total_pending': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(*) FROM pending_items WHERE is_resolved = 0 AND fair_id = ?',
          [fairId]))),
      'resolved_pending': q(Sqflite.firstIntValue(await database.rawQuery(
          'SELECT COUNT(*) FROM pending_items WHERE is_resolved = 1 AND fair_id = ?',
          [fairId]))),
    };
  }

  static Future<List<Map<String, dynamic>>> getTeamRankings(
      {required int fairId}) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT team,
        COUNT(*) as total,
        SUM(CASE WHEN is_resolved = 0 THEN 1 ELSE 0 END) as open,
        SUM(CASE WHEN is_resolved = 1 THEN 1 ELSE 0 END) as resolved
      FROM pending_items
      WHERE fair_id = ?
      GROUP BY team
      ORDER BY total DESC
    ''', [fairId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<List<Map<String, dynamic>>> getProducerRankings(
      {required int fairId}) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT c.produtor as producer,
        COUNT(*) as total,
        SUM(CASE WHEN p.is_resolved = 0 THEN 1 ELSE 0 END) as open,
        SUM(CASE WHEN p.is_resolved = 1 THEN 1 ELSE 0 END) as resolved
      FROM pending_items p
      JOIN clients c ON c.row_id = p.client_id
      WHERE c.produtor != '' AND p.fair_id = ?
      GROUP BY c.produtor
      ORDER BY total DESC
    ''', [fairId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
