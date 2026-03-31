import 'package:sqflite/sqflite.dart';
import 'package:sqflite_learning/clean_code_level1/clean_code.dart';

/// ============================================================
/// DatabaseExecutor — The Common Interface
/// ============================================================
///
/// In sqflite, there are three things that can execute SQL:
///
///   1. Database     → The main database object
///   2. Transaction  → Inside db.transaction((txn) { ... })
///   3. Batch        → Inside db.batch() (we'll cover later)
///
/// Both Database and Transaction implement the DatabaseExecutor interface.
/// This means they share the same methods:
///   - execute(), insert(), query(), update(), delete()
///   - rawInsert(), rawQuery(), rawUpdate(), rawDelete()
///
/// WHY does this matter?
/// → You can write functions that accept DatabaseExecutor
///   and they'll work with BOTH regular database calls AND transactions!
///   This is crucial for writing reusable, testable code.

class UserRepository {
  final Database _db;

  UserRepository(this._db);

  /// This method accepts DatabaseExecutor instead of Database.
  /// WHY? → So it can be called from both normal code AND inside transactions.
  ///
  /// Without DatabaseExecutor:
  ///   - You'd need two versions of every method (one for db, one for txn)
  ///   - OR you'd have to duplicate code inside transactions
  Future<int> insertUser(User user, {DatabaseExecutor? executor}) async {
    // Use the provided executor, or fall back to the database
    final DatabaseExecutor exec = executor ?? _db;

    return await exec.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<User>> getAllUsers({DatabaseExecutor? executor}) async {
    final DatabaseExecutor exec = executor ?? _db;

    final maps = await exec.query('users', orderBy: 'name ASC');
    return maps.map((map) => User.fromMap(map)).toList();
  }

  Future<User?> getUserById(int id, {DatabaseExecutor? executor}) async {
    final DatabaseExecutor exec = executor ?? _db;

    final maps = await exec.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return User.fromMap(maps.first);
  }

  Future<int> updateUser(User user, {DatabaseExecutor? executor}) async {
    final DatabaseExecutor exec = executor ?? _db;

    return await exec.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<int> deleteUser(int id, {DatabaseExecutor? executor}) async {
    final DatabaseExecutor exec = executor ?? _db;

    return await exec.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  /// ── Using DatabaseExecutor in a transaction ──
  /// Now these methods can be composed inside transactions!
  Future<void> transferUserData(int fromId, int toId) async {
    await _db.transaction((txn) async {
      // Both calls are part of the SAME transaction because
      // we pass 'txn' as the executor!
      final fromUser = await getUserById(fromId, executor: txn);
      if (fromUser == null) throw Exception('User $fromId not found');

      await updateUser(fromUser.copyWith(id: toId), executor: txn);
      await deleteUser(fromId, executor: txn);
      // If deleteUser fails, updateUser is also rolled back!
    });
  }
}
