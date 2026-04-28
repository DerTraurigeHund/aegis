import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/server.dart';

class DatabaseService {
  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, 'server_monitor.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE servers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            base_url TEXT NOT NULL,
            api_key TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<List<Server>> getServers() async {
    final db = await database;
    final maps = await db.query('servers', orderBy: 'created_at DESC');
    return maps.map((m) => Server.fromMap(m)).toList();
  }

  Future<Server> addServer(Server server) async {
    final db = await database;
    final id = await db.insert('servers', server.toMap());
    return Server(
      id: id,
      name: server.name,
      baseUrl: server.baseUrl,
      apiKey: server.apiKey,
      createdAt: server.createdAt,
    );
  }

  Future<void> deleteServer(int id) async {
    final db = await database;
    await db.delete('servers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateServer(Server server) async {
    final db = await database;
    await db.update('servers', server.toMap(), where: 'id = ?', whereArgs: [server.id]);
  }
}
