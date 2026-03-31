import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// ============================================================
/// CRUD = Create, Read, Update, Delete
/// ============================================================
/// sqflite provides two ways to do everything:
///
/// 1. HELPER METHODS → db.insert(), db.query(), db.update(), db.delete()
///    - Easier to use
///    - Less error-prone
///    - Handles escaping/sanitization automatically
///
/// 2. RAW SQL → db.rawInsert(), db.rawQuery(), db.rawUpdate(), db.rawDelete()
///    - More flexible
///    - You write actual SQL strings
///    - Better for complex queries (joins, subqueries)
///
/// RULE OF THUMB: Use helper methods for simple operations,
///                raw SQL for complex ones.
Future<void> crudExamples() async {
  final db = await openDatabase(
    join(await getDatabasesPath(), 'crud_demo.db'),
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE,
          age INTEGER,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');
    },
    onOpen: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
  );

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  CREATE (Insert)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // Method 1: Helper method (RECOMMENDED for simple inserts)
  // Returns: the id of the inserted row
  final int userId1 = await db.insert(
    'users', // table name
    {
      // Map of column:value pairs
      'name': 'Alice',
      'email': 'alice@example.com',
      'age': 28,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    },
    // conflictAlgorithm determines what happens if there's a conflict
    // (e.g., duplicate UNIQUE email)
    //
    // Options:
    // ConflictAlgorithm.abort   → Cancel this insert, throw error (DEFAULT)
    // ConflictAlgorithm.replace → Delete the old row, insert new one
    // ConflictAlgorithm.ignore  → Silently skip this insert
    // ConflictAlgorithm.rollback → Abort and rollback entire transaction
    // ConflictAlgorithm.fail    → Abort this statement only
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  print('Inserted user with id: $userId1'); // Output: 1

  // Method 2: Raw SQL (when you need more control)
  // Returns: the id of the inserted row
  final int userId2 = await db.rawInsert(
    '''
    INSERT INTO users (name, email, age, is_active, created_at)
    VALUES (?, ?, ?, ?, ?)
  ''',
    ['Bob', 'bob@example.com', 32, 1, DateTime.now().toIso8601String()],
  );
  // The ? marks are PLACEHOLDERS (parameterized queries)
  // WHY use ? instead of string interpolation?
  // → PREVENTS SQL INJECTION ATTACKS!
  // → Values are properly escaped automatically
  // → NEVER do: "VALUES ('$name', '$email')" — this is DANGEROUS!
  print('Inserted user with id: $userId2'); // Output: 2

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  READ (Query)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // Method 1: Query ALL rows
  final List<Map<String, dynamic>> allUsers = await db.query('users');
  // Returns a list of Maps, one per row:
  // [{id: 1, name: Alice, ...}, {id: 2, name: Bob, ...}]

  // Method 2: Query with ALL available parameters
  final List<Map<String, dynamic>> filteredUsers = await db.query(
    'users', // table name
    // distinct: true → Remove duplicate rows from results
    distinct: true,

    // columns: Which columns to return (null = all columns)
    // WHY specify? → Performance! Only fetch what you need.
    columns: ['id', 'name', 'email', 'age'],

    // where: Filter condition (like SQL WHERE clause)
    // Use ? for parameter placeholders
    where: 'age > ? AND is_active = ?',

    // whereArgs: Values to substitute for ? in where clause
    // WHY separate? → SQL injection prevention!
    whereArgs: [25, 1],

    // groupBy: Group rows by a column (for aggregations)
    // groupBy: 'age',

    // having: Filter on grouped results (used with groupBy)
    // having: 'COUNT(*) > 1',

    // orderBy: Sort the results
    // ASC = ascending (A→Z, 1→9), DESC = descending (Z→A, 9→1)
    orderBy: 'name ASC',

    // limit: Maximum number of rows to return
    limit: 10,

    // offset: Skip this many rows (for pagination)
    // Page 1: offset 0, limit 10  → rows 1-10
    // Page 2: offset 10, limit 10 → rows 11-20
    offset: 0,
  );

  // Method 3: Raw query (for complex SQL)
  final List<Map<String, dynamic>> rawResults = await db.rawQuery(
    '''
    SELECT id, name, email, age
    FROM users
    WHERE age > ? AND is_active = ?
    ORDER BY name ASC
    LIMIT 10 OFFSET 0
  ''',
    [25, 1],
  );

  // Method 4: Count rows
  final int? count = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM users'),
  );
  print('Total users: $count');

  // Method 5: Query single row by ID
  final List<Map<String, dynamic>> singleUser = await db.query(
    'users',
    where: 'id = ?',
    whereArgs: [1],
    limit: 1, // We only expect one result, so limit to 1 for performance
  );
  if (singleUser.isNotEmpty) {
    print('Found user: ${singleUser.first}');
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  UPDATE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // Method 1: Helper method
  // Returns: number of rows affected
  final int updateCount = await db.update(
    'users',
    {'name': 'Alice Updated', 'age': 29}, // columns to update
    where: 'id = ?', // which rows to update
    whereArgs: [1], // value for ?
    // Without where clause → UPDATES ALL ROWS! (Usually not what you want)
  );
  print('Updated $updateCount rows');

  // Method 2: Raw SQL
  final int rawUpdateCount = await db.rawUpdate(
    'UPDATE users SET name = ?, age = ? WHERE id = ?',
    ['Bob Updated', 33, 2],
  );
  print('Updated $rawUpdateCount rows');

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  DELETE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // Method 1: Helper method
  // Returns: number of rows deleted
  final int deleteCount = await db.delete(
    'users',
    where: 'id = ?',
    whereArgs: [2],
    // Without where clause → DELETES ALL ROWS! Be very careful!
  );
  print('Deleted $deleteCount rows');

  // Method 2: Raw SQL
  final int rawDeleteCount = await db.rawDelete(
    'DELETE FROM users WHERE age < ?',
    [18],
  );
  print('Deleted $rawDeleteCount rows');

  // Method 3: Delete ALL rows (clear the table)
  await db.delete('users'); // No where clause = delete everything

  // Method 4: Alternative to delete all
  await db.execute('DELETE FROM users');

  await db.close();
}
