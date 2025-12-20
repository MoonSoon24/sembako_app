import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  // Existing Tables
  static const String tableProducts = 'products';
  static const String tableTransactions = 'transactions';
  static const String tableTransactionItems = 'transaction_items';

  // NEW TABLES for Option B (Offline History & PayLater)
  static const String tableCachedOrders = 'cached_orders';
  static const String tableCachedOrderItems = 'cached_order_items';
  static const String tablePendingPayLater = 'pending_paylater_payments';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    String path = join(await getDatabasesPath(), 'sembako_app.db');
    return await openDatabase(
      path,
      version: 3, // Incremented to v3
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Existing Tables
    await db.execute('''
      CREATE TABLE $tableProducts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT,
        stok INTEGER,
        hargaJual INTEGER,
        hargaBeli INTEGER,
        kategori TEXT,
        tanggalKadaluwarsa TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTransactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_date TEXT,
        total_amount INTEGER,
        payment_method TEXT,
        customer_name TEXT,
        is_paylater INTEGER,
        paylater_due_date TEXT,
        payment_amount INTEGER DEFAULT 0,
        change_amount INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTransactionItems(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER,
        product_name TEXT,
        quantity INTEGER,
        price_at_transaction INTEGER,
        subtotal INTEGER,
        FOREIGN KEY(transaction_id) REFERENCES $tableTransactions(id)
      )
    ''');

    // 2. NEW Tables for History Cache
    await _createHistoryTables(db);

    // 3. NEW Table for Pending PayLater Payments (Option B)
    await _createPendingPayLaterTable(db);

    print("Database Created");
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 to v2 migration
      await db.execute(
          'ALTER TABLE $tableTransactions ADD COLUMN payment_amount INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE $tableTransactions ADD COLUMN change_amount INTEGER DEFAULT 0');
      print("Database Upgraded to v2");
    }

    if (oldVersion < 3) {
      // v2 to v3 migration
      await _createHistoryTables(db);
      await _createPendingPayLaterTable(db);
      print("Database Upgraded to v3");
    }
  }

  // Helper to create history cache tables
  Future<void> _createHistoryTables(Database db) async {
    await db.execute('''
      CREATE TABLE $tableCachedOrders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderID TEXT UNIQUE,
        timestamp TEXT,
        userName TEXT,
        totalPrice INTEGER,
        paymentAmount INTEGER,
        paymentMethod TEXT,
        change INTEGER,
        status TEXT,
        totalMargin INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableCachedOrderItems(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderID TEXT,
        nama TEXT,
        qty INTEGER,
        pricePerItem INTEGER,
        hargaBeli INTEGER,
        kategori TEXT,
        FOREIGN KEY(orderID) REFERENCES $tableCachedOrders(orderID) ON DELETE CASCADE
      )
    ''');
  }

  // Helper to create pending paylater table
  Future<void> _createPendingPayLaterTable(Database db) async {
    await db.execute('''
      CREATE TABLE $tablePendingPayLater(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderID TEXT UNIQUE,
        timestamp TEXT
      )
    ''');
  }

  // --- CRUD Helpers ---

  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAll(String table) async {
    final db = await database;
    return await db.query(table);
  }

  Future<int> update(String table, Map<String, dynamic> data, int id) async {
    final db = await database;
    return await db.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String table, int id) async {
    final db = await database;
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}
