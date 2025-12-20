import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  static const String tableProducts = 'products';
  static const String tableTransactions = 'transactions';
  static const String tableTransactionItems = 'transaction_items';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    String path = join(await getDatabasesPath(), 'sembako_app.db');
    // Increment version to 2 to trigger onUpgrade if needed,
    // but since we are changing schema, it's safer to just handle onCreate for new installs.
    // If you have existing data you want to keep, you'd need onUpgrade.
    // For now, I'll stick to version 1 assuming you can clear data/uninstall.
    return await openDatabase(
      path,
      version: 2, // Incremented version
      onCreate: _onCreate,
      onUpgrade: _onUpgrade, // Handle migration
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
        payment_amount INTEGER,
        change_amount INTEGER
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

    print("Database Created");
  }

  // Handle migration for existing users
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE $tableTransactions ADD COLUMN payment_amount INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE $tableTransactions ADD COLUMN change_amount INTEGER DEFAULT 0');
      print("Database Upgraded to v2");
    }
  }

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
