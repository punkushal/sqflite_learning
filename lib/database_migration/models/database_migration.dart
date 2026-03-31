import 'package:sqflite/sqflite.dart';

/// ============================================================
/// DATABASE MIGRATIONS — Handling App Updates
/// ============================================================
///
/// THE PROBLEM:
/// User has your app v1 with a "tasks" table.
/// You release v2 which adds a "priority" column to tasks.
/// You release v3 which adds a new "tags" table.
///
/// When the user updates from v1 → v3, you need to:
///   1. Add the "priority" column (v1 → v2 migration)
///   2. Create the "tags" table (v2 → v3 migration)
///   WITHOUT losing any of the user's existing data!
///
/// THE SOLUTION:
/// Each migration is a set of SQL statements that transform the database
/// from one version to the next. They run sequentially.
///
/// GOLDEN RULES:
///   1. NEVER modify a migration that's been released to users
///   2. ALWAYS add new migrations, never change old ones
///   3. onCreate should create the LATEST version from scratch
///   4. Test migration paths: v1→v2, v1→v3, v2→v3, etc.
///   5. NEVER use "DROP TABLE" in migrations (data loss!)
///      Exception: dropping a table you intentionally want to remove

/// ──────────────────────────────────────
/// Migration Strategy Pattern
/// ──────────────────────────────────────
class DatabaseMigration {
  final int version;
  final String description;
  final Future<void> Function(Database db) migrate;

  const DatabaseMigration({
    required this.version,
    required this.description,
    required this.migrate,
  });
}
