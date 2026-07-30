import 'dart:convert';
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
    final database = await openDatabase(path,
        version: 23, onCreate: _onCreate, onUpgrade: _onUpgrade);
    await _ensureSchema(database);
    return database;
  }

  /// Colunas que precisam existir. Os ALTER TABLE das migrações ficam dentro
  /// de try/catch: se um falha, a falha passa despercebida e, a partir daí,
  /// todo insert/update naquela tabela lança — derrubando a sincronização.
  /// Esta checagem roda em toda abertura e repõe o que faltar, inclusive em
  /// aparelhos que já ficaram nesse estado.
  static const _requiredColumns = <String, Map<String, String>>{
    'pending_items': {
      'consultant_name': "TEXT DEFAULT ''",
      'approval_note': "TEXT DEFAULT ''",
      'resolution_note': "TEXT DEFAULT ''",
      'resolution_photos': "TEXT DEFAULT ''",
      'approval_status': "TEXT DEFAULT 'none'",
      'rejection_reason': "TEXT DEFAULT ''",
      'awaiting_validation': 'INTEGER DEFAULT 0',
      'in_progress': 'INTEGER DEFAULT 0',
      'in_progress_by': "TEXT DEFAULT ''",
    },
    'fairs': {
      'auto_approve': 'INTEGER DEFAULT 0',
      'archived': 'INTEGER DEFAULT 0',
    },
  };

  static Future<void> _ensureSchema(Database database) async {
    for (final table in _requiredColumns.entries) {
      try {
        final info =
            await database.rawQuery('PRAGMA table_info(${table.key})');
        final existing =
            info.map((r) => (r['name'] as String?) ?? '').toSet();
        for (final col in table.value.entries) {
          if (existing.contains(col.key)) continue;
          try {
            await database.execute('ALTER TABLE ${table.key} '
                'ADD COLUMN ${col.key} ${col.value}');
          } catch (_) {}
        }
      } catch (_) {
        // Tabela ainda não criada — _onCreate cuida.
      }
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE fairs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        spreadsheet_id TEXT NOT NULL,
        sheet_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        mode TEXT DEFAULT 'producao',
        sheet_mode TEXT DEFAULT 'individual',
        archived INTEGER DEFAULT 0,
        auto_approve INTEGER DEFAULT 0
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
        firestore_id TEXT DEFAULT '',
        nome TEXT, montagem TEXT, local TEXT, hangar TEXT,
        area TEXT, deck TEXT, total_area TEXT, mezanino TEXT,
        produtor TEXT, atendimento TEXT DEFAULT '', organizadora TEXT DEFAULT '', pin TEXT DEFAULT '', marceneiro TEXT, tapeceiro TEXT,
        eletricista TEXT, faxineira TEXT, teto50 TEXT,
        project_link TEXT DEFAULT '',
        link_cv TEXT DEFAULT '',
        link_memorial TEXT DEFAULT '',
        mobilario TEXT DEFAULT '',
        extras TEXT DEFAULT '',
        pavilhao TEXT DEFAULT '',
        data_montagem TEXT DEFAULT '',
        data_evento TEXT DEFAULT '',
        data_desmontagem TEXT DEFAULT '',
        link_planta TEXT DEFAULT '',
        link_drive TEXT DEFAULT '',
        is_completed INTEGER DEFAULT 0, completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fair_id INTEGER DEFAULT 1,
        firestore_id TEXT,
        producer_name TEXT DEFAULT '',
        consultant_name TEXT DEFAULT '',
        client_id TEXT, client_name TEXT, local TEXT, hangar TEXT,
        team TEXT, responsible TEXT, description TEXT,
        photo_urls TEXT DEFAULT '',
        origem TEXT DEFAULT 'equipe',
        created_by TEXT DEFAULT '',
        resolved_by TEXT DEFAULT '',
        approval_status TEXT DEFAULT 'none',
        rejection_reason TEXT DEFAULT '',
        approval_note TEXT DEFAULT '',
        resolution_note TEXT DEFAULT '',
        resolution_photos TEXT DEFAULT '',
        is_resolved INTEGER DEFAULT 0,
        awaiting_validation INTEGER DEFAULT 0,
        in_progress INTEGER DEFAULT 0,
        in_progress_by TEXT DEFAULT '',
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
    if (oldV < 11) {
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN created_by TEXT DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN resolved_by TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 12) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN organizadora TEXT DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN approval_status TEXT DEFAULT 'none'");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN rejection_reason TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 13) {
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN in_progress INTEGER DEFAULT 0");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE pending_items ADD COLUMN in_progress_by TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 14) {
      try {
        await db.execute("ALTER TABLE fairs ADD COLUMN sheet_mode TEXT DEFAULT 'individual'");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN pavilhao TEXT DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN data_montagem TEXT DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN data_evento TEXT DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN data_desmontagem TEXT DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN link_planta TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 15) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN link_memorial TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 16) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN link_drive TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 17) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN firestore_id TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 18) {
      try {
        await db.execute("ALTER TABLE fairs ADD COLUMN archived INTEGER DEFAULT 0");
      } catch (_) {}
    }
    if (oldV < 19) {
      try {
        await db.execute("ALTER TABLE clients ADD COLUMN extras TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 20) {
      // Fix pending items that were incorrectly stored with firestoreId as
      // client_id. All SQLite queries use row_id, so we normalise client_id
      // back to row_id and update fair_id accordingly.
      try {
        await db.rawUpdate('''
          UPDATE pending_items
          SET
            client_id = (
              SELECT c.row_id FROM clients c
              WHERE c.firestore_id = pending_items.client_id
                AND c.firestore_id != ''
              LIMIT 1
            ),
            fair_id = COALESCE((
              SELECT c.fair_id FROM clients c
              WHERE c.firestore_id = pending_items.client_id
                AND c.firestore_id != ''
              LIMIT 1
            ), fair_id)
          WHERE EXISTS (
            SELECT 1 FROM clients c
            WHERE c.firestore_id = pending_items.client_id
              AND c.firestore_id != ''
          )
        ''');
      } catch (_) {}
    }
    if (oldV < 23) {
      // Consultor do cliente, para notificar só quem está atrelado a ele.
      try {
        await db.execute(
            "ALTER TABLE pending_items ADD COLUMN consultant_name TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldV < 22) {
      // Aprovação automática por feira.
      try {
        await db.execute(
            'ALTER TABLE fairs ADD COLUMN auto_approve INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldV < 21) {
      // Notas da montadora: aprovação, conclusão (manutenção) e fotos do
      // serviço realizado.
      for (final col in const [
        'approval_note',
        'resolution_note',
        'resolution_photos'
      ]) {
        try {
          await db.execute(
              "ALTER TABLE pending_items ADD COLUMN $col TEXT DEFAULT ''");
        } catch (_) {}
      }
    }
  }

  /// SQL fragment: items hidden from producer/leader because they are organizer
  /// requests still awaiting approval, or that were rejected by the attendant.
  static const _visibleClause =
      "COALESCE(approval_status, 'none') NOT IN ('pendente', 'recusada')";

  // ─── Fairs ──────────────────────────────────────────────────────────────────

  static Future<List<Fair>> getFairs() async {
    final database = await db;
    final maps = await database.query('fairs',
        where: '(archived IS NULL OR archived = 0)',
        orderBy: 'id');
    return maps.map(Fair.fromMap).toList();
  }

  static Future<void> archiveFair(int id) async {
    final database = await db;
    await database.update('fairs', {'archived': 1}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> restoreFair(int id) async {
    final database = await db;
    await database.update('fairs', {'archived': 0}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Fair>> getArchivedFairs() async {
    final database = await db;
    final maps = await database.query('fairs',
        where: 'archived = 1',
        orderBy: 'id');
    return maps.map(Fair.fromMap).toList();
  }

  /// Returns the first non-empty pavilhao / date values found across all clients
  /// of each fair. Shape: { fairId: { 'dataMontagem': '...', 'dataEvento': '...',
  /// 'dataDesmontagem': '...', 'pavilhao': '...' } }
  static Future<Map<int, Map<String, String>>> getFairEventDates() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT fair_id,
        MAX(NULLIF(pavilhao, ''))         AS pavilhao,
        MAX(NULLIF(data_montagem, ''))    AS dataMontagem,
        MAX(NULLIF(data_evento, ''))      AS dataEvento,
        MAX(NULLIF(data_desmontagem, '')) AS dataDesmontagem
      FROM clients
      GROUP BY fair_id
    ''');
    final result = <int, Map<String, String>>{};
    for (final r in rows) {
      final id = r['fair_id'] as int?;
      if (id == null) continue;
      result[id] = {
        'pavilhao': (r['pavilhao'] as String?) ?? '',
        'dataMontagem': (r['dataMontagem'] as String?) ?? '',
        'dataEvento': (r['dataEvento'] as String?) ?? '',
        'dataDesmontagem': (r['dataDesmontagem'] as String?) ?? '',
      };
    }
    return result;
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

  static Future<void> updateFairAutoApprove(int id, bool value) async {
    final database = await db;
    await database.update('fairs', {'auto_approve': value ? 1 : 0},
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

  /// Removes clients whose row_id is no longer in [activeRowIds], along with
  /// their pending items. Called after a sheet sync to clean up deleted rows.
  static Future<void> deleteStaleClients(
      int fairId, Set<String> activeRowIds) async {
    if (activeRowIds.isEmpty) return;
    final database = await db;
    final existing = await database.query('clients',
        columns: ['row_id'], where: 'fair_id = ?', whereArgs: [fairId]);
    final toDelete = existing
        .map((r) => r['row_id'] as String)
        .where((id) => !activeRowIds.contains(id))
        .toList();
    if (toDelete.isEmpty) return;
    for (final rowId in toDelete) {
      await database.delete('pending_items',
          where: 'client_id = ?', whereArgs: [rowId]);
      await database.delete('clients',
          where: 'row_id = ?', whereArgs: [rowId]);
    }
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

  /// Applies a completion status coming from the shared cloud state, keyed by
  /// the client's stable cross-device id (firestore_id).
  ///
  /// Legacy rows may have an empty firestore_id — Client.fromMap falls back to
  /// row_id in that case, so the lookup accepts either column. Both ids are
  /// prefixed with the fair id, and the update is scoped to the fair anyway.
  static Future<void> updateClientStatusByFirestoreId(
      int fairId, String firestoreId, bool completed,
      DateTime? completedAt) async {
    final database = await db;
    await database.update(
      'clients',
      {
        'is_completed': completed ? 1 : 0,
        'completed_at': completed
            ? (completedAt ?? DateTime.now()).toIso8601String()
            : null,
      },
      where: 'fair_id = ? AND (firestore_id = ? OR row_id = ?)',
      whereArgs: [fairId, firestoreId, firestoreId],
    );
  }

  /// Returns the set of row_ids already stored for a fair (used to detect new
  /// clients after a sheet sync so that push notifications can be sent).
  static Future<Set<String>> getExistingClientRowIds(int fairId) async {
    final database = await db;
    final rows = await database.query('clients',
        columns: ['row_id'], where: 'fair_id = ?', whereArgs: [fairId]);
    return rows.map((r) => r['row_id'] as String).toSet();
  }

  /// Finds a derived (mestra_child) fair by name or creates one if it doesn't
  /// exist. Returns the fair's id. Called when syncing a master sheet.
  static Future<int> findOrCreateDerivedFair({
    required String name,
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final database = await db;
    final existing = await database.query('fairs',
        where: "name = ? AND sheet_mode = 'mestra_child'",
        whereArgs: [name],
        limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return database.insert('fairs', {
      'name': name,
      'spreadsheet_id': spreadsheetId,
      'sheet_name': sheetName,
      'created_at': DateTime.now().toIso8601String(),
      'mode': 'producao',
      'sheet_mode': 'mestra_child',
    });
  }

  static Future<List<Client>> getClients({required int fairId}) async {
    final database = await db;
    final maps = await database.query('clients',
        where: 'fair_id = ?', whereArgs: [fairId], orderBy: 'hangar, local');
    return maps.map(Client.fromMap).toList();
  }

  /// Fair IDs that have at least one client assigned to [producerName].
  static Future<List<int>> getFairIdsWithProducer(String producerName) async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT DISTINCT fair_id FROM clients WHERE produtor = ? AND produtor != ''",
      [producerName],
    );
    return rows.map((r) => r['fair_id'] as int).toList();
  }

  /// Fair IDs that have at least one client where the leader's team column
  /// matches [leaderName]. The team-to-column mapping mirrors the hangar screen.
  /// Teams without a per-client column (e.g. Comunicação Visual, Vidraceiro)
  /// cover all fairs, so every fair ID is returned for them.
  static Future<List<int>> getFairIdsWithLeader(
      String leaderName, String team) async {
    final database = await db;
    final col = _teamColumn(team);
    if (col == null) {
      // No per-client column — this team covers all fairs.
      final rows = await database.rawQuery('SELECT id FROM fairs');
      return rows.map((r) => r['id'] as int).toList();
    }
    final rows = await database.rawQuery(
      "SELECT DISTINCT fair_id FROM clients WHERE $col = ? AND $col != ''",
      [leaderName],
    );
    return rows.map((r) => r['fair_id'] as int).toList();
  }

  /// Coluna da planilha que guarda o líder desta equipe, ou null quando a
  /// equipe não tem coluna por cliente.
  static String? teamColumn(String team) => _teamColumn(team);

  static String? _teamColumn(String team) {
    switch (team.toLowerCase().trim()) {
      case 'elétrica':
      case 'eletrica':
        return 'eletricista';
      case 'limpeza':
        return 'faxineira';
      case 'marcenaria':
        return 'marceneiro';
      case 'tapeçaria':
      case 'tapecaria':
        return 'tapeceiro';
      case 'teto 50':
        return 'teto50';
      // Comunicação Visual e Vidraceiro não têm coluna por cliente —
      // retorna null para que getFairIdsWithLeader liste todas as feiras.
      default:
        return null;
    }
  }

  /// Fair IDs that have at least one client assigned to [consultantName].
  static Future<List<int>> getFairIdsWithConsultant(String consultantName) async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT DISTINCT fair_id FROM clients WHERE atendimento = ? AND atendimento != ''",
      [consultantName],
    );
    return rows.map((r) => r['fair_id'] as int).toList();
  }

  static Future<Map<String, int>> getPendingCounts(
      List<String> clientIds) async {
    if (clientIds.isEmpty) return {};
    final database = await db;
    final ids = clientIds.map((id) => "'$id'").join(',');
    final rows = await database.rawQuery(
      'SELECT client_id, COUNT(*) as cnt FROM pending_items '
      'WHERE client_id IN ($ids) AND is_resolved = 0 AND $_visibleClause GROUP BY client_id',
    );
    return {for (final r in rows) r['client_id'] as String: r['cnt'] as int};
  }

  /// Open (unresolved) pending count per client for an entire fair.
  static Future<Map<String, int>> getAllPendingCounts(int fairId) async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT client_id, COUNT(*) as cnt FROM pending_items '
      'WHERE fair_id = ? AND is_resolved = 0 AND $_visibleClause GROUP BY client_id',
      [fairId],
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
      'WHERE client_id IN ($ids) AND is_resolved = 0 AND team = ? AND $_visibleClause GROUP BY client_id',
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
      String clientId,
      {bool excludeUnapproved = false,
      bool resolvedOnly = false}) async {
    final database = await db;
    var clauses = <String>['client_id = ?'];
    if (excludeUnapproved) clauses.add(_visibleClause);
    if (resolvedOnly) {
      // Recusar grava is_resolved = 1, então filtrar só por isso trazia
      // chamados recusados junto — e o relatório de entrega do stand, que vai
      // para o expositor, os listava como serviço resolvido.
      clauses.add('is_resolved = 1');
      clauses.add("COALESCE(approval_status, 'none') != 'recusada'");
    }
    final where = clauses.join(' AND ');
    final maps = await database.query('pending_items',
        where: where,
        whereArgs: [clientId],
        orderBy: 'created_at DESC');
    return maps.map(PendingItem.fromMap).toList();
  }

  /// Distinct organizer names from the spreadsheet (column "organizadora").
  static Future<List<String>> getOrganizers({required int fairId}) async {
    final database = await db;
    final result = await database.rawQuery(
        "SELECT DISTINCT organizadora FROM clients WHERE organizadora != '' AND fair_id = ? ORDER BY organizadora",
        [fairId]);
    return result.map((r) => r['organizadora'] as String).toList();
  }

  /// Organizer requests awaiting the attendant's approval, for a fair.
  static Future<List<PendingItem>> getPendingApprovalItems(
      {required int fairId}) async {
    final database = await db;
    final maps = await database.query(
      'pending_items',
      where: "fair_id = ? AND origem = 'organizadora' AND approval_status = 'pendente' AND is_resolved = 0",
      whereArgs: [fairId],
      orderBy: 'created_at',
    );
    return maps.map(PendingItem.fromMap).toList();
  }

  /// Approves an organizer request: it becomes a normal pending and flows to
  /// the producer/leader.
  static Future<void> approveOrganizerItem(int id, {String note = ''}) async {
    final database = await db;
    await database.update(
        'pending_items',
        {
          'approval_status': 'aprovada',
          if (note.isNotEmpty) 'approval_note': note,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  /// Rejects an organizer request: it is finalized (closed) with a reason.
  static Future<void> rejectOrganizerItem(int id,
      {String reason = '', String by = ''}) async {
    final database = await db;
    await database.update(
      'pending_items',
      {
        'approval_status': 'recusada',
        'rejection_reason': reason,
        'is_resolved': 1,
        'resolved_at': DateTime.now().toIso8601String(),
        if (by.isNotEmpty) 'resolved_by': by,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Nomes distintos de uma coluna de pessoa, em TODAS as feiras.
  ///
  /// A tela de cadastro filtrava pela feira aberta, e por isso não enxergava
  /// quem só existe na planilha mestra: os clientes da mestra são gravados
  /// sob as feiras derivadas (mestra_child), nunca sob o id da própria
  /// mestra. Com a mestra aberta, a consulta não achava ninguém — e sem uma
  /// feira aberta, ninguém aparecia de lugar nenhum. Cadastro de pessoa não é
  /// por feira: o PIN vale para todas.
  static Future<List<String>> _allPeopleIn(String column) async {
    final database = await db;
    final result = await database.rawQuery(
        "SELECT DISTINCT $column AS nome FROM clients "
        "WHERE $column IS NOT NULL AND TRIM($column) != '' ORDER BY $column");
    return result
        .map((r) => (r['nome'] as String).trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  static Future<List<String>> getAllProducers() => _allPeopleIn('produtor');

  static Future<List<String>> getAllConsultants() =>
      _allPeopleIn('atendimento');

  static Future<List<String>> getAllOrganizers() =>
      _allPeopleIn('organizadora');

  /// Busca expositores em TODAS as feiras.
  ///
  /// A busca é local porque os dados já estão aqui: o espelho da nuvem enche
  /// o banco das feiras que interessam a quem está logado. Consultar o
  /// Firestore a cada tecla custaria leitura e não acharia nada que já não
  /// esteja aqui.
  ///
  /// Procura por nome, stand e pavilhão — os três jeitos pelos quais alguém
  /// se lembra de um expositor.
  static Future<List<Map<String, dynamic>>> searchClients(String query) async {
    final termo = query.trim();
    if (termo.length < 2) return [];
    final database = await db;
    final like = '%${termo.toLowerCase()}%';
    final rows = await database.rawQuery(
      "SELECT c.*, f.name AS fair_name FROM clients c "
      "LEFT JOIN fairs f ON f.id = c.fair_id "
      "WHERE LOWER(c.nome) LIKE ? OR LOWER(c.local) LIKE ? "
      "   OR LOWER(c.pavilhao) LIKE ? "
      "ORDER BY c.nome LIMIT 60",
      [like, like, like],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Quem trabalha numa feira: produtores, consultores e líderes.
  ///
  /// Os líderes saem das colunas por equipe da planilha (eletricista,
  /// faxineira, marceneiro, tapeceiro, teto50). Comunicação Visual e
  /// Vidraceiro não têm coluna por cliente — quem lidera essas equipes atende
  /// todas as feiras e por isso não dá para deduzir daqui; a tela de aviso
  /// completa esse caso.
  static Future<({
    List<String> producers,
    List<String> consultants,
    List<String> leaders,
  })> getFairAudience(int fairId) async {
    final database = await db;

    Future<List<String>> distinct(String column) async {
      final rows = await database.rawQuery(
        "SELECT DISTINCT $column AS nome FROM clients "
        "WHERE fair_id = ? AND $column IS NOT NULL AND TRIM($column) != '' "
        "ORDER BY $column",
        [fairId],
      );
      return rows
          .map((r) => (r['nome'] as String).trim())
          .where((n) => n.isNotEmpty)
          .toList();
    }

    final leaders = <String>{};
    for (final col in const [
      'eletricista',
      'faxineira',
      'marceneiro',
      'tapeceiro',
      'teto50',
    ]) {
      leaders.addAll(await distinct(col));
    }

    return (
      producers: await distinct('produtor'),
      consultants: await distinct('atendimento'),
      leaders: leaders.toList()..sort(),
    );
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
      'SELECT * FROM pending_items WHERE client_id IN ($ids) AND is_resolved = 0 AND $_visibleClause '
      'ORDER BY hangar, local, created_at',
    );
    return maps.map(PendingItem.fromMap).toList();
  }

  static Future<List<PendingItem>> getPendingItemsByTeam(
      String team, {required int fairId}) async {
    final database = await db;
    final maps = await database.query(
      'pending_items',
      where: 'team = ? AND fair_id = ? AND is_resolved = 0 AND $_visibleClause',
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

    // Resolve Firestore clientId to the local row_id format.
    // Firestore may store firestoreId (e.g. 'cas_2026_5'); all SQLite queries
    // use row_id (e.g. '1_5'). Match on either firestore_id or row_id.
    String clientId = item.clientId;
    int fairId = int.tryParse(item.clientId.split('_').first) ?? 1;
    final clientRow = await database.query(
      'clients',
      columns: ['row_id', 'fair_id'],
      where: "COALESCE(NULLIF(firestore_id, ''), row_id) = ?",
      whereArgs: [item.clientId],
      limit: 1,
    );
    if (clientRow.isNotEmpty) {
      clientId = clientRow.first['row_id'] as String;
      fairId = clientRow.first['fair_id'] as int;
    }

    final existing = await database.query('pending_items',
        where: 'firestore_id = ?', whereArgs: [item.firestoreId], limit: 1);
    if (existing.isNotEmpty) {
      await database.update(
        'pending_items',
        {
          'client_id': clientId, // normalize if previously stored as firestoreId
          'fair_id': fairId,
          'is_resolved': item.isResolved ? 1 : 0,
          'awaiting_validation': item.awaitingValidation ? 1 : 0,
          'in_progress': item.inProgress ? 1 : 0,
          'in_progress_by': item.inProgressBy,
          'resolved_at': item.resolvedAt?.toIso8601String(),
          'resolved_by': item.resolvedBy,
          'consultant_name': item.consultantName,
          'approval_status': item.approvalStatus,
          'rejection_reason': item.rejectionReason,
          'approval_note': item.approvalNote,
          'resolution_note': item.resolutionNote,
          'resolution_photos': jsonEncode(item.resolutionPhotoUrls),
          'description': item.description,
          'photo_urls': jsonEncode(item.photoUrls),
        },
        where: 'firestore_id = ?',
        whereArgs: [item.firestoreId],
      );
    } else {
      final data = {...item.toMap(), 'fair_id': fairId, 'client_id': clientId};
      await database.insert(
        'pending_items',
        data,
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

  /// Updates the editable content (description + photos) of a pending item.
  static Future<void> updatePendingContent(
      int id, String description, List<String> photoUrls) async {
    final database = await db;
    await database.update(
      'pending_items',
      {'description': description, 'photo_urls': jsonEncode(photoUrls)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Full edit: updates team, responsible, description and photos in SQLite.
  static Future<void> updatePendingFull(
      int id, {
      required String team,
      required String responsible,
      required String description,
      required List<String> photoUrls,
  }) async {
    final database = await db;
    await database.update(
      'pending_items',
      {
        'team': team,
        'responsible': responsible,
        'description': description,
        'photo_urls': jsonEncode(photoUrls),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> resolvePendingItem(int id,
      {String? resolvedBy,
      String? resolutionNote,
      List<String>? resolutionPhotoUrls}) async {
    final database = await db;
    await database.update(
      'pending_items',
      {
        'is_resolved': 1,
        'resolved_at': DateTime.now().toIso8601String(),
        if (resolvedBy != null && resolvedBy.isNotEmpty) 'resolved_by': resolvedBy,
        // Nota e fotos de manutenção são opcionais: só sobrescreve quando
        // vieram preenchidas, para não apagar o que já existia.
        if (resolutionNote != null && resolutionNote.isNotEmpty)
          'resolution_note': resolutionNote,
        if (resolutionPhotoUrls != null && resolutionPhotoUrls.isNotEmpty)
          'resolution_photos': jsonEncode(resolutionPhotoUrls),
      },
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

  static Future<void> markInProgress(int id, String by) async {
    final database = await db;
    await database.update(
      'pending_items',
      {'in_progress': 1, 'in_progress_by': by},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Busca um cliente por qualquer um dos dois identificadores (row_id local ou
  /// firestore_id), em qualquer feira. Usado ao abrir uma notificação, quando
  /// ainda não se sabe a que feira o item pertence.
  static Future<Client?> findClientByAnyId(String id) async {
    if (id.isEmpty) return null;
    final database = await db;
    final rows = await database.query(
      'clients',
      where: "row_id = ? OR (firestore_id != '' AND firestore_id = ?)",
      whereArgs: [id, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Client.fromMap(rows.first);
  }

  /// Grava nota/fotos de manutenção pelo id local. Usado quando o produtor
  /// conclui: a nota é registrada já nesse momento, antes da validação, para
  /// não se perder no caminho.
  static Future<void> setResolutionNote(int id,
      {String? note, List<String>? photoUrls}) async {
    final database = await db;
    await database.update(
      'pending_items',
      {
        if (note != null && note.isNotEmpty) 'resolution_note': note,
        if (photoUrls != null && photoUrls.isNotEmpty)
          'resolution_photos': jsonEncode(photoUrls),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Grava nota/fotos de manutenção num item identificado pelo id do Firestore.
  /// Usado quando a conclusão parte de um item que só existe na nuvem.
  static Future<void> setResolutionNoteByFirestoreId(String firestoreId,
      {String? note, List<String>? photoUrls}) async {
    final database = await db;
    await database.update(
      'pending_items',
      {
        if (note != null && note.isNotEmpty) 'resolution_note': note,
        if (photoUrls != null && photoUrls.isNotEmpty)
          'resolution_photos': jsonEncode(photoUrls),
      },
      where: 'firestore_id = ?',
      whereArgs: [firestoreId],
    );
  }

  static Future<void> resolvePendingItemByFirestoreId(String firestoreId,
      {String? resolvedBy}) async {
    final database = await db;
    await database.update(
      'pending_items',
      {
        'is_resolved': 1,
        'resolved_at': DateTime.now().toIso8601String(),
        if (resolvedBy != null && resolvedBy.isNotEmpty) 'resolved_by': resolvedBy,
      },
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
      // Recusadas gravam is_resolved = 1 junto com approval_status = 'recusada';
      // contá-las como resolvidas inflaria o número de conclusões.
      'resolved_pending': q(Sqflite.firstIntValue(await database.rawQuery(
          "SELECT COUNT(*) FROM pending_items WHERE is_resolved = 1 "
          "AND COALESCE(approval_status, 'none') != 'recusada' AND fair_id = ?",
          [fairId]))),
      'rejected_pending': q(Sqflite.firstIntValue(await database.rawQuery(
          "SELECT COUNT(*) FROM pending_items WHERE "
          "COALESCE(approval_status, 'none') = 'recusada' AND fair_id = ?",
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
        SUM(CASE WHEN is_resolved = 1
                  AND COALESCE(approval_status, 'none') != 'recusada'
                 THEN 1 ELSE 0 END) as resolved,
        SUM(CASE WHEN COALESCE(approval_status, 'none') = 'recusada'
                 THEN 1 ELSE 0 END) as rejected,
        AVG(CASE
          WHEN is_resolved = 1 AND resolved_at IS NOT NULL
          THEN (JULIANDAY(resolved_at) - JULIANDAY(created_at)) * 24 * 60
          ELSE NULL
        END) as avg_minutes
      FROM pending_items
      WHERE fair_id = ?
      GROUP BY team
      ORDER BY total DESC
    ''', [fairId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Ranking por líder/responsável. Agrupa pelo campo `responsible` da
  /// pendência — a mesma pessoa usada para direcionar a notificação ao líder
  /// daquele cliente/equipe.
  static Future<List<Map<String, dynamic>>> getLeaderRankings(
      {required int fairId}) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT responsible as leader,
        COUNT(*) as total,
        SUM(CASE WHEN is_resolved = 0 THEN 1 ELSE 0 END) as open,
        SUM(CASE WHEN is_resolved = 1
                  AND COALESCE(approval_status, 'none') != 'recusada'
                 THEN 1 ELSE 0 END) as resolved,
        SUM(CASE WHEN COALESCE(approval_status, 'none') = 'recusada'
                 THEN 1 ELSE 0 END) as rejected,
        AVG(CASE
          WHEN is_resolved = 1 AND resolved_at IS NOT NULL
          THEN (JULIANDAY(resolved_at) - JULIANDAY(created_at)) * 24 * 60
          ELSE NULL
        END) as avg_minutes
      FROM pending_items
      WHERE fair_id = ? AND COALESCE(responsible, '') != ''
      GROUP BY responsible
      ORDER BY total DESC
    ''', [fairId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Returns cross-fair summary for all fairs (for the metrics tab).
  static Future<List<Map<String, dynamic>>> getCrossFairStats() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT f.name as fair_name,
        COUNT(DISTINCT c.row_id) as total_clients,
        SUM(CASE WHEN c.is_completed = 1 THEN 1 ELSE 0 END) as completed_clients,
        COUNT(p.id) as total_pending,
        SUM(CASE WHEN p.is_resolved = 1
                  AND COALESCE(p.approval_status, 'none') != 'recusada'
                 THEN 1 ELSE 0 END) as resolved_pending,
        SUM(CASE WHEN COALESCE(p.approval_status, 'none') = 'recusada'
                 THEN 1 ELSE 0 END) as rejected_pending,
        AVG(CASE
          WHEN p.is_resolved = 1 AND p.resolved_at IS NOT NULL
          THEN (JULIANDAY(p.resolved_at) - JULIANDAY(p.created_at)) * 24 * 60
          ELSE NULL
        END) as avg_minutes
      FROM fairs f
      LEFT JOIN clients c ON c.fair_id = f.id
      LEFT JOIN pending_items p ON p.fair_id = f.id
      GROUP BY f.id, f.name
      ORDER BY f.created_at DESC
    ''');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<List<Map<String, dynamic>>> getProducerRankings(
      {required int fairId}) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT c.produtor as producer,
        COUNT(*) as total,
        SUM(CASE WHEN p.is_resolved = 0 THEN 1 ELSE 0 END) as open,
        SUM(CASE WHEN p.is_resolved = 1
                  AND COALESCE(p.approval_status, 'none') != 'recusada'
                 THEN 1 ELSE 0 END) as resolved,
        SUM(CASE WHEN COALESCE(p.approval_status, 'none') = 'recusada'
                 THEN 1 ELSE 0 END) as rejected
      FROM pending_items p
      JOIN clients c ON c.row_id = p.client_id
      WHERE c.produtor != '' AND p.fair_id = ?
      GROUP BY c.produtor
      ORDER BY total DESC
    ''', [fairId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
