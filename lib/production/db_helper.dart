import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// ============================================================
/// PRODUCTION DATABASE HELPER
/// ============================================================
/// Uses the Singleton pattern to ensure only ONE database
/// connection exists throughout the entire app lifecycle.
///
/// WHY Singleton?
/// → Multiple database connections can cause:
///   1. Database locked errors
///   2. Inconsistent data reads
///   3. Memory waste
///   4. File corruption in rare cases

class DatabaseHelper {
  // ── Singleton Setup ──
  // Private constructor — no one outside this class can create an instance
  DatabaseHelper._internal();

  // The single instance of this class
  static final DatabaseHelper instance = DatabaseHelper._internal();

  // Factory constructor — always returns the same instance
  // WHY factory? → It doesn't create a new object; it returns the existing one
  factory DatabaseHelper() => instance;

  // The database instance (nullable because it's not created until first use)
  static Database? _database;

  // Database configuration
  static const String _databaseName = 'app_production.db';
  static const int _databaseVersion = 3;

  // ── Table Names (constants to avoid typos) ──
  static const String tableUsers = 'users';
  static const String tableTasks = 'tasks';
  static const String tableCategories = 'categories';

  /// Get the database (lazy initialization)
  /// "Lazy" means: create it only when first needed, then reuse
  Future<Database> get database async {
    // If already created, return it
    if (_database != null) return _database!;

    // Otherwise, create it
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database
  Future<Database> _initDatabase() async {
    final String databasesPath = await getDatabasesPath();
    final String path = join(databasesPath, _databaseName);

    // In debug mode, print the database path
    // WHY? → So you can find and inspect the DB file during development
    if (kDebugMode) {
      print('📁 Database path: $path');
    }

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
      onConfigure: _onConfigure,
      onDowngrade: onDatabaseDowngradeDelete,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Enable foreign keys (required on every open!)
    await db.execute('PRAGMA foreign_keys = ON');
    // Optional: Enable WAL mode for better concurrent read performance
    // WHY WAL? → Allows reads and writes to happen simultaneously
    //            instead of blocking each other
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.rawQuery('PRAGMA busy_timeout = 5000');
  }

  /// Create all tables (fresh install)
  Future<void> _onCreate(Database db, int version) async {
    if (kDebugMode) print('Creating database v$version');

    // Use a batch for better performance when creating multiple tables
    // otherwise if only one table is being created then use db.transaction((txn)){}
    final batch = db.batch();

    // ── Users Table ──
    batch.execute('''
      CREATE TABLE $tableUsers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        avatar_url TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // ── Categories Table ──
    batch.execute('''
      CREATE TABLE $tableCategories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT NOT NULL DEFAULT '#808080',
        icon TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // ── Tasks Table ──
    batch.execute('''
      CREATE TABLE $tableTasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        category_id INTEGER,
        title TEXT NOT NULL,
        description TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        due_date TEXT,
        completed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES $tableCategories(id) ON DELETE SET NULL
      )
    ''');
    // ON DELETE SET NULL → If a category is deleted, tasks in that category
    //                       get category_id = null (not deleted)

    // ── Indexes ──
    batch.execute('CREATE INDEX idx_tasks_user_id ON $tableTasks(user_id)');
    batch.execute(
      'CREATE INDEX idx_tasks_category_id ON $tableTasks(category_id)',
    );
    batch.execute('CREATE INDEX idx_tasks_due_date ON $tableTasks(due_date)');
    batch.execute(
      'CREATE INDEX idx_tasks_completed ON $tableTasks(is_completed)',
    );

    await batch.commit(noResult: true);

    // Seed default categories
    await _seedDefaultData(db);
  }

  /// Seed initial data
  Future<void> _seedDefaultData(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    final defaultCategories = [
      {
        'name': 'Personal',
        'color': '#4CAF50',
        'icon': 'person',
        'sort_order': 1,
      },
      {'name': 'Work', 'color': '#2196F3', 'icon': 'work', 'sort_order': 2},
      {
        'name': 'Shopping',
        'color': '#FF9800',
        'icon': 'shopping_cart',
        'sort_order': 3,
      },
      {
        'name': 'Health',
        'color': '#E91E63',
        'icon': 'favorite',
        'sort_order': 4,
      },
    ];

    for (final category in defaultCategories) {
      batch.insert(tableCategories, {...category, 'created_at': now});
    }

    await batch.commit(noResult: true);
  }

  /// Run migrations
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (kDebugMode) {
      print('🟡 Upgrading database from v$oldVersion to v$newVersion');
    }

    // Each migration should be wrapped in a batch or transaction
    // for atomicity and performance
    if (oldVersion < 2) {
      await _migrateV1toV2(db);
    }
    if (oldVersion < 3) {
      await _migrateV2toV3(db);
    }
  }

  Future<void> _migrateV1toV2(Database db) async {
    if (kDebugMode) print(' Migrating v1 → v2');
    await db.execute(
      'ALTER TABLE $tableTasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateV2toV3(Database db) async {
    if (kDebugMode) print(' Migrating v2 → v3');
    await db.execute('ALTER TABLE $tableTasks ADD COLUMN completed_at TEXT');
    await db.execute('ALTER TABLE $tableUsers ADD COLUMN avatar_url TEXT');
  }

  /// Configure database on every open
  Future<void> _onOpen(Database db) async {
    if (kDebugMode) print('Database opened');

    // Good place for verification, e.g. integrity checks or debug logs.
    final result = await db.rawQuery('PRAGMA integrity_check');
    final ok = result.isNotEmpty && result.first.values.first == 'ok';
    if (!ok) {
      throw Exception('Database integrity check failed');
    }
  }

  /// Close database (call in app's dispose or when shutting down)
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
      if (kDebugMode) print('Database closed');
    }
  }

  /// Delete the entire database (for testing or "reset app" feature)
  Future<void> deleteDatabase() async {
    await close();
    final path = join(await getDatabasesPath(), _databaseName);
    await databaseFactory.deleteDatabase(path);
    if (kDebugMode) print('Database deleted');
  }
}
