import '../db_helper.dart';
import '../models/task.dart';
import 'base_repo.dart';

class TaskRepository extends BaseRepository<Task> {
  TaskRepository(super.dbHelper);

  @override
  String get tableName => DatabaseHelper.tableTasks;

  @override
  Task fromMap(Map<String, dynamic> map) => Task.fromMap(map);

  @override
  Map<String, dynamic> toMap(Task item) => item.toMap();

  /// Get tasks for a specific user
  Future<List<Task>> getByUserId(
    int userId, {
    bool? isCompleted,
    TaskPriority? priority,
    String orderBy = 'created_at DESC',
  }) async {
    final db = await database;

    // Build WHERE clause dynamically
    final List<String> conditions = ['user_id = ?'];
    final List<dynamic> args = [userId];

    if (isCompleted != null) {
      conditions.add('is_completed = ?');
      args.add(isCompleted ? 1 : 0);
    }

    if (priority != null) {
      conditions.add('priority = ?');
      args.add(priority.index);
    }

    final maps = await db.query(
      tableName,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: orderBy,
    );

    return maps.map(fromMap).toList();
  }

  /// Get tasks due today
  Future<List<Task>> getDueToday(int userId) async {
    final db = await database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      tableName,
      where:
          'user_id = ? AND due_date >= ? AND due_date < ? AND is_completed = 0',
      whereArgs: [
        userId,
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
      orderBy: 'priority DESC, due_date ASC',
    );

    return maps.map(fromMap).toList();
  }

  /// Get overdue tasks
  Future<List<Task>> getOverdue(int userId) async {
    final db = await database;

    final maps = await db.query(
      tableName,
      where:
          'user_id = ? AND due_date < ? AND is_completed = 0 AND due_date IS NOT NULL',
      whereArgs: [userId, DateTime.now().toIso8601String()],
      orderBy: 'due_date ASC',
    );

    return maps.map(fromMap).toList();
  }

  /// Mark task as completed
  Future<void> markCompleted(int taskId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      tableName,
      {'is_completed': 1, 'completed_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  /// Get task count by category (for dashboard)
  Future<List<Map<String, dynamic>>> getCountByCategory(int userId) async {
    final db = await database;

    return await db.rawQuery(
      '''
      SELECT 
        c.id as category_id,
        c.name as category_name,
        c.color as category_color,
        COUNT(t.id) as total_tasks,
        SUM(CASE WHEN t.is_completed = 1 THEN 1 ELSE 0 END) as completed_tasks
      FROM ${DatabaseHelper.tableCategories} c
      LEFT JOIN $tableName t ON t.category_id = c.id AND t.user_id = ?
      GROUP BY c.id
      ORDER BY c.sort_order ASC
    ''',
      [userId],
    );
    // LEFT JOIN → Include categories even if they have no tasks
    // SUM(CASE ...) → Count only completed tasks
  }

  /// Search tasks by title or description
  Future<List<Task>> search(int userId, String query) async {
    final db = await database;
    final searchTerm = '%$query%'; // % = wildcard (matches any characters)

    final maps = await db.query(
      tableName,
      where: 'user_id = ? AND (title LIKE ? OR description LIKE ?)',
      whereArgs: [userId, searchTerm, searchTerm],
      orderBy: 'created_at DESC',
    );
    // LIKE with % → Fuzzy search
    // '%hello%' matches: "say hello world", "hello", "oh hello there"

    return maps.map(fromMap).toList();
  }

  /// Bulk complete tasks
  Future<void> bulkComplete(List<int> taskIds) async {
    if (taskIds.isEmpty) return;

    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Use transaction for atomicity
    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final id in taskIds) {
        batch.update(
          tableName,
          {'is_completed': 1, 'completed_at': now, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      await batch.commit(noResult: true);
    });
  }

  /// Get completion statistics
  Future<Map<String, dynamic>> getStatistics(int userId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN is_completed = 0 THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN is_completed = 0 AND due_date < ? AND due_date IS NOT NULL 
            THEN 1 ELSE 0 END) as overdue
      FROM $tableName
      WHERE user_id = ?
    ''',
      [DateTime.now().toIso8601String(), userId],
    );

    return result.first;
  }

  /// Paginated query (for infinite scroll lists)
  Future<List<Task>> getPaginated({
    required int userId,
    required int page,
    int pageSize = 20,
    String orderBy = 'created_at DESC',
  }) async {
    final db = await database;

    final maps = await db.query(
      tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: orderBy,
      limit: pageSize,
      offset: page * pageSize, // Page 0 → offset 0, Page 1 → offset 20, etc.
    );

    return maps.map(fromMap).toList();
  }
}
