import 'dart:developer';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// ============================================================
/// WHY use Models?
/// ============================================================
// ignore: unintended_html_in_doc_comment
/// Working with Map<String, dynamic> everywhere is:
///   1. Error-prone (typos in column names aren't caught at compile time)
///   2. Hard to read (row['created_at'] vs user.createdAt)
///   3. No type safety (everything is dynamic)
///
/// Models give us:
///   1. Compile-time safety (typos become compiler errors)
///   2. Readable code (user.name instead of row['name'])
///   3. Type safety (user.age is always int?, not dynamic)
///   4. Single place to define conversion logic

/// ──────────────────────────────────────
/// The User Model
/// ──────────────────────────────────────
class User {
  final int? id; // Nullable because it's null before insertion (DB assigns it)
  final String name;
  final String email;
  final int? age;
  final bool isActive;
  final DateTime createdAt;

  // Constructor
  const User({
    this.id,
    required this.name,
    required this.email,
    this.age,
    this.isActive = true,
    required this.createdAt,
  });

  /// Convert a Map (from database) → User object
  /// WHY "factory"? → It creates a new User from external data.
  ///                   The data shape (Map) is different from the class shape.
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      name: map['name'] as String,
      email: map['email'] as String,
      age: map['age'] as int?,
      // SQLite stores bool as int (0 or 1), so we convert
      isActive: (map['is_active'] as int) == 1,
      // SQLite stores DateTime as TEXT, so we parse it back
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Convert User object → Map (for database insertion)
  /// WHY exclude 'id'? → The database auto-generates it (AUTOINCREMENT).
  ///                      If we include null id, it might cause issues.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id, // Only include id if it exists (for updates)
      'name': name,
      'email': email,
      'age': age,
      'is_active': isActive ? 1 : 0, // bool → int for SQLite
      'created_at': createdAt.toIso8601String(), // DateTime → String for SQLite
    };
  }

  /// Create a copy of this User with some fields changed
  /// WHY? → User objects are immutable (final fields).
  ///        To "change" a user, we create a new one with updated values.
  User copyWith({
    int? id,
    String? name,
    String? email,
    int? age,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      age: age ?? this.age,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, name: $name, email: $email, age: $age, '
        'isActive: $isActive, createdAt: $createdAt)';
  }
}

/// ──────────────────────────────────────
/// Using the Model with Database
/// ──────────────────────────────────────
Future<void> modelExample() async {
  final db = await openDatabase(
    join(await getDatabasesPath(), 'model_demo.db'),
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
  );

  // ── INSERT using model ──
  final newUser = User(
    name: 'Charlie',
    email: 'charlie@example.com',
    age: 25,
    createdAt: DateTime.now(),
  );
  final insertedId = await db.insert('users', newUser.toMap());
  log('Inserted user with id: $insertedId');

  // ── READ and convert to model ──
  final List<Map<String, dynamic>> maps = await db.query('users');
  final List<User> users = maps.map((map) => User.fromMap(map)).toList();
  // Now we have type-safe User objects!
  for (final user in users) {
    log(user.name); // Compile-time checked! No more typos.
    log(
      "Is Acitve:$user.isActive",
    ); // It's already a bool, no conversion needed.
  }

  // ── UPDATE using model ──
  final updatedUser = users.first.copyWith(name: 'Charlie Updated', age: 26);
  await db.update(
    'users',
    updatedUser.toMap(),
    where: 'id = ?',
    whereArgs: [updatedUser.id],
  );

  await db.close();
}
