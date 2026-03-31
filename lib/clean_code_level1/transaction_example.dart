import 'dart:developer';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// ============================================================
/// TRANSACTIONS — All or Nothing
/// ============================================================
///
/// WHAT: A transaction groups multiple database operations together.
///       Either ALL operations succeed, or NONE of them are applied.
///
/// WHY do we need this?
/// Imagine transferring money: Bank A -$100, Bank B +$100
///   - Without transaction: If app crashes after step 1, money disappears!
///   - With transaction: If anything fails, both steps are undone (rolled back)
///
/// WHEN to use:
///   1. Multiple related operations that must ALL succeed
///   2. Bulk inserts (MUCH faster — 100x or more!)
///   3. Any operation where partial completion would corrupt data
///
/// PERFORMANCE INSIGHT:
///   Without transaction: Each insert = 1 disk write (slow)
///   With transaction:    100 inserts = 1 disk write (fast!)
///   This is because SQLite wraps each individual operation
///   in its own mini-transaction by default. Explicit transactions
///   batch everything into one write.

Future<void> transactionExamples() async {
  final db = await openDatabase(
    join(await getDatabasesPath(), 'transaction_demo.db'),
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          balance REAL NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE transfer_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          from_account INTEGER NOT NULL,
          to_account INTEGER NOT NULL,
          amount REAL NOT NULL,
          transferred_at TEXT NOT NULL
        )
      ''');
    },
  );

  // Setup: Create two accounts
  await db.insert('accounts', {'name': 'Alice', 'balance': 1000.0});
  await db.insert('accounts', {'name': 'Bob', 'balance': 500.0});

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 1: Basic Transaction
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // Transfer $200 from Alice (id:1) to Bob (id:2)
  await db.transaction((Transaction txn) async {
    // IMPORTANT: Inside a transaction, use 'txn' NOT 'db'!
    // WHY? → 'txn' ensures all operations are part of the same transaction.
    //        Using 'db' would create separate operations outside the transaction.

    // Step 1: Deduct from Alice
    await txn.rawUpdate(
      'UPDATE accounts SET balance = balance - ? WHERE id = ?',
      [200.0, 1],
    );

    // Step 2: Add to Bob
    await txn.rawUpdate(
      'UPDATE accounts SET balance = balance + ? WHERE id = ?',
      [200.0, 2],
    );

    // Step 3: Log the transfer
    await txn.insert('transfer_log', {
      'from_account': 1,
      'to_account': 2,
      'amount': 200.0,
      'transferred_at': DateTime.now().toIso8601String(),
    });

    // If ANY of the above steps throws an error,
    // ALL three steps are rolled back automatically!
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 2: Transaction with Return Value
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // Transactions can return values!
  final bool transferSuccess = await db.transaction((txn) async {
    // Check if Alice has enough balance
    final result = await txn.query(
      'accounts',
      columns: ['balance'],
      where: 'id = ?',
      whereArgs: [1],
    );
    final double balance = result.first['balance'] as double;

    if (balance < 500) {
      // Not enough funds — we can simply return false.
      // The transaction will still commit (no error was thrown),
      // but we didn't modify anything.
      return false;
    }

    await txn.rawUpdate(
      'UPDATE accounts SET balance = balance - 500 WHERE id = ?',
      [1],
    );
    await txn.rawUpdate(
      'UPDATE accounts SET balance = balance + 500 WHERE id = ?',
      [2],
    );
    return true;
  });
  log('Transfer successful: $transferSuccess');

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 3: Transaction Rollback on Error
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  try {
    await db.transaction((txn) async {
      await txn.insert('accounts', {'name': 'Charlie', 'balance': 100.0});

      // Simulate an error
      throw Exception('Something went wrong!');

      // This line never executes, AND the insert above is rolled back!
      // ignore: dead_code
      await txn.insert('accounts', {'name': 'Dave', 'balance': 200.0});
    });
  } catch (e) {
    log('Transaction rolled back: $e');
    // Charlie was NOT inserted because the transaction was rolled back
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Example 4: Bulk Insert (Performance)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // SLOW: 1000 inserts without transaction (1000 disk writes)
  final slowStart = DateTime.now();
  for (int i = 0; i < 100; i++) {
    await db.insert('accounts', {'name': 'User$i', 'balance': 0});
  }
  log('Without transaction: ${DateTime.now().difference(slowStart)}');

  // FAST: 1000 inserts with transaction (1 disk write)
  final fastStart = DateTime.now();
  await db.transaction((txn) async {
    for (int i = 100; i < 200; i++) {
      await txn.insert('accounts', {'name': 'User$i', 'balance': 0});
    }
  });
  log('With transaction: ${DateTime.now().difference(fastStart)}');
  // The transaction version is typically 10-100x faster!

  await db.close();
}
