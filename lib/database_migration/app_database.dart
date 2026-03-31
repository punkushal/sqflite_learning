import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'models/database_migration.dart';

class AppDatabase {
  static const String _dbName = 'my_app.db';
  static const int _currentVersion = 5;

  static Database? _database;

  /// All migrations in order
  /// NEVER remove or modify old migrations!
  /// Only ADD new ones at the end.
  static final List<DatabaseMigration> _migrations = [
    // ── Version 1 → 2: Add priority to tasks ──
    DatabaseMigration(
      version: 2,
      description: 'Add priority column to tasks table',
      migrate: (db) async {
        await db.execute(
          'ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 0',
        );
        // WHY DEFAULT 0? → Existing rows need a value.
        //                   0 means "normal priority" for old tasks.
      },
    ),

    // ── Version 2 → 3: Add tags system ──
    DatabaseMigration(
      version: 3,
      description: 'Add tags table and task_tags junction table',
      migrate: (db) async {
        await db.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color TEXT NOT NULL DEFAULT '#808080'
          )
        ''');

        // Junction table for many-to-many relationship (task ↔ tag)
        // WHY junction table? → One task can have many tags,
        //                       and one tag can be on many tasks.
        await db.execute('''
          CREATE TABLE task_tags (
            task_id INTEGER NOT NULL,
            tag_id INTEGER NOT NULL,
            PRIMARY KEY (task_id, tag_id),
            FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
          )
        ''');

        // Index for faster lookups on junction table
        await db.execute(
          'CREATE INDEX idx_task_tags_tag_id ON task_tags(tag_id)',
        );
      },
    ),

    // ── Version 3 → 4: Add due_date and notes to tasks ──
    DatabaseMigration(
      version: 4,
      description: 'Add due_date and notes columns to tasks',
      migrate: (db) async {
        // SQLite limitation: ALTER TABLE can only ADD one column at a time
        await db.execute('ALTER TABLE tasks ADD COLUMN due_date TEXT');
        await db.execute('ALTER TABLE tasks ADD COLUMN notes TEXT');

        // Add index on due_date for queries like "tasks due today"
        await db.execute('CREATE INDEX idx_tasks_due_date ON tasks(due_date)');
      },
    ),

    // ── Version 4 → 5: Add user settings table ──
    DatabaseMigration(
      version: 5,
      description: 'Add settings table for user preferences',
      migrate: (db) async {
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        // Using TEXT PRIMARY KEY instead of INTEGER
        // WHY? → Settings are key-value pairs like ('theme', 'dark')
        //        The key itself is the identifier.

        // Insert default settings
        await db.insert('settings', {'key': 'theme', 'value': 'system'});
        await db.insert('settings', {'key': 'language', 'value': 'en'});
        await db.insert('settings', {'key': 'notifications', 'value': 'true'});
      },
    ),
  ];

  /// Get the database instance (creates it if needed)
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _dbName);

    return await openDatabase(
      path,
      version: _currentVersion,

      // ── FRESH INSTALL: Create everything from scratch ──
      onCreate: (db, version) async {
        // Create ALL tables in their LATEST form
        // This runs only for brand new installations
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            is_completed INTEGER NOT NULL DEFAULT 0,
            priority INTEGER NOT NULL DEFAULT 0,
            due_date TEXT,
            notes TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color TEXT NOT NULL DEFAULT '#808080'
          )
        ''');

        await db.execute('''
          CREATE TABLE task_tags (
            task_id INTEGER NOT NULL,
            tag_id INTEGER NOT NULL,
            PRIMARY KEY (task_id, tag_id),
            FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');

        // Create all indexes
        await db.execute(
          'CREATE INDEX idx_task_tags_tag_id ON task_tags(tag_id)',
        );
        await db.execute('CREATE INDEX idx_tasks_due_date ON tasks(due_date)');

        // Insert default settings
        await db.insert('settings', {'key': 'theme', 'value': 'system'});
        await db.insert('settings', {'key': 'language', 'value': 'en'});
        await db.insert('settings', {'key': 'notifications', 'value': 'true'});
      },

      // ── APP UPDATE: Run migrations sequentially ──
      onUpgrade: (db, oldVersion, newVersion) async {
        // Run each migration that hasn't been applied yet
        for (final migration in _migrations) {
          if (migration.version > oldVersion &&
              migration.version <= newVersion) {
            print(
              '📦 Running migration v${migration.version}: '
              '${migration.description}',
            );
            await migration.migrate(db);
          }
        }
        // Example: User updates from v2 to v5
        // → Runs migration 3 (v2→v3)
        // → Runs migration 4 (v3→v4)
        // → Runs migration 5 (v4→v5)
        // → Skips migration 2 (already applied)
      },

      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Close the database (call when app terminates)
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

/// ============================================================
/// ADVANCED MIGRATION SCENARIOS
/// ============================================================

/// ── Scenario 1: Renaming a column (SQLite doesn't support ALTER RENAME) ──
/// Solution: Create new table, copy data, drop old, rename new
DatabaseMigration renameColumnMigration = DatabaseMigration(
  version: 6,
  description: 'Rename tasks.description to tasks.summary',
  migrate: (db) async {
    // Step 1: Create new table with desired column name
    await db.execute('''
      CREATE TABLE tasks_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        summary TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        due_date TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Step 2: Copy data from old table to new table
    await db.execute('''
      INSERT INTO tasks_new (id, title, summary, is_completed, priority, 
                             due_date, notes, created_at)
      SELECT id, title, description, is_completed, priority,
             due_date, notes, created_at
      FROM tasks
    ''');

    // Step 3: Drop old table
    await db.execute('DROP TABLE tasks');

    // Step 4: Rename new table to old name
    await db.execute('ALTER TABLE tasks_new RENAME TO tasks');

    // Step 5: Recreate indexes (they were dropped with the old table)
    await db.execute('CREATE INDEX idx_tasks_due_date ON tasks(due_date)');
  },
);

/// ── Scenario 2: Changing column type ──
/// SQLite doesn't support ALTER COLUMN, so same pattern as above
DatabaseMigration changeColumnTypeMigration = DatabaseMigration(
  version: 7,
  description: 'Change tasks.priority from INTEGER to TEXT',
  migrate: (db) async {
    await db.execute('''
      CREATE TABLE tasks_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        summary TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        priority TEXT NOT NULL DEFAULT 'medium',
        due_date TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Convert integer priority to text during copy
    await db.execute('''
      INSERT INTO tasks_new (id, title, summary, is_completed, priority,
                             due_date, notes, created_at)
      SELECT id, title, summary, is_completed,
             CASE priority
               WHEN 0 THEN 'low'
               WHEN 1 THEN 'medium'
               WHEN 2 THEN 'high'
               ELSE 'medium'
             END,
             due_date, notes, created_at
      FROM tasks
    ''');

    await db.execute('DROP TABLE tasks');
    await db.execute('ALTER TABLE tasks_new RENAME TO tasks');
    await db.execute('CREATE INDEX idx_tasks_due_date ON tasks(due_date)');
  },
);

/// ── Scenario 3: Adding data transformation during migration ──
DatabaseMigration dataTransformMigration = DatabaseMigration(
  version: 8,
  description: 'Normalize phone numbers in users table',
  migrate: (db) async {
    // Read all users
    final users = await db.query('users');

    for (final user in users) {
      final phone = user['phone'] as String?;
      if (phone != null) {
        // Remove all non-digit characters
        final normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
        await db.update(
          'users',
          {'phone': normalized},
          where: 'id = ?',
          whereArgs: [user['id']],
        );
      }
    }
  },
);
