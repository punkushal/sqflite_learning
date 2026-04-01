import 'package:sqflite/sqflite.dart';
import '../db_helper.dart';

/// ============================================================
/// REPOSITORY PATTERN — Clean Separation of Concerns
/// ============================================================
///
/// WHY Repository Pattern?
///   1. UI code doesn't know about SQL or database internals
///   2. Easy to test (can mock the repository)
///   3. Easy to switch storage (SQL → API → Hive → etc.)
///   4. All database logic in one place per entity
///   5. Consistent error handling

/// ──────────────────────────────────────
/// Base Repository (shared functionality)
/// ──────────────────────────────────────
abstract class BaseRepository<T> {
  final DatabaseHelper _dbHelper;

  BaseRepository(this._dbHelper);

  /// Subclasses must specify their table name
  String get tableName;

  /// Subclasses must provide conversion methods
  T fromMap(Map<String, dynamic> map);
  Map<String, dynamic> toMap(T item);

  /// Get the database instance
  Future<Database> get _db => _dbHelper.database;

  /// Generic: Get all items
  Future<List<T>> getAll({
    String? orderBy,
    int? limit,
    int? offset,
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? await _db;
    final maps = await exec.query(
      tableName,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return maps.map(fromMap).toList();
  }

  /// Generic: Get item by ID
  Future<T?> getById(int id, {DatabaseExecutor? executor}) async {
    final exec = executor ?? await _db;
    final maps = await exec.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  /// Generic: Insert item
  Future<int> insert(T item, {DatabaseExecutor? executor}) async {
    final exec = executor ?? await _db;
    return await exec.insert(
      tableName,
      toMap(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Generic: Update item
  Future<int> update(T item, int id, {DatabaseExecutor? executor}) async {
    final exec = executor ?? await _db;
    return await exec.update(
      tableName,
      toMap(item),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Generic: Delete item
  Future<int> delete(int id, {DatabaseExecutor? executor}) async {
    final exec = executor ?? await _db;
    return await exec.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Generic: Count all items
  Future<int> count({DatabaseExecutor? executor}) async {
    final exec = executor ?? await _db;
    final result = await exec.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName',
    );
    return result.first['count'] as int;
  }

  /// Generic: Delete all items
  Future<int> deleteAll({DatabaseExecutor? executor}) async {
    final exec = executor ?? await _db;
    return await exec.delete(tableName);
  }
}
