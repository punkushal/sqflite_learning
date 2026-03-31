import 'dart:developer';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// ============================================================
/// INDEXING — Making Queries Fast
/// ============================================================
///
/// WHAT is an index?
/// Think of it like the index at the back of a book.
/// Without an index: You search page by page (SLOW for big books)
/// With an index:    You look up the page number directly (FAST)
///
/// HOW it works in databases:
/// Without index: SQLite scans EVERY row to find matches ("full table scan")
/// With index:    SQLite uses a B-tree structure to jump directly to matches
///
/// ┌────────────────────────────────────────────────────────────────┐
/// │ WHEN TO USE an index:                                          │
/// ├────────────────────────────────────────────────────────────────┤
/// │ ✅ Columns frequently used in WHERE clauses                    │
/// │ ✅ Columns used in ORDER BY                                    │
/// │ ✅ Columns used in JOIN conditions                             │
/// │ ✅ Columns with high cardinality (many unique values)          │
/// │    Example: email, user_id, timestamps                          │
/// ├────────────────────────────────────────────────────────────────┤
/// │ WHEN NOT TO USE an index:                                     │
/// ├────────────────────────────────────────────────────────────────┤
/// │ ❌ Small tables (< 1000 rows) — overhead isn't worth it       │
/// │ ❌ Columns with low cardinality (few unique values)            │
/// │    Example: is_active (only 0 or 1) — index doesn't help much │
/// │ ❌ Tables with heavy INSERT/UPDATE operations                  │
/// │    (indexes slow down writes because they need updating too)   │
/// │ ❌ Columns rarely used in queries                              │
/// └────────────────────────────────────────────────────────────────┘
///
/// TRADE-OFF:
///   Indexes make READS faster but WRITES slower.
///   Each insert/update/delete must also update the index.
///   They also use extra disk space.

Future<void> indexingExamples() async {
  final db = await openDatabase(
    join(await getDatabasesPath(), 'index_demo.db'),
    version: 1,
    onCreate: (db, version) async {
      // Create the table
      await db.execute('''
        CREATE TABLE orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          product_name TEXT NOT NULL,
          amount REAL NOT NULL,
          status TEXT NOT NULL,
          order_date TEXT NOT NULL,
          region TEXT NOT NULL
        )
      ''');

      // ── Index Type 1: Single Column Index ──
      // WHY? We frequently query: "Show me all orders for customer X"
      // SQL: SELECT * FROM orders WHERE customer_id = ?
      await db.execute('''
        CREATE INDEX idx_orders_customer_id ON orders(customer_id)
      ''');
      // Naming convention: idx_{table}_{column}
      // This creates a B-tree on customer_id for fast lookups

      // ── Index Type 2: Unique Index ──
      // Ensures no duplicate values (like UNIQUE constraint + faster lookups)
      // Example: If each order has a unique tracking number
      // await db.execute('''
      //   CREATE UNIQUE INDEX idx_orders_tracking ON orders(tracking_number)
      // ''');

      // ── Index Type 3: Composite (Multi-Column) Index ──
      // WHY? We frequently query: "Show orders for customer X with status Y"
      // SQL: SELECT * FROM orders WHERE customer_id = ? AND status = ?
      await db.execute('''
        CREATE INDEX idx_orders_customer_status 
        ON orders(customer_id, status)
      ''');
      // IMPORTANT: Column order matters!
      // This index helps with:
      //   ✅ WHERE customer_id = ?                    (leftmost column)
      //   ✅ WHERE customer_id = ? AND status = ?     (both columns)
      //   ❌ WHERE status = ?                         (not leftmost!)
      //
      // Think of it like a phone book sorted by (LastName, FirstName):
      //   ✅ Find all "Smith" → Easy (sorted by last name)
      //   ✅ Find "Smith, John" → Easy (sorted by last, then first)
      //   ❌ Find all "John" → Hard (not sorted by first name alone)

      // ── Index Type 4: Index for sorting ──
      // WHY? We frequently sort by order_date
      // SQL: SELECT * FROM orders ORDER BY order_date DESC
      await db.execute('''
        CREATE INDEX idx_orders_date ON orders(order_date DESC)
      ''');
    },
  );

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Seed data for testing
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  await db.transaction((txn) async {
    for (int i = 0; i < 10000; i++) {
      await txn.insert('orders', {
        'customer_id': i % 100, // 100 different customers
        'product_name': 'Product ${i % 50}',
        'amount': (i * 1.5) % 1000,
        'status': ['pending', 'shipped', 'delivered'][i % 3],
        'order_date': DateTime(
          2024,
          1,
          1,
        ).add(Duration(hours: i)).toIso8601String(),
        'region': ['north', 'south', 'east', 'west'][i % 4],
      });
    }
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Using EXPLAIN QUERY PLAN to verify index usage
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // This shows HOW SQLite will execute the query
  // Look for "USING INDEX" in the output

  final plan1 = await db.rawQuery(
    'EXPLAIN QUERY PLAN SELECT * FROM orders WHERE customer_id = ?',
    [42],
  );
  log('Query plan (indexed): $plan1');
  // Should show: SEARCH TABLE orders USING INDEX idx_orders_customer_id

  final plan2 = await db.rawQuery(
    'EXPLAIN QUERY PLAN SELECT * FROM orders WHERE region = ?',
    ['north'],
  );
  log('Query plan (no index): $plan2');
  // Should show: SCAN TABLE orders (full table scan — slow!)

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Performance comparison
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // FAST (uses index on customer_id)
  var start = DateTime.now();
  await db.query('orders', where: 'customer_id = ?', whereArgs: [42]);
  log('Indexed query: ${DateTime.now().difference(start).inMicroseconds}μs');

  // SLOW (no index on region — full table scan)
  start = DateTime.now();
  await db.query('orders', where: 'region = ?', whereArgs: ['north']);
  log(
    'Non-indexed query: ${DateTime.now().difference(start).inMicroseconds}μs',
  );

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Managing indexes
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // Drop an index (if you decide it's not helping)
  // await db.execute('DROP INDEX IF EXISTS idx_orders_date');

  // List all indexes on a table
  final indexes = await db.rawQuery(
    "SELECT * FROM sqlite_master WHERE type = 'index' AND tbl_name = 'orders'",
  );
  for (final idx in indexes) {
    log('Index: ${idx['name']} → SQL: ${idx['sql']}');
  }

  await db.close();
}
