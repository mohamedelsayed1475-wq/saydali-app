import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'saydali_pro.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // إنشاء جداول الأكواد والإعلانات لو مش موجودة (ترقية من v1)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS subscription_codes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT UNIQUE NOT NULL,
          plan TEXT NOT NULL,
          duration_days INTEGER NOT NULL,
          discount_percent INTEGER DEFAULT 0,
          max_uses INTEGER DEFAULT 1,
          used_count INTEGER DEFAULT 0,
          device_id TEXT,
          is_active INTEGER DEFAULT 1,
          expires_at TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ads (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          image_url TEXT,
          link TEXT,
          button_text TEXT DEFAULT 'التفاصيل',
          is_active INTEGER DEFAULT 1,
          screen TEXT DEFAULT 'home',
          skip_duration INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      // إضافة تاريخ الاستحقاق للعملاء
      try {
        await db.execute('ALTER TABLE customers ADD COLUMN due_date TEXT');
      } catch (_) {}
      // جدول الفواتير
      await db.execute('''
        CREATE TABLE IF NOT EXISTS invoices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER,
          customer_name TEXT NOT NULL,
          items TEXT NOT NULL,
          subtotal REAL NOT NULL,
          discount REAL DEFAULT 0,
          total REAL NOT NULL,
          notes TEXT,
          created_at TEXT NOT NULL
        )
      ''');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // جدول النواقص
    await db.execute('''
      CREATE TABLE shortages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        company TEXT DEFAULT 'غير محدد',
        quantity INTEGER DEFAULT 1,
        status TEXT DEFAULT 'pending',
        is_urgent INTEGER DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // جدول المندوبين
    await db.execute('''
      CREATE TABLE representatives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        company TEXT,
        phone TEXT,
        rating INTEGER DEFAULT 5,
        total_covered INTEGER DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // جدول ردود المندوبين
    await db.execute('''
      CREATE TABLE rep_responses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rep_id INTEGER NOT NULL,
        shortage_id INTEGER NOT NULL,
        price REAL,
        discount REAL DEFAULT 0,
        available INTEGER DEFAULT 1,
        notes TEXT,
        responded_at TEXT NOT NULL,
        FOREIGN KEY (rep_id) REFERENCES representatives(id),
        FOREIGN KEY (shortage_id) REFERENCES shortages(id)
      )
    ''');

    // جدول العملاء والديون
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        total_debt REAL DEFAULT 0,
        due_date TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // جدول الفواتير
    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        customer_name TEXT NOT NULL,
        items TEXT NOT NULL,
        subtotal REAL NOT NULL,
        discount REAL DEFAULT 0,
        total REAL NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // جدول معاملات الديون
    await db.execute('''
      CREATE TABLE debt_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        description TEXT,
        transaction_date TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // جدول إعدادات التطبيق
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // جدول الأكواد (للمزامنة المحلية والتحقق)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS subscription_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        plan TEXT NOT NULL,
        duration_days INTEGER NOT NULL,
        discount_percent INTEGER DEFAULT 0,
        max_uses INTEGER DEFAULT 1,
        used_count INTEGER DEFAULT 0,
        device_id TEXT,
        is_active INTEGER DEFAULT 1,
        expires_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // جدول الإعلانات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        image_url TEXT,
        link TEXT,
        button_text TEXT DEFAULT 'التفاصيل',
        is_active INTEGER DEFAULT 1,
        screen TEXT DEFAULT 'home',
        skip_duration INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // إضافة إعدادات افتراضية
    await db.insert('settings', {'key': 'pharmacy_name', 'value': 'صيدليتي'});
    await db.insert('settings', {'key': 'pharmacist_name', 'value': 'الصيدلي'});
    await db.insert('settings', {'key': 'theme_color', 'value': '00C896'});
    await db.insert('settings', {'key': 'notifications_enabled', 'value': '1'});
  }

  // ── النواقص ──────────────────────────────────────────────────
  Future<int> insertShortage(Map<String, dynamic> data) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    data['created_at'] = now;
    data['updated_at'] = now;
    return await db.insert('shortages', data);
  }

  Future<List<Map<String, dynamic>>> getShortages({String? status}) async {
    final db = await database;
    if (status != null) {
      return await db.query('shortages',
          where: 'status = ?', whereArgs: [status], orderBy: 'created_at DESC');
    }
    return await db.query('shortages',
        orderBy: 'is_urgent DESC, created_at DESC');
  }

  Future<int> updateShortage(int id, Map<String, dynamic> data) async {
    final db = await database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return await db.update('shortages', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteShortage(int id) async {
    final db = await database;
    return await db.delete('shortages', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, int>> getShortageStats() async {
    final db = await database;
    final total = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM shortages')) ??
        0;
    final covered = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM shortages WHERE status='covered'")) ??
        0;
    final offered = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM shortages WHERE status='offered'")) ??
        0;
    final pending = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM shortages WHERE status='pending'")) ??
        0;
    final stubborn = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM shortages WHERE status='stubborn'")) ??
        0;
    return {
      'total': total,
      'pending': pending,
      'offered': offered,
      'covered': covered,
      'stubborn': stubborn,
    };
  }

  Future<void> autoCloseOldPendingShortages() async {
    final db = await database;
    final twentyFourHoursAgo =
        DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
    await db.rawUpdate(
      "UPDATE shortages SET status = 'stubborn' WHERE status = 'pending' AND created_at <= ?",
      [twentyFourHoursAgo],
    );
  }

  // ── المندوبين ──────────────────────────────────────────────────
  Future<int> insertRep(Map<String, dynamic> data) async {
    final db = await database;
    data['created_at'] = DateTime.now().toIso8601String();
    return await db.insert('representatives', data);
  }

  Future<List<Map<String, dynamic>>> getReps() async {
    final db = await database;
    return await db.query('representatives',
        orderBy: 'rating DESC, total_covered DESC');
  }

  Future<int> updateRep(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db
        .update('representatives', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteRep(int id) async {
    final db = await database;
    return await db.delete('representatives', where: 'id = ?', whereArgs: [id]);
  }

  // ── العملاء والديون ──────────────────────────────────────────────────
  Future<int> insertCustomer(Map<String, dynamic> data) async {
    final db = await database;
    data['created_at'] = DateTime.now().toIso8601String();
    data['total_debt'] = 0.0;
    return await db.insert('customers', data);
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;
    return await db.query('customers', orderBy: 'total_debt DESC');
  }

  Future<int> updateCustomer(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update('customers', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    await db
        .delete('debt_transactions', where: 'customer_id = ?', whereArgs: [id]);
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addDebtTransaction(Map<String, dynamic> data) async {
    final db = await database;
    data['transaction_date'] = DateTime.now().toIso8601String();
    final txId = await db.insert('debt_transactions', data);

    // تحديث إجمالي الدين
    final customer = await db
        .query('customers', where: 'id = ?', whereArgs: [data['customer_id']]);
    if (customer.isNotEmpty) {
      double currentDebt = (customer.first['total_debt'] as num).toDouble();
      double amount = (data['amount'] as num).toDouble();
      double newDebt =
          data['type'] == 'debt' ? currentDebt + amount : currentDebt - amount;
      await db.update('customers', {'total_debt': newDebt},
          where: 'id = ?', whereArgs: [data['customer_id']]);
    }
    return txId;
  }

  Future<List<Map<String, dynamic>>> getCustomerTransactions(
      int customerId) async {
    final db = await database;
    return await db.query('debt_transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'transaction_date DESC');
  }

  Future<double> getTotalDebt() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT SUM(total_debt) as total FROM customers');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ── الإعدادات ──────────────────────────────────────────────────
  Future<String?> getSetting(String key) async {
    final db = await database;
    final result =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return result.isNotEmpty ? result.first['value'] as String : null;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getActiveAd(String screen) async {
    final db = await database;
    try {
      final result = await db.query('ads',
          where: 'is_active = 1 AND screen = ?', whereArgs: [screen], limit: 1);
      if (result.isNotEmpty) return result.first;
    } catch (_) {}
    return null;
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final result = await db.query('settings');
    return {
      for (var row in result) row['key'] as String: row['value'] as String
    };
  }

  /// جلب رمز العملة (ج.م، ر.س، إلخ)
  Future<String> getCurrency() async {
    return await getSetting('currency_symbol') ?? 'ج.م';
  }

  /// جلب كود الدولة (EG، SA، إلخ)
  Future<String> getCountryCode() async {
    return await getSetting('country_code') ?? 'EG';
  }

  // ── الديون المستحقة ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getDueDebts() async {
    final db = await database;
    final tomorrow = DateTime.now().add(const Duration(days: 1)).toIso8601String().substring(0, 10);
    return await db.query('customers',
        where: "due_date IS NOT NULL AND due_date <= ? AND total_debt > 0",
        whereArgs: [tomorrow],
        orderBy: 'due_date ASC');
  }

  // ── الفواتير ──────────────────────────────────────────────────
  Future<int> insertInvoice(Map<String, dynamic> data) async {
    final db = await database;
    data['created_at'] = DateTime.now().toIso8601String();
    return await db.insert('invoices', data);
  }

  Future<List<Map<String, dynamic>>> getInvoices() async {
    final db = await database;
    return await db.query('invoices', orderBy: 'created_at DESC');
  }
}
