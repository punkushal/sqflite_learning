import 'dart:developer';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

Future<void> myFirstDatabase() async {
  // Get path where the databases stored on the device
  final String dbPath = await getDatabasesPath();

  // Create a full path including our database file name
  final String path = join(dbPath, "my_first.db");

  // Open (or create) the database
  // WHY version: 1? → This tells sqflite which "version" of your
  //                    database schema this is. When you change your
  //                    tables later, you increment this number.
  //                    sqflite uses it to decide whether to call
  //                    onCreate or onUpgrade.
  final tabelName = "notes";
  final Database database = await openDatabase(
    path,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        create table $tabelName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          content TEXT,
          created_at TEXT NOT NULL
        )
        ''');
      // AUTOINCREMENT → SQLite automatically assigns 1, 2, 3... to id
      // TEXT NOT NULL  → This column MUST have a value, can't be empty
      // TEXT (without NOT NULL) → This column CAN be empty (null)
    },
  );

  // insert a row
  await database.insert(tabelName, {
    'title': 'first note',
    'content': 'learning sqflite basic',
    'created_at': DateTime.now().toIso8601String(),
  });

  // read all rows
  final results = await database.query(tabelName);

  log("Results: $results");

  // Always close when done (in real apps, we manage this differently)
  await database.close();
}
