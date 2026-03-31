import 'dart:developer';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// ============================================================
/// BATCH OPERATIONS — Fire and Forget (or Collect Results)
/// ============================================================
///
/// WHAT: A Batch queues up multiple operations and executes them
///       all at once. Similar to transactions but different:
///
/// TRANSACTION vs BATCH:
/// ┌──────────────────┬────────────────────────────────────────┐
/// │ Transaction      │ Batch                                  │
/// ├──────────────────┼────────────────────────────────────────┤
/// │ Awaits each op   │ Queues ops, executes all at commit     │
/// │ Can read results │ Results available only after commit    │
/// │ between ops      │                                        │
/// │ All or nothing   │ Can choose: all-or-nothing OR continue │
/// │ (rollback)       │ on error                               │
/// └──────────────────┴────────────────────────────────────────┘
///
/// WHEN to use Batch:
///   - Bulk inserts where you don't need intermediate results
///   - Initial data seeding
///   - When operations are independent of each other

Future<void> batchExamples() async {
  final db = await openDatabase(
    join(await getDatabasesPath(), 'batch_demo.db'),
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          price REAL NOT NULL
        )
      ''');
    },
  );

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 1: Basic Batch Insert
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  final Batch batch = db.batch();

  // Queue up operations (nothing is executed yet!)
  batch.insert('products', {'name': 'Apple', 'price': 1.50});
  batch.insert('products', {'name': 'Banana', 'price': 0.75});
  batch.insert('products', {'name': 'Cherry', 'price': 3.00});
  batch.insert('products', {'name': 'Date', 'price': 5.00});
  batch.insert('products', {'name': 'Elderberry', 'price': 8.00});

  // Execute all queued operations at once
  // Returns a list of results (one per operation)
  final List<dynamic> results = await batch.commit();
  log('Inserted IDs: $results'); // [1, 2, 3, 4, 5]

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 2: Batch with noResult (Performance)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  final batch2 = db.batch();
  for (int i = 0; i < 1000; i++) {
    batch2.insert('products', {'name': 'Product $i', 'price': i * 1.5});
  }

  // noResult: true → Don't bother collecting results
  // WHY? → Slightly faster because it doesn't need to track return values
  // Use when you don't need the inserted IDs
  await batch2.commit(noResult: true);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 3: Batch with continueOnError
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  final batch3 = db.batch();
  batch3.insert('products', {'name': 'Valid Product', 'price': 10.0});
  // This might fail if there's a constraint violation:
  batch3.insert('products', {'name': null, 'price': 10.0}); // name is NOT NULL!
  batch3.insert('products', {'name': 'Another Valid', 'price': 20.0});

  // Without continueOnError: The entire batch fails at the second insert
  // With continueOnError: Second insert fails, but first and third succeed
  try {
    await batch3.commit(continueOnError: true);
  } catch (e) {
    log('Batch error: $e');
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 4: Batch inside Transaction
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // You can use batches inside transactions for ultimate performance + safety
  await db.transaction((txn) async {
    final batch = txn.batch(); // Note: txn.batch(), not db.batch()

    for (int i = 0; i < 500; i++) {
      batch.insert('products', {'name': 'TxnProduct $i', 'price': i * 2.0});
    }

    await batch.commit(noResult: true);
    // If anything fails, the entire transaction (including all batch ops)
    // is rolled back
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 5: Mixed Batch Operations
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  final mixedBatch = db.batch();

  // You can mix different operations in a single batch
  mixedBatch.insert('products', {'name': 'New Product', 'price': 15.0});
  mixedBatch.update(
    'products',
    {'price': 2.00},
    where: 'name = ?',
    whereArgs: ['Apple'],
  );
  mixedBatch.delete('products', where: 'price > ?', whereArgs: [100.0]);

  // All three operations execute together
  await mixedBatch.commit();

  await db.close();
}
