import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../utils/security_helper.dart';

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
      version: 19,
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
    if (oldVersion < 4) {
      // ── جدول المساعدين ──
      await db.execute('''
        CREATE TABLE IF NOT EXISTS assistants (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          pin TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'assistant',
          can_add_debt INTEGER DEFAULT 1,
          can_edit_debt INTEGER DEFAULT 0,
          can_delete INTEGER DEFAULT 0,
          can_view_reports INTEGER DEFAULT 0,
          can_manage_invoices INTEGER DEFAULT 1,
          is_active INTEGER DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');
      // ── جدول سجل الأنشطة ──
      await db.execute('''
        CREATE TABLE IF NOT EXISTS activity_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          assistant_id INTEGER,
          assistant_name TEXT NOT NULL,
          action TEXT NOT NULL,
          details TEXT,
          screen TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (assistant_id) REFERENCES assistants(id)
        )
      ''');
    }
    if (oldVersion < 5) {
      // ── أعمدة المزامنة السحابية ──
      final syncTables = ['shortages', 'customers', 'invoices', 'debt_transactions'];
      for (final table in syncTables) {
        try { await db.execute('ALTER TABLE $table ADD COLUMN cloud_id TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE $table ADD COLUMN is_synced INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE $table ADD COLUMN created_by TEXT'); } catch (_) {}
      }
    }
    if (oldVersion < 6) {
      // ── أعمدة صلاحيات جديدة ──
      try { await db.execute('ALTER TABLE assistants ADD COLUMN can_manage_shortages INTEGER DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE assistants ADD COLUMN can_manage_reps INTEGER DEFAULT 0'); } catch (_) {}
    }
    if (oldVersion < 7) {
      // ── إضافة صور العملاء وإيصالات الديون ──
      try { await db.execute('ALTER TABLE customers ADD COLUMN photo_url TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE debt_transactions ADD COLUMN receipt_url TEXT'); } catch (_) {}
    }
    if (oldVersion < 8) {
      // ── جدول طلبات المندوبين ──
      await db.execute('''
        CREATE TABLE IF NOT EXISTS rep_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          rep_name TEXT NOT NULL,
          items TEXT NOT NULL,
          total REAL NOT NULL,
          is_paid INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      // ── جدول مرتجعات المندوبين ──
      await db.execute('''
        CREATE TABLE IF NOT EXISTS rep_returns (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          rep_name TEXT NOT NULL,
          item_name TEXT NOT NULL,
          reason TEXT NOT NULL,
          reminder_time TEXT,
          is_returned INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 9) {
      // إضافة أعمدة المبلغ المدفوع والمتبقي للفواتير
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN paid_amount REAL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN remaining REAL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 10) {
      // إضافة تاريخ انتهاء الإعلانات
      try {
        await db.execute('ALTER TABLE ads ADD COLUMN expires_at TEXT');
      } catch (_) {}
    }
    if (oldVersion < 11) {
      // إضافة الدولة المستهدفة للإعلانات
      try {
        await db.execute('ALTER TABLE ads ADD COLUMN target_country TEXT');
      } catch (_) {}
    }
    if (oldVersion < 12) {
      // إضافة أعمدة اشتراك المساعدين
      try {
        await db.execute('ALTER TABLE assistants ADD COLUMN subscription_expiry TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE assistants ADD COLUMN subscription_duration_days INTEGER DEFAULT 30');
      } catch (_) {}
    }
    if (oldVersion < 13) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS medication_expiries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            quantity INTEGER NOT NULL DEFAULT 1,
            expiry_date TEXT NOT NULL,
            supplier_name TEXT,
            notes TEXT,
        cloud_id TEXT,
        is_synced INTEGER DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            amount REAL NOT NULL,
            description TEXT,
            expense_date TEXT NOT NULL,
            created_by TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS alternatives (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            medication_name TEXT NOT NULL,
            alternative_name TEXT NOT NULL,
            active_ingredient TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 14) {
      // إضافة عمود الدولة لجدول البدائل
      try {
        await db.execute("ALTER TABLE alternatives ADD COLUMN country_code TEXT DEFAULT 'EG'");
      } catch (_) {}
      // تحديث السجلات القديمة بالدولة الافتراضية
      try {
        await db.execute("UPDATE alternatives SET country_code = 'EG' WHERE country_code IS NULL");
      } catch (_) {}
    }
    if (oldVersion < 15) {
      // إضافة cloud_id للمساعدين
      try {
        await db.execute("ALTER TABLE assistants ADD COLUMN cloud_id TEXT");
      } catch (_) {}
    }
    if (oldVersion < 16) {
      try {
        await db.execute('ALTER TABLE rep_orders ADD COLUMN created_by TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE rep_returns ADD COLUMN created_by TEXT');
      } catch (_) {}
    }
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS used_activation_codes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT UNIQUE NOT NULL,
          used_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 18) {
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_shortages_status ON shortages(status)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_shortages_created ON shortages(created_at DESC)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_debt_customer ON debt_transactions(customer_id)'); } catch (_) {}
      try { await db.execute("ALTER TABLE assistants ADD COLUMN updated_at TEXT"); } catch (_) {}
      try { await db.execute("ALTER TABLE customers ADD COLUMN updated_at TEXT"); } catch (_) {}
    }
    if (oldVersion < 19) {
      // ── جداول الجرد والمخزون ──
      await db.execute('''
        CREATE TABLE IF NOT EXISTS inventory_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'in_progress',
          total_items INTEGER DEFAULT 0,
          counted_items INTEGER DEFAULT 0,
          matched_items INTEGER DEFAULT 0,
          surplus_items INTEGER DEFAULT 0,
          deficit_items INTEGER DEFAULT 0,
          notes TEXT,
          created_by TEXT,
          created_at TEXT NOT NULL,
          completed_at TEXT,
          cloud_id TEXT,
          is_synced INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS inventory_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          barcode TEXT,
          system_quantity REAL DEFAULT 0,
          actual_quantity REAL,
          difference REAL,
          status TEXT DEFAULT 'pending',
          counted_by TEXT,
          counted_at TEXT,
          review_status TEXT DEFAULT 'pending',
          notes TEXT,
          cloud_id TEXT,
          is_synced INTEGER DEFAULT 0,
          FOREIGN KEY (session_id) REFERENCES inventory_sessions(id) ON DELETE CASCADE
        )
      ''');
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_inv_items_session ON inventory_items(session_id)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_inv_items_status ON inventory_items(status)'); } catch (_) {}
    }
  }

  /// حذف الإعلانات المنتهية تلقائياً
  Future<int> cleanupExpiredAds() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return await db.delete('ads',
        where: "expires_at IS NOT NULL AND expires_at != '' AND expires_at < ?",
        whereArgs: [now]);
  }

  // ── Activation code single-use tracking ───────────────────────────────────

  /// Returns true if this code has already been used on this device.
  Future<bool> isActivationCodeUsed(String code) async {
    final db = await database;
    final rows = await db.query(
      'used_activation_codes',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Marks [code] as used so it cannot be reused.
  Future<void> markActivationCodeUsed(String code) async {
    final db = await database;
    await db.insert(
      'used_activation_codes',
      {
        'code': code,
        'used_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
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
        cloud_id TEXT,
        is_synced INTEGER DEFAULT 0,
        created_by TEXT,
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
        cloud_id TEXT,
        photo_url TEXT,
        is_synced INTEGER DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
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
        paid_amount REAL DEFAULT 0,
        remaining REAL DEFAULT 0,
        notes TEXT,
        cloud_id TEXT,
        is_synced INTEGER DEFAULT 0,
        created_by TEXT,
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
        cloud_id TEXT,
        receipt_url TEXT,
        is_synced INTEGER DEFAULT 0,
        created_by TEXT,
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

    // جدول طلبات المندوبين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rep_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rep_name TEXT NOT NULL,
        items TEXT NOT NULL,
        total REAL NOT NULL,
        is_paid INTEGER DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // جدول مرتجعات المندوبين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rep_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rep_name TEXT NOT NULL,
        item_name TEXT NOT NULL,
        reason TEXT NOT NULL,
        reminder_time TEXT,
        is_returned INTEGER DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL
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
        expires_at TEXT,
        target_country TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // جدول المساعدين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assistants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        pin TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'assistant',
        can_add_debt INTEGER DEFAULT 1,
        can_edit_debt INTEGER DEFAULT 0,
        can_delete INTEGER DEFAULT 0,
        can_view_reports INTEGER DEFAULT 0,
        can_manage_invoices INTEGER DEFAULT 1,
        can_manage_shortages INTEGER DEFAULT 1,
        can_manage_reps INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        subscription_expiry TEXT,
        subscription_duration_days INTEGER DEFAULT 30,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    // جدول سجل الأنشطة
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        assistant_id INTEGER,
        assistant_name TEXT NOT NULL,
        action TEXT NOT NULL,
        details TEXT,
        screen TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id)
      )
    ''');

    // ── جدول تواريخ انتهاء الصلاحية ──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medication_expiries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        expiry_date TEXT NOT NULL,
        supplier_name TEXT,
        notes TEXT,
        cloud_id TEXT,
        is_synced INTEGER DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ── جدول المصروفات ──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        expense_date TEXT NOT NULL,
        created_by TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ── جدول بدائل الأدوية ──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alternatives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_name TEXT NOT NULL,
        alternative_name TEXT NOT NULL,
        active_ingredient TEXT,
        country_code TEXT DEFAULT 'EG',
        created_at TEXT NOT NULL
      )
    ''');

    // إضافة إعدادات افتراضية

    await db.insert('settings', {'key': 'pharmacist_name', 'value': 'الصيدلي'});
    await db.insert('settings', {'key': 'theme_color', 'value': '00C896'});
    await db.insert('settings', {'key': 'notifications_enabled', 'value': '1'});

    // جدول أكواد التفعيل المستخدمة (كل كود يشتغل مرة واحدة بس)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS used_activation_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        used_at TEXT NOT NULL
      )
    ''');

    // ── جداول الجرد والمخزون ──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'in_progress',
        total_items INTEGER DEFAULT 0,
        counted_items INTEGER DEFAULT 0,
        matched_items INTEGER DEFAULT 0,
        surplus_items INTEGER DEFAULT 0,
        deficit_items INTEGER DEFAULT 0,
        notes TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        cloud_id TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        barcode TEXT,
        system_quantity REAL DEFAULT 0,
        actual_quantity REAL,
        difference REAL,
        status TEXT DEFAULT 'pending',
        counted_by TEXT,
        counted_at TEXT,
        review_status TEXT DEFAULT 'pending',
        notes TEXT,
        cloud_id TEXT,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES inventory_sessions(id) ON DELETE CASCADE
      )
    ''');

    // ── الفهارس لتحسين أداء الاستعلامات ──
    await db.execute('CREATE INDEX IF NOT EXISTS idx_shortages_status ON shortages(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_shortages_created ON shortages(created_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_debt_customer ON debt_transactions(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inv_items_session ON inventory_items(session_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inv_items_status ON inventory_items(status)');
  }


  // ── النواقص ──────────────────────────────────────────────────
  Future<int> insertShortage(Map<String, dynamic> data) async {
    final db = await database;
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    final now = DateTime.now().toIso8601String();
    map['created_at'] = now;
    map['updated_at'] = now;
    map['created_by'] ??= await getCurrentUserName();
    map['cloud_id'] ??= SecurityHelper.generateUUID();
    map['is_synced'] = 0;
    return await db.insert('shortages', map);
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
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    map['updated_at'] = DateTime.now().toIso8601String();
    map.remove('created_by');
    map['is_synced'] = 0;
    return await db.update('shortages', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteShortage(int id) async {
    final db = await database;
    await db.delete('rep_responses', where: 'shortage_id = ?', whereArgs: [id]);
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
    // ✅ افحص الإعداد الأول
    final enabled = await getSetting('auto_close_enabled');
    if (enabled != '1') return; // مش مفعّل؟ وقف
    
    final db = await database;
    final hoursStr = await getSetting('auto_close_hours') ?? '24';
    final hours = int.tryParse(hoursStr) ?? 24;
    final cutoff = DateTime.now()
        .subtract(Duration(hours: hours))
        .toIso8601String();
        
    await db.rawUpdate(
      "UPDATE shortages SET status='stubborn' WHERE status='pending' AND created_at <= ?",
      [cutoff],
    );
  }

  Future<List<int>> getWeeklyShortages() async {
    final db = await database;
    final now = DateTime.now();
    final results = <int>[];
    
    for (int i = 3; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: (i + 1) * 7));
      final weekEnd = now.subtract(Duration(days: i * 7));
      final count = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM shortages WHERE created_at >= ? AND created_at < ?",
        [weekStart.toIso8601String(), weekEnd.toIso8601String()],
      )) ?? 0;
      results.add(count);
    }
    return results;
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
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    map['created_at'] = DateTime.now().toIso8601String();
    map['total_debt'] = 0.0;
    map['created_by'] ??= await getCurrentUserName();
    map['cloud_id'] ??= SecurityHelper.generateUUID();
    map['is_synced'] = 0;
    return await db.insert('customers', map);
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT c.*, 
        (
          SELECT COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE 0 END), 0) -
                 COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END), 0)
          FROM debt_transactions dt WHERE dt.customer_id = c.id
        ) as total_debt
      FROM customers c
      ORDER BY total_debt DESC
    ''');
  }

  Future<int> updateCustomer(int id, Map<String, dynamic> data) async {
    final db = await database;
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    map['created_by'] = await getCurrentUserName();
    map['is_synced'] = 0;
    return await db.update('customers', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    await db
        .delete('debt_transactions', where: 'customer_id = ?', whereArgs: [id]);
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addDebtTransaction(Map<String, dynamic> data) async {
    final db = await database;
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    map['transaction_date'] ??= DateTime.now().toIso8601String();
    map['created_by'] ??= await getCurrentUserName();
    map['cloud_id'] ??= SecurityHelper.generateUUID();
    map['is_synced'] = 0;
    final txId = await db.insert('debt_transactions', map);

    // ✅ احسب من الأول من جدول المعاملات (أكثر أمانًا)
    final result = await db.rawQuery(
      """SELECT 
          COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE 0 END), 0) -
          COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END), 0) 
          as net
         FROM debt_transactions WHERE customer_id = ?""",
      [map['customer_id']],
    );
    final newDebt = (result.first['net'] as num?)?.toDouble() ?? 0.0;

    // تحديث العميل مع تفعيل إعادة المزامنة
    await db.update(
      'customers',
      {'total_debt': newDebt < 0 ? 0.0 : newDebt, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [map['customer_id']],
    );
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
    final result = await db.rawQuery('''
      SELECT 
          COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE 0 END), 0) -
          COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END), 0) 
          as total
         FROM debt_transactions
    ''');
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

  /// إعادة ضبط بيانات الجهاز بالكامل (مسح التفعيل وإعدادات السحابة والجلسة)
  Future<void> resetDeviceAndActivationData() async {
    final db = await database;
    final keysToDelete = [
      'is_activated',
      'activation_code',
      'activation_date',
      'supabase_url',
      'supabase_key',
      'web_portal_url',
      'pharmacy_cloud_id',
      'pharmacy_code',
      'is_assistant_device',
      'logged_in_assistant_id',
      'logged_in_assistant_name',
      'assistant_session_token',
      'assistant_session_expiry',
      'last_sync_at',
      'last_local_sync_at',
    ];
    for (final k in keysToDelete) {
      await db.delete('settings', where: 'key = ?', whereArgs: [k]);
    }
    await db.delete('used_activation_codes');
  }

  Future<Map<String, dynamic>?> getActiveAd(String screen) async {
    final db = await database;
    try {
      // تنظيف الإعلانات المنتهية أولاً
      await cleanupExpiredAds();
      final now = DateTime.now().toIso8601String();
      final countryCode = await getCountryCode();
      final result = await db.query('ads',
          where: "is_active = 1 AND screen = ? AND (expires_at IS NULL OR expires_at = '' OR expires_at > ?) AND (target_country IS NULL OR target_country = '' OR target_country = ?)",
          whereArgs: [screen, now, countryCode],
          orderBy: "target_country DESC",
          limit: 1);
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

  /// عدد الأماكن المتاحة للمساعدين (كل كود assistant = 3 أماكن)
  Future<int> getAssistantSlots() async {
    final val = await getSetting('assistant_slots');
    return int.tryParse(val ?? '0') ?? 0;
  }

  /// عدد الأماكن الإضافية المفردة (من كود assistant_1)
  Future<int> getExtraAssistantSlots() async {
    final val = await getSetting('extra_assistant_slots');
    return int.tryParse(val ?? '0') ?? 0;
  }

  /// الحد الأقصى للأماكن الإضافية المفردة
  static const int maxExtraAssistantSlots = 3;

  /// التسعير التصاعدي للمساعد الإضافي
  static const List<int> extraAssistantPrices = [49, 99, 149];

  /// سعر المساعد الإضافي التالي بناءً على عدد الأماكن المفعلة
  static int getNextExtraPrice(int currentExtras) {
    if (currentExtras >= maxExtraAssistantSlots) return 0;
    return extraAssistantPrices[currentExtras];
  }

  /// إضافة أماكن مساعدين جديدة (عند تفعيل كود assistant)
  Future<void> addAssistantSlots(int count) async {
    final current = await getAssistantSlots();
    await setSetting('assistant_slots', '${current + count}');
    // تتبع الأماكن الإضافية المفردة
    if (count == 1) {
      final extras = await getExtraAssistantSlots();
      await setSetting('extra_assistant_slots', '${extras + 1}');
    }
  }

  /// عدد المساعدين النشطين حالياً
  Future<int> getActiveAssistantCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
        await db.rawQuery("SELECT COUNT(*) FROM assistants WHERE is_active = 1")) ?? 0;
  }

  /// جلب كود الدولة (EG، SA، إلخ)
  Future<String> getCountryCode() async {
    return await getSetting('country_code') ?? 'EG';
  }

  // ── الديون المستحقة ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getDueDebts() async {
    final db = await database;
    final tomorrow = DateTime.now().add(const Duration(days: 1)).toIso8601String().substring(0, 10);
    return await db.rawQuery('''
      SELECT * FROM (
        SELECT c.*, 
          (
            SELECT COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE 0 END), 0) -
                   COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END), 0)
            FROM debt_transactions dt WHERE dt.customer_id = c.id
          ) as total_debt
        FROM customers c
        WHERE c.due_date IS NOT NULL AND c.due_date <= ?
      )
      WHERE total_debt > 0
      ORDER BY due_date ASC
    ''', [tomorrow]);
  }

  // ── الفواتير ──────────────────────────────────────────────────
  // ── طلبات ومرتجعات المندوبين ──────────────────────────────────────────────────
  Future<int> insertRepOrder(Map<String, dynamic> data) async {
    final db = await database;
    final map = Map<String, dynamic>.from(data);
    map['created_at'] = map['created_at'] ?? DateTime.now().toIso8601String();
    map['created_by'] ??= await getCurrentUserName();
    return await db.insert('rep_orders', map);
  }

  Future<List<Map<String, dynamic>>> getRepOrders(String repName) async {
    final db = await database;
    return await db.query(
      'rep_orders',
      where: 'rep_name = ?',
      whereArgs: [repName],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllRepOrders({int? withinDays}) async {
    final db = await database;
    if (withinDays != null) {
      final cutoff = DateTime.now().subtract(Duration(days: withinDays)).toIso8601String();
      return await db.query('rep_orders',
          where: 'created_at >= ?',
          whereArgs: [cutoff],
          orderBy: 'created_at DESC');
    }
    return await db.query('rep_orders', orderBy: 'created_at DESC');
  }

  Future<int> updateRepOrderPaidStatus(int id, bool isPaid) async {
    final db = await database;
    return await db.update(
      'rep_orders',
      {'is_paid': isPaid ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRepOrder(int id) async {
    final db = await database;
    return await db.delete('rep_orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertRepReturn(Map<String, dynamic> data) async {
    final db = await database;
    final map = Map<String, dynamic>.from(data);
    map['created_at'] = map['created_at'] ?? DateTime.now().toIso8601String();
    map['created_by'] ??= await getCurrentUserName();
    return await db.insert('rep_returns', map);
  }

  Future<List<Map<String, dynamic>>> getRepReturns(String repName) async {
    final db = await database;
    return await db.query(
      'rep_returns',
      where: 'rep_name = ?',
      whereArgs: [repName],
      orderBy: 'created_at DESC',
    );
  }

  Future<int> updateRepReturnStatus(int id, bool isReturned) async {
    final db = await database;
    return await db.update(
      'rep_returns',
      {'is_returned': isReturned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRepReturn(int id) async {
    final db = await database;
    return await db.delete('rep_returns', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertInvoice(Map<String, dynamic> data) async {
    final db = await database;
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    map['created_at'] ??= DateTime.now().toIso8601String();
    map['created_by'] ??= await getCurrentUserName();
    map['cloud_id'] ??= SecurityHelper.generateUUID();
    map['is_synced'] = 0;
    return await db.insert('invoices', map);
  }

  Future<List<Map<String, dynamic>>> getInvoices() async {
    final db = await database;
    return await db.query('invoices', orderBy: 'created_at DESC');
  }

  Future<int> updateInvoice(int id, Map<String, dynamic> data) async {
    final db = await database;
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    map['created_by'] = await getCurrentUserName();
    map['is_synced'] = 0;
    return await db.update('invoices', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteInvoice(int id) async {
    final db = await database;
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  // ── المساعدين ────────────────────────────────────────────────────────────────
  Future<int> insertAssistant(Map<String, dynamic> data) async {
    final db = await database;
    final map = Map<String, dynamic>.from(data);
    final now = DateTime.now().toIso8601String();
    map['created_at'] = now;
    map['updated_at'] = now;
    map['subscription_duration_days'] ??= 30;
    map['subscription_expiry'] ??= DateTime.now()
        .add(Duration(days: map['subscription_duration_days'] as int))
        .toIso8601String();
    map['cloud_id'] ??= SecurityHelper.generateUUID();
    if (map['pin'] != null && !(map['pin'] as String).contains('\$')) {
      map['pin'] = SecurityHelper.hashPin(map['pin'] as String);
    }
    return await db.insert('assistants', map);
  }

  Future<void> clearAssistantSession() async {
    final db = await database;
    await db.delete('settings', where: "key IN ('logged_in_assistant_id', 'logged_in_assistant_name', 'assistant_session_token', 'assistant_session_expiry')");
  }

  Future<String> getCurrentUserName() async {
    final isAssistant = await getSetting('is_assistant_device');
    if (isAssistant == '1') {
      final name = await getSetting('logged_in_assistant_name');
      if (name != null && name.isNotEmpty) return name;
      return 'مساعد';
    }
    return 'المالك';
  }

  Future<List<Map<String, dynamic>>> getAssistants() async {
    final db = await database;
    return await db.query('assistants', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getAssistantByPin(String pin) async {
    final db = await database;
    
    // تأكيد وجود صيدلية مربوطة لضمان أمان تسجيل الدخول على أجهزة المساعدين
    final pharmacyCloudId = await getSetting('pharmacy_cloud_id');
    final isAssistant = await getSetting('is_assistant_device');
    if (isAssistant == '1' && (pharmacyCloudId == null || pharmacyCloudId.isEmpty)) {
      debugPrint('⛔ محاولة تسجيل دخول PIN على جهاز مساعد غير مرتبط بصيدلية سحابية!');
      return null;
    }

    final results = await db.query('assistants', where: 'is_active = 1');
    for (final row in results) {
      final storedPin = row['pin'] as String;
      if (SecurityHelper.verifyPin(pin, storedPin)) {
        // ترقية تلقائية للـ PIN القديم المكتوب بشكل نصي غير مشفر
        if (!storedPin.contains('\$')) {
          final hashed = SecurityHelper.hashPin(pin);
          await db.update('assistants', {'pin': hashed}, where: 'id = ?', whereArgs: [row['id']]);
        }
        return row;
      }
    }
    return null;
  }

  Future<int> updateAssistant(int id, Map<String, dynamic> data) async {
    final db = await database;
    final map = Map<String, dynamic>.from(data);
    map['updated_at'] = DateTime.now().toIso8601String();
    if (map['pin'] != null && !(map['pin'] as String).contains('\$')) {
      map['pin'] = SecurityHelper.hashPin(map['pin'] as String);
    }
    return await db.update('assistants', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAssistant(int id) async {
    final db = await database;
    return await db.delete('assistants', where: 'id = ?', whereArgs: [id]);
  }

  /// التحقق من تكرار رمز PIN بين المساعدين النشطين
  Future<bool> isPinDuplicate(String pin, {int? excludeId}) async {
    final db = await database;
    final results = excludeId != null
        ? await db.query('assistants',
            where: 'is_active = 1 AND id != ?',
            whereArgs: [excludeId])
        : await db.query('assistants',
            where: 'is_active = 1');
    for (final row in results) {
      final storedPin = row['pin'] as String;
      if (SecurityHelper.verifyPin(pin, storedPin)) {
        return true;
      }
    }
    return false;
  }

  // ── سجل الأنشطة (Activity Log) ────────────────────────────────────────────
  Future<int> logActivity({
    int? assistantId,
    required String assistantName,
    required String action,
    String? details,
    String? screen,
  }) async {
    final db = await database;
    return await db.insert('activity_log', {
      'assistant_id': assistantId,
      'assistant_name': assistantName,
      'action': action,
      'details': details,
      'screen': screen,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getActivityLog({int limit = 50}) async {
    final db = await database;
    return await db.query('activity_log',
        orderBy: 'created_at DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getAssistantActivityLog(
      int assistantId, {int limit = 50}) async {
    final db = await database;
    return await db.query('activity_log',
        where: 'assistant_id = ?',
        whereArgs: [assistantId],
        orderBy: 'created_at DESC',
        limit: limit);
  }

  // ── صيانة قاعدة البيانات ────────────────────────────────────────────
  /// تنظيف وضغط قاعدة البيانات لاستعادة المساحة
  Future<void> vacuumDatabase() async {
    final db = await database;
    await db.execute('VACUUM');
    debugPrint('✅ تم ضغط قاعدة البيانات بنجاح');
  }

  /// حجم قاعدة البيانات بالكيلوبايت
  Future<double> getDatabaseSizeKB() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/saydali_pro.db';
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.length();
        return bytes / 1024;
      }
    } catch (e) {
      debugPrint('❌ Error getting DB size: $e');
    }
    return 0;
  }

  // ── مزامنة أكواد الاشتراك من السحابة ────────────────────────────────
  /// يسحب الأكواد من Supabase ويحفظها محلياً (merge بدون تكرار)
  Future<int> syncCodesFromCloud(List<Map<String, dynamic>> cloudCodes) async {
    if (cloudCodes.isEmpty) return 0;
    final db = await database;
    int synced = 0;
    for (final code in cloudCodes) {
      try {
        final existing = await db.query('subscription_codes',
            where: 'code = ?', whereArgs: [code['code']]);
        if (existing.isEmpty) {
          await db.insert('subscription_codes', {
            'code': code['code'],
            'plan': code['plan'] ?? 'pro',
            'duration_days': code['duration_days'] ?? 30,
            'discount_percent': code['discount_percent'] ?? 0,
            'max_uses': code['max_uses'] ?? 1,
            'used_count': code['used_count'] ?? 0,
            'is_active': code['is_active'] == true || code['is_active'] == 1 ? 1 : 0,
            'created_at': code['created_at'] ?? DateTime.now().toIso8601String(),
          });
          synced++;
        } else {
          // تحديث عدد الاستخدام من السحابة (الأحدث يكسب)
          final cloudUsed = code['used_count'] ?? 0;
          final localUsed = existing.first['used_count'] ?? 0;
          if (cloudUsed is int && cloudUsed > (localUsed as int)) {
            await db.update('subscription_codes', 
                {'used_count': cloudUsed},
                where: 'code = ?', whereArgs: [code['code']]);
          }
        }
      } catch (e) {
        debugPrint('⚠️ خطأ في مزامنة كود ${code['code']}: $e');
      }
    }
    if (synced > 0) debugPrint('✅ تم مزامنة $synced كود من السحابة');
    return synced;
  }

  // ── مزامنة الإعلانات من السحابة ────────────────────────────────────
  /// يسحب الإعلانات من Supabase ويحفظها محلياً
  Future<int> syncAdsFromCloud(List<Map<String, dynamic>> cloudAds) async {
    final db = await database;
    
    // مسح الإعلانات القديمة لتحديثها بالإعلانات النشطة الحالية فقط
    await db.delete('ads');
    
    if (cloudAds.isEmpty) return 0;
    
    int synced = 0;
    for (final ad in cloudAds) {
      try {
        await db.insert('ads', {
          'title': ad['title'] ?? '',
          'body': ad['body'] ?? '',
          'image_url': ad['image_url'],
          'link': ad['link'],
          'button_text': ad['button_text'] ?? 'التفاصيل',
          'is_active': ad['is_active'] == true || ad['is_active'] == 1 ? 1 : 0,
          'screen': ad['screen'] ?? 'home',
          'skip_duration': ad['skip_duration'] ?? 0,
          'expires_at': ad['expires_at'],
          'target_country': ad['target_country'],
          'created_at': ad['created_at'] ?? DateTime.now().toIso8601String(),
        });
        synced++;
      } catch (e) {
        debugPrint('⚠️ خطأ في مزامنة إعلان: $e');
      }
    }
    if (synced > 0) debugPrint('✅ تم مزامنة $synced إعلان من السحابة');
    return synced;
  }

  // ── الإحصائيات والأرباح ────────────────────────────────────

  /// مبيعات آخر 7 أيام مجمعة بالتاريخ
  Future<List<Map<String, dynamic>>> getDailySalesLastWeek() async {
    final db = await database;
    final List<Map<String, dynamic>> result = [];
    try {
      final rows = await db.rawQuery('''
        SELECT substr(created_at, 1, 10) as day, SUM(total) as total
        FROM invoices
        WHERE created_at >= date('now', '-6 days')
        GROUP BY day
        ORDER BY day ASC
      ''');
      result.addAll(rows.map((r) => {
        'day': r['day'] as String,
        'total': (r['total'] as num?)?.toDouble() ?? 0.0,
      }));
    } catch (e) {
      debugPrint('Error getDailySalesLastWeek: $e');
    }
    // fill missing days with zero
    final List<Map<String, dynamic>> filled = [];
    for (int i = 6; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      final key = '${day.year}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}';
      final found = result.where((r) => r['day'] == key);
      filled.add({'day': key, 'total': found.isNotEmpty ? found.first['total'] : 0.0});
    }
    return filled;
  }

  Future<Map<String, dynamic>> getStatisticsSummary() async {

    final db = await database;
    double totalSales = 0;
    double totalCost = 0;
    double totalDebts = 0;
    int pendingShortagesCount = 0;
    List<Map<String, dynamic>> topSellingItems = [];
    double totalExpenses = 0;
    List<Map<String, dynamic>> expensesByCategory = [];

    try {
      // 1. إجمالي المبيعات
      final salesResult = await db.rawQuery('SELECT SUM(total) as sum_total FROM invoices');
      if (salesResult.isNotEmpty && salesResult.first['sum_total'] != null) {
        totalSales = (salesResult.first['sum_total'] as num).toDouble();
      }

      // 2. إجمالي الديون المستحقة (محسوب من debt_transactions لتجنب البيانات القديمة)
      final debtsResult = await db.rawQuery("SELECT COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE -amount END), 0) as sum_debt FROM debt_transactions");
      if (debtsResult.isNotEmpty && debtsResult.first['sum_debt'] != null) {
        totalDebts = (debtsResult.first['sum_debt'] as num).toDouble();
      }

      // 3. عدد النواقص الحالية
      final shortagesResult = await db.rawQuery("SELECT COUNT(*) as count FROM shortages WHERE status = 'pending'");
      if (shortagesResult.isNotEmpty && shortagesResult.first['count'] != null) {
        pendingShortagesCount = (shortagesResult.first['count'] as num).toInt();
      }

      // 4. الأصناف الأكثر مبيعاً وحساب التكلفة الإجمالية للمنتجات المبيعة
      final invoices = await db.query('invoices', columns: ['items']);
      Map<String, int> itemCounts = {};
      for (var invoice in invoices) {
        try {
          final itemsJson = invoice['items'] as String?;
          if (itemsJson != null && itemsJson.isNotEmpty) {
            final List<dynamic> itemsList = jsonDecode(itemsJson);
            for (var item in itemsList) {
              final String name = item['name']?.toString() ?? 'غير معروف';
              final int qty = (item['qty'] as num?)?.toInt() ?? 1;
              itemCounts[name] = (itemCounts[name] ?? 0) + qty;

              // حساب التكلفة لهذا الصنف
              final int boxes = (item['boxes'] as num?)?.toInt() ?? 0;
              final int strips = (item['strips'] as num?)?.toInt() ?? 0;
              final double costPrice = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
              final double stripCostPrice = (item['strip_cost_price'] as num?)?.toDouble() ?? 0.0;
              totalCost += (boxes * costPrice) + (strips * stripCostPrice);
            }
          }
        } catch (e) {
          debugPrint('Error parsing invoice items for statistics: $e');
        }
      }

      var sortedItems = itemCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      topSellingItems = sortedItems.take(5).map((e) => {'name': e.key, 'qty': e.value}).toList();

      // 5. إجمالي المصروفات
      final expensesResult = await db.rawQuery('SELECT SUM(amount) as sum_amount FROM expenses');
      if (expensesResult.isNotEmpty && expensesResult.first['sum_amount'] != null) {
        totalExpenses = (expensesResult.first['sum_amount'] as num).toDouble();
      }

      // 6. المصروفات حسب الفئة
      final expensesByCategoryRaw = await db.rawQuery(
        'SELECT category, SUM(amount) as total FROM expenses GROUP BY category ORDER BY total DESC'
      );
      expensesByCategory = expensesByCategoryRaw.map((e) => {
        'category': e['category'] as String,
        'total': (e['total'] as num).toDouble(),
      }).toList();

    } catch (e) {
      debugPrint('Error generating statistics: $e');
    }

    final double grossProfit = totalSales - totalCost;
    final double netProfit = grossProfit - totalExpenses;

    return {
      'total_sales': totalSales,
      'total_cost': totalCost,
      'gross_profit': grossProfit,
      'net_profit': netProfit,
      'total_debts': totalDebts,
      'pending_shortages_count': pendingShortagesCount,
      'top_selling_items': topSellingItems,
      'total_expenses': totalExpenses,
      'expenses_by_category': expensesByCategory,
    };
  }

  // ─── ميزات صلاحية الأدوية ───
  Future<int> insertMedicationExpiry(Map<String, dynamic> data) async {
    final db = await database;
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    map['created_at'] ??= DateTime.now().toIso8601String();
    map['created_by'] ??= await getCurrentUserName();
    map['cloud_id'] ??= SecurityHelper.generateUUID();
    map['is_synced'] = 0;
    return await db.insert('medication_expiries', map);
  }

  Future<List<Map<String, dynamic>>> getMedicationExpiries() async {
    final db = await database;
    return await db.query('medication_expiries', orderBy: 'expiry_date ASC');
  }

  Future<int> updateMedicationExpiry(int id, Map<String, dynamic> data) async {
    final db = await database;
    final Map<String, dynamic> map = Map<String, dynamic>.from(data);
    map['created_by'] = await getCurrentUserName();
    map['is_synced'] = 0;
    return await db.update('medication_expiries', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteMedicationExpiry(int id) async {
    final db = await database;
    return await db.delete('medication_expiries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getExpiringCount(int months) async {
    final db = await database;
    final limitDate = DateTime.now().add(Duration(days: months * 30)).toIso8601String();
    final now = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM medication_expiries WHERE expiry_date <= ? AND expiry_date >= ?',
      [limitDate, now]
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ─── ميزات المصروفات ───
  Future<int> insertExpense(Map<String, dynamic> data) async {
    final db = await database;
    data['created_at'] = DateTime.now().toIso8601String();
    return await db.insert('expenses', data);
  }

  Future<List<Map<String, dynamic>>> getExpenses({String? category, String? startDate, String? endDate}) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (category != null && category.isNotEmpty) {
      whereClause += 'category = ?';
      whereArgs.add(category);
    }

    if (startDate != null && startDate.isNotEmpty) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'expense_date >= ?';
      whereArgs.add(startDate);
    }

    if (endDate != null && endDate.isNotEmpty) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'expense_date <= ?';
      whereArgs.add(endDate);
    }

    return await db.query(
      'expenses',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereClause.isEmpty ? null : whereArgs,
      orderBy: 'expense_date DESC',
    );
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalExpenses() async {
    final db = await database;
    final result = await db.rawQuery('SELECT SUM(amount) as sum_amount FROM expenses');
    if (result.isNotEmpty && result.first['sum_amount'] != null) {
      return (result.first['sum_amount'] as num).toDouble();
    }
    return 0.0;
  }

  // ─── بدائل الأدوية ───
  Future<int> insertAlternative(Map<String, dynamic> data) async {
    final db = await database;
    data['created_at'] = DateTime.now().toIso8601String();
    // ▌ إضافة كود الدولة تلقائياً من إعدادات المستخدم
    if (data['country_code'] == null) {
      data['country_code'] = await getCountryCode();
    }
    return await db.insert('alternatives', data);
  }

  /// حفظ بديل محلياً إذا لم يكن موجوداً مسبقاً (سواء بالاتجاهين) لتجنب التكرار
  Future<void> addAlternativeIfNotExists(String medName, String altName, {String? activeIngredient}) async {
    final db = await database;
    final country = await getCountryCode();
    
    final med = medName.trim();
    final alt = altName.trim();
    if (med.isEmpty || alt.isEmpty) return;

    // التحقق من وجود العلاقة مسبقاً بالاتجاهين
    final existing = await db.query(
      'alternatives',
      where: '((medication_name = ? AND alternative_name = ?) OR (medication_name = ? AND alternative_name = ?)) AND country_code = ?',
      whereArgs: [med, alt, alt, med, country],
    );

    if (existing.isEmpty) {
      await insertAlternative({
        'medication_name': med,
        'alternative_name': alt,
        'active_ingredient': activeIngredient,
      });
      debugPrint('💾 Saved rep alternative locally: $med -> $alt');
    }
  }

  /// البحث عن بدائل محلية حسب اسم الدواء + دولة المستخدم
  Future<List<Map<String, dynamic>>> getAlternativesFor(String medName, {String? countryCode}) async {
    final db = await database;
    final country = countryCode ?? await getCountryCode();
    return await db.query(
      'alternatives',
      where: '(medication_name LIKE ? OR alternative_name LIKE ?) AND country_code = ?',
      whereArgs: ['%$medName%', '%$medName%', country],
    );
  }

  /// البحث عن بدائل محلية حسب المادة الفعالة + دولة المستخدم
  Future<List<Map<String, dynamic>>> getAlternativesByIngredient(String ingredient, {String? countryCode}) async {
    final db = await database;
    final country = countryCode ?? await getCountryCode();
    return await db.query(
      'alternatives',
      where: 'active_ingredient LIKE ? AND country_code = ?',
      whereArgs: ['%$ingredient%', country],
    );
  }

  /// جلب كل البدائل المحلية لدولة المستخدم (بدون بحث)
  Future<List<Map<String, dynamic>>> getAllAlternatives({String? countryCode}) async {
    final db = await database;
    final country = countryCode ?? await getCountryCode();
    return await db.query(
      'alternatives',
      where: 'country_code = ?',
      whereArgs: [country],
      limit: 50,
      orderBy: 'id DESC',
    );
  }

  /// بحث سريع في جدول البدائل لاقتراح أسماء الأدوية حسب الدولة (للاستخدام في شاشة النواقص)
  Future<List<String>> getAlternativeSuggestions(String query, {String? countryCode}) async {
    if (query.trim().isEmpty) return [];
    final db = await database;
    final country = countryCode ?? await getCountryCode();
    final q = '%${query.trim()}%';
    try {
      final rows = await db.rawQuery(
        '''SELECT DISTINCT medication_name, alternative_name FROM alternatives
           WHERE (medication_name LIKE ? OR alternative_name LIKE ? OR active_ingredient LIKE ?)
             AND country_code = ?
           LIMIT 100''',
        [q, q, q, country],
      );
      final names = <String>{};
      for (final row in rows) {
        final med = row['medication_name']?.toString() ?? '';
        final alt = row['alternative_name']?.toString() ?? '';
        if (med.isNotEmpty) names.add(med);
        if (alt.isNotEmpty) names.add(alt);
      }
      return names.toList();
    } catch (e) {
      debugPrint('❌ getAlternativeSuggestions error: $e');
      return [];
    }
  }

  Future<int> deleteAlternativeLink(int id) async {
    final db = await database;
    return await db.delete('alternatives', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  // ميزات المزامنة المحلية (Wi-Fi)
  // ══════════════════════════════════════════════════════════════

  /// جلب البيانات التي تم تعديلها أو إنشاؤها بعد وقت معين للمزامنة المحلية
  Future<Map<String, List<Map<String, dynamic>>>> getLocalSyncData({String? modifiedSince}) async {
    final db = await database;
    
    String queryShortages = "SELECT * FROM shortages";
    String queryCustomers = "SELECT * FROM customers";
    String queryTransactions = "SELECT dt.*, c.cloud_id as customer_cloud_id FROM debt_transactions dt JOIN customers c ON dt.customer_id = c.id";
    String queryInvoices = "SELECT i.*, c.cloud_id as customer_cloud_id FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id";
    String queryAssistants = "SELECT * FROM assistants";
    String queryExpiries = "SELECT * FROM medication_expiries";

    if (modifiedSince != null && modifiedSince.isNotEmpty) {
      queryShortages += " WHERE created_at > ? OR updated_at > ?";
      queryCustomers += " WHERE created_at > ?";
      queryTransactions += " WHERE transaction_date > ?";
      queryInvoices += " WHERE created_at > ?";
      queryAssistants += " WHERE created_at > ?";
      queryExpiries += " WHERE created_at > ?";
    }

    final shortages = await db.rawQuery(queryShortages, modifiedSince != null && modifiedSince.isNotEmpty ? [modifiedSince, modifiedSince] : null);
    final customers = await db.rawQuery(queryCustomers, modifiedSince != null && modifiedSince.isNotEmpty ? [modifiedSince] : null);
    final transactions = await db.rawQuery(queryTransactions, modifiedSince != null && modifiedSince.isNotEmpty ? [modifiedSince] : null);
    final invoices = await db.rawQuery(queryInvoices, modifiedSince != null && modifiedSince.isNotEmpty ? [modifiedSince] : null);
    final assistants = await db.rawQuery(queryAssistants, modifiedSince != null && modifiedSince.isNotEmpty ? [modifiedSince] : null);
    final expiries = await db.rawQuery(queryExpiries, modifiedSince != null && modifiedSince.isNotEmpty ? [modifiedSince] : null);

    return {
      'shortages': shortages,
      'customers': customers,
      'debt_transactions': transactions,
      'invoices': invoices,
      'assistants': assistants,
      'medication_expiries': expiries,
    };
  }

  /// جلب كافة البيانات المحلية التي لم تُزامن بعد مع السحابة أو محلياً
  Future<Map<String, List<Map<String, dynamic>>>> getUnsyncedLocalData() async {
    final db = await database;
    final shortages = await db.query('shortages', where: 'is_synced = 0 OR is_synced IS NULL');
    final customers = await db.query('customers', where: 'is_synced = 0 OR is_synced IS NULL');
    final transactions = await db.rawQuery('''
      SELECT dt.*, c.cloud_id as customer_cloud_id 
      FROM debt_transactions dt
      JOIN customers c ON dt.customer_id = c.id
      WHERE dt.is_synced = 0 OR dt.is_synced IS NULL
    ''');
    final invoices = await db.rawQuery('''
      SELECT i.*, c.cloud_id as customer_cloud_id 
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE i.is_synced = 0 OR i.is_synced IS NULL
    ''');
    final assistants = await db.query('assistants'); // مزامنة كل المساعدين دائماً لسلامة الصلاحيات
    final expiries = await db.query('medication_expiries', where: 'is_synced = 0 OR is_synced IS NULL');

    return {
      'shortages': shortages,
      'customers': customers,
      'debt_transactions': transactions,
      'invoices': invoices,
      'assistants': assistants,
      'medication_expiries': expiries,
    };
  }

  /// دمج التحديثات الواردة من جهاز المزامنة المحلية الآخر في قاعدة البيانات المحلية
  Future<void> mergeLocalSyncData(Map<String, dynamic> incomingData) async {
    final db = await database;

    // 1. العملاء
    if (incomingData['customers'] != null) {
      for (final item in incomingData['customers']) {
        final cloudId = item['cloud_id'];
        if (cloudId == null || cloudId.toString().isEmpty) continue;
        final existing = await db.query('customers', where: 'cloud_id = ?', whereArgs: [cloudId]);
        final data = {
          'cloud_id': cloudId,
          'name': item['name'],
          'phone': item['phone'],
          'address': item['address'],
          'due_date': item['due_date'],
          'photo_url': item['photo_url'],
          'created_by': item['created_by'],
          'created_at': item['created_at'],
          'is_synced': 1,
        };
        if (existing.isEmpty) {
          await db.insert('customers', data);
        } else {
          final localCreated = existing.first['created_at']?.toString() ?? '';
          final remoteCreated = item['created_at']?.toString() ?? '';
          if (remoteCreated.compareTo(localCreated) > 0) {
            await db.update('customers', data, where: 'cloud_id = ?', whereArgs: [cloudId]);
          }
        }
      }
    }

    // 2. النواقص
    if (incomingData['shortages'] != null) {
      for (final item in incomingData['shortages']) {
        final cloudId = item['cloud_id'];
        if (cloudId == null || cloudId.toString().isEmpty) continue;
        final existing = await db.query('shortages', where: 'cloud_id = ?', whereArgs: [cloudId]);
        final data = {
          'cloud_id': cloudId,
          'name': item['name'],
          'company': item['company'] ?? 'غير محدد',
          'quantity': item['quantity'] ?? 1,
          'status': item['status'] ?? 'pending',
          'is_urgent': item['is_urgent'] ?? 0,
          'notes': item['notes'],
          'created_by': item['created_by'],
          'created_at': item['created_at'],
          'updated_at': item['updated_at'],
          'is_synced': 1,
        };
        if (existing.isEmpty) {
          await db.insert('shortages', data);
        } else {
          final localUpdated = existing.first['updated_at']?.toString() ?? '';
          final remoteUpdated = item['updated_at']?.toString() ?? '';
          if (remoteUpdated.compareTo(localUpdated) > 0) {
            await db.update('shortages', data, where: 'cloud_id = ?', whereArgs: [cloudId]);
          }
        }
      }
    }

    // 3. معاملات الديون
    if (incomingData['debt_transactions'] != null) {
      for (final item in incomingData['debt_transactions']) {
        final cloudId = item['cloud_id'];
        if (cloudId == null || cloudId.toString().isEmpty) continue;
        
        final customerCloudId = item['customer_cloud_id'];
        int? localCustomerId;
        if (customerCloudId != null) {
          final customer = await db.query('customers', where: 'cloud_id = ?', whereArgs: [customerCloudId]);
          if (customer.isNotEmpty) {
            localCustomerId = customer.first['id'] as int?;
          }
        }
        if (localCustomerId == null) continue; // لا يوجد العميل محلياً بعد

        final existing = await db.query('debt_transactions', where: 'cloud_id = ?', whereArgs: [cloudId]);
        final data = {
          'cloud_id': cloudId,
          'customer_id': localCustomerId,
          'amount': item['amount'],
          'type': item['type'],
          'description': item['description'],
          'receipt_url': item['receipt_url'],
          'created_by': item['created_by'],
          'transaction_date': item['transaction_date'],
          'is_synced': 1,
        };
        if (existing.isEmpty) {
          await db.insert('debt_transactions', data);
        } else {
          final localDate = existing.first['transaction_date']?.toString() ?? '';
          final remoteDate = item['transaction_date']?.toString() ?? '';
          if (remoteDate.compareTo(localDate) > 0) {
            await db.update('debt_transactions', data, where: 'cloud_id = ?', whereArgs: [cloudId]);
          }
        }
      }
      await recalculateAllDebts();
    }

    // 4. الفواتير
    if (incomingData['invoices'] != null) {
      for (final item in incomingData['invoices']) {
        final cloudId = item['cloud_id'];
        if (cloudId == null || cloudId.toString().isEmpty) continue;

        final customerCloudId = item['customer_cloud_id'];
        int? localCustomerId;
        if (customerCloudId != null) {
          final customer = await db.query('customers', where: 'cloud_id = ?', whereArgs: [customerCloudId]);
          if (customer.isNotEmpty) {
            localCustomerId = customer.first['id'] as int?;
          }
        }

        final existing = await db.query('invoices', where: 'cloud_id = ?', whereArgs: [cloudId]);
        final data = {
          'cloud_id': cloudId,
          'customer_id': localCustomerId,
          'customer_name': item['customer_name'],
          'items': item['items'],
          'subtotal': item['subtotal'],
          'discount': item['discount'],
          'total': item['total'],
          'paid_amount': item['paid_amount'] ?? 0,
          'remaining': item['remaining'] ?? 0,
          'notes': item['notes'],
          'created_by': item['created_by'],
          'created_at': item['created_at'],
          'is_synced': 1,
        };
        if (existing.isEmpty) {
          await db.insert('invoices', data);
        } else {
          final localDate = existing.first['created_at']?.toString() ?? '';
          final remoteDate = item['created_at']?.toString() ?? '';
          if (remoteDate.compareTo(localDate) > 0) {
            await db.update('invoices', data, where: 'cloud_id = ?', whereArgs: [cloudId]);
          }
        }
      }
    }

    // 5. المساعدين
    if (incomingData['assistants'] != null) {
      for (final item in incomingData['assistants']) {
        final cloudId = item['cloud_id'];
        if (cloudId == null || cloudId.toString().isEmpty) continue;
        final existing = await db.query('assistants', where: 'cloud_id = ?', whereArgs: [cloudId]);
        final data = {
          'cloud_id': cloudId,
          'name': item['name'],
          'phone': item['phone'],
          'pin': item['pin'],
          'role': item['role'] ?? 'assistant',
          'can_add_debt': item['can_add_debt'] ?? 1,
          'can_edit_debt': item['can_edit_debt'] ?? 0,
          'can_delete': item['can_delete'] ?? 0,
          'can_view_reports': item['can_view_reports'] ?? 0,
          'can_manage_invoices': item['can_manage_invoices'] ?? 1,
          'can_manage_shortages': item['can_manage_shortages'] ?? 1,
          'can_manage_reps': item['can_manage_reps'] ?? 0,
          'is_active': item['is_active'] ?? 1,
          'subscription_expiry': item['subscription_expiry'],
          'subscription_duration_days': item['subscription_duration_days'] ?? 30,
          'created_at': item['created_at'],
        };
        if (existing.isEmpty) {
          await db.insert('assistants', data);
        } else {
          final localUpdated = existing.first['updated_at']?.toString() ?? existing.first['created_at']?.toString() ?? '';
          final remoteUpdated = item['updated_at']?.toString() ?? item['created_at']?.toString() ?? '';
          if (remoteUpdated.compareTo(localUpdated) > 0) {
            await db.update('assistants', data, where: 'cloud_id = ?', whereArgs: [cloudId]);
          }
        }
      }
    }

    // 6. صلاحية الأدوية
    if (incomingData['medication_expiries'] != null) {
      for (final item in incomingData['medication_expiries']) {
        final cloudId = item['cloud_id'];
        if (cloudId == null || cloudId.toString().isEmpty) continue;
        final existing = await db.query('medication_expiries', where: 'cloud_id = ?', whereArgs: [cloudId]);
        final data = {
          'cloud_id': cloudId,
          'name': item['name'],
          'quantity': item['quantity'] ?? 1,
          'expiry_date': item['expiry_date'],
          'supplier_name': item['supplier_name'],
          'notes': item['notes'],
          'created_by': item['created_by'],
          'created_at': item['created_at'],
          'is_synced': 1,
        };
        if (existing.isEmpty) {
          await db.insert('medication_expiries', data);
        } else {
          final localDate = existing.first['created_at']?.toString() ?? '';
          final remoteDate = item['created_at']?.toString() ?? '';
          if (remoteDate.compareTo(localDate) > 0) {
            await db.update('medication_expiries', data, where: 'cloud_id = ?', whereArgs: [cloudId]);
          }
        }
      }
    }
  }

  /// إعادة حساب مديونيات كافة العملاء من جدول حركات الديون لضمان سلامة الأرقام بعد الدمج
  Future<void> recalculateAllDebts() async {
    final db = await database;
    final customers = await db.query('customers');
    for (final c in customers) {
      final id = c['id'];
      final result = await db.rawQuery(
        """SELECT 
            COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE 0 END), 0) -
            COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END), 0) 
            as net
           FROM debt_transactions WHERE customer_id = ?""",
        [id],
      );
      final newDebt = (result.first['net'] as num?)?.toDouble() ?? 0.0;
      await db.update(
        'customers',
        {'total_debt': newDebt < 0 ? 0.0 : newDebt},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// تعليم كافة السجلات المحلية كـ "تمت مزامنتها"
  Future<void> markLocalDataAsSynced() async {
    final db = await database;
    await db.update('shortages', {'is_synced': 1});
    await db.update('customers', {'is_synced': 1});
    await db.update('debt_transactions', {'is_synced': 1});
    await db.update('invoices', {'is_synced': 1});
    await db.update('medication_expiries', {'is_synced': 1});
  }

  /// حذف ردود المندوبين القديمة من قاعدة البيانات المحلية
  /// يُستدعى بعد نجاح رفعها للسحابة لمنع التضخم غير المحدود
  Future<int> deleteOldRepResponses({int daysToKeep = 30}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysToKeep))
        .toIso8601String();
    final deleted = await db.delete(
      'rep_responses',
      where: "responded_at < ?",
      whereArgs: [cutoff],
    );
    if (deleted > 0) {
      debugPrint('🗑️ تم حذف $deleted سجل قديم من ردود المندوبين (أقدم من $daysToKeep يوم)');
    }
    return deleted;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── إدارة الجرد والمخزون الفعلي (Inventory & Stocktaking) ─────────────────
  // ══════════════════════════════════════════════════════════════════════════

  /// إنشاء جلسة جرد جديدة
  Future<int> insertInventorySession(Map<String, dynamic> data) async {
    final db = await database;
    final map = Map<String, dynamic>.from(data);
    map['created_at'] ??= DateTime.now().toIso8601String();
    map['created_by'] ??= await getCurrentUserName();
    map['cloud_id'] ??= SecurityHelper.generateUUID();
    map['status'] ??= 'in_progress';
    map['is_synced'] = 0;
    final id = await db.insert('inventory_sessions', map);

    debugPrint('📦 جرد: بدء جلسة ${map['title']} بواسطة ${map['created_by']}');

    return id;
  }

  /// جلب كافة جلسات الجرد
  Future<List<Map<String, dynamic>>> getInventorySessions() async {
    final db = await database;
    return await db.query('inventory_sessions', orderBy: 'id DESC');
  }

  /// جلب تفاصيل جلسة جرد واحدة
  Future<Map<String, dynamic>?> getInventorySession(int id) async {
    final db = await database;
    final res = await db.query('inventory_sessions', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? res.first : null;
  }

  /// تحديث بيانات جلسة الجرد
  Future<int> updateInventorySession(int id, Map<String, dynamic> data) async {
    final db = await database;
    final map = Map<String, dynamic>.from(data);
    map['is_synced'] = 0;
    return await db.update('inventory_sessions', map, where: 'id = ?', whereArgs: [id]);
  }

  /// حذف جلسة جرد وعناصرها
  Future<int> deleteInventorySession(int id) async {
    final db = await database;
    final session = await getInventorySession(id);
    final title = session?['title'] ?? 'جلسة #$id';
    await db.delete('inventory_items', where: 'session_id = ?', whereArgs: [id]);
    final deleted = await db.delete('inventory_sessions', where: 'id = ?', whereArgs: [id]);

    debugPrint('🗑️ جرد: حذف جلسة $title');

    return deleted;
  }

  /// إدراج دفعة من أصناف الجرد داخل جلسة
  Future<void> insertInventoryItemsBatch(int sessionId, List<Map<String, dynamic>> items) async {
    final db = await database;
    final batch = db.batch();
    for (final item in items) {
      final map = Map<String, dynamic>.from(item);
      map['session_id'] = sessionId;
      map['cloud_id'] ??= SecurityHelper.generateUUID();
      map['status'] ??= 'pending';
      map['review_status'] ??= 'pending';
      map['is_synced'] = 0;
      batch.insert('inventory_items', map);
    }
    await batch.commit(noResult: true);
    await updateInventorySessionStats(sessionId);
  }

  /// جلب أصناف جلسة جرد مع فلترة اختيارية
  Future<List<Map<String, dynamic>>> getInventoryItems(int sessionId, {String? statusFilter, String? search}) async {
    final db = await database;
    String whereClause = 'session_id = ?';
    List<dynamic> whereArgs = [sessionId];

    if (statusFilter != null && statusFilter != 'all') {
      whereClause += ' AND status = ?';
      whereArgs.add(statusFilter);
    }

    if (search != null && search.trim().isNotEmpty) {
      whereClause += ' AND (name LIKE ? OR barcode LIKE ?)';
      whereArgs.add('%${search.trim()}%');
      whereArgs.add('%${search.trim()}%');
    }

    return await db.query('inventory_items',
        where: whereClause, whereArgs: whereArgs, orderBy: 'id ASC');
  }

  /// تسجيل الكمية الفعلية لصنف وتحديث الفرق والحالة فوراً
  Future<void> updateInventoryItemCount(
    int itemId,
    double actualQty,
    String countedBy, {
    String? notes,
  }) async {
    final db = await database;
    final itemRows = await db.query('inventory_items', where: 'id = ?', whereArgs: [itemId]);
    if (itemRows.isEmpty) return;

    final item = itemRows.first;
    final systemQty = (item['system_quantity'] as num?)?.toDouble() ?? 0.0;
    final diff = actualQty - systemQty;

    String status = 'matched';
    if (diff > 0.001) {
      status = 'surplus';
    } else if (diff < -0.001) {
      status = 'deficit';
    }

    final updateData = <String, dynamic>{
      'actual_quantity': actualQty,
      'difference': diff,
      'status': status,
      'counted_by': countedBy,
      'counted_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    };
    if (notes != null) updateData['notes'] = notes;

    await db.update('inventory_items', updateData, where: 'id = ?', whereArgs: [itemId]);

    final sessionId = item['session_id'] as int;
    await updateInventorySessionStats(sessionId);
  }

  /// إعادة حساب إحصائيات الجلسة بدقة وتحديث جدول الجلسات
  Future<void> updateInventorySessionStats(int sessionId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total,
        COUNT(actual_quantity) as counted,
        SUM(CASE WHEN status = 'matched' THEN 1 ELSE 0 END) as matched,
        SUM(CASE WHEN status = 'surplus' THEN 1 ELSE 0 END) as surplus,
        SUM(CASE WHEN status = 'deficit' THEN 1 ELSE 0 END) as deficit
      FROM inventory_items
      WHERE session_id = ?
    ''', [sessionId]);

    if (result.isNotEmpty) {
      final row = result.first;
      final total = (row['total'] as num?)?.toInt() ?? 0;
      final counted = (row['counted'] as num?)?.toInt() ?? 0;
      final matched = (row['matched'] as num?)?.toInt() ?? 0;
      final surplus = (row['surplus'] as num?)?.toInt() ?? 0;
      final deficit = (row['deficit'] as num?)?.toInt() ?? 0;

      await db.update(
        'inventory_sessions',
        {
          'total_items': total,
          'counted_items': counted,
          'matched_items': matched,
          'surplus_items': surplus,
          'deficit_items': deficit,
          'is_synced': 0,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    }
  }

  /// اعتماد نتيجة الجلسة بالكامل (للمالك)
  Future<void> approveInventorySession(int sessionId, String approvedBy) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'inventory_sessions',
      {
        'status': 'completed',
        'completed_at': now,
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    await db.update(
      'inventory_items',
      {
        'review_status': 'approved',
        'is_synced': 0,
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    final session = await getInventorySession(sessionId);
    debugPrint('✅ جرد: اعتماد جلسة ${session?['title'] ?? '#$sessionId'} بواسطة $approvedBy');
  }

  /// طلب إعادة عد لأصناف محددة أو للجلسة كلها
  Future<void> requestInventoryRecount(int sessionId, {List<int>? itemIds}) async {
    final db = await database;
    final userName = await getCurrentUserName();

    if (itemIds == null || itemIds.isEmpty) {
      // إعادة عد الجلسة كاملة
      await db.update(
        'inventory_sessions',
        {
          'status': 'recount_requested',
          'is_synced': 0,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      await db.update(
        'inventory_items',
        {
          'actual_quantity': null,
          'difference': null,
          'status': 'pending',
          'review_status': 'recount',
          'is_synced': 0,
        },
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
    } else {
      for (final id in itemIds) {
        await db.update(
          'inventory_items',
          {
            'actual_quantity': null,
            'difference': null,
            'status': 'pending',
            'review_status': 'recount',
            'is_synced': 0,
          },
          where: 'id = ? AND session_id = ?',
          whereArgs: [id, sessionId],
        );
      }
      await db.update(
        'inventory_sessions',
        {
          'status': 'recount_requested',
          'is_synced': 0,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    }

    await updateInventorySessionStats(sessionId);

    final session = await getInventorySession(sessionId);
    debugPrint('🔄 جرد: طلب إعادة عد لجلسة ${session?['title'] ?? '#$sessionId'}');
  }

  /// استيراد قائمة الأصناف من قاموس الأدوية المسجل لتسهيل إنشاء جلسة جرد
  Future<List<Map<String, dynamic>>> getDrugDictionaryItemsForInventory() async {
    final dictStr = await getSetting('drug_dictionary_v2') ?? await getSetting('drug_dictionary');
    if (dictStr == null || dictStr.isEmpty || dictStr == '[]') return [];

    try {
      final List<dynamic> decoded = jsonDecode(dictStr);
      final list = <Map<String, dynamic>>[];
      for (final item in decoded) {
        final name = (item['arName'] ?? item['enName'] ?? item['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          list.add({
            'name': name,
            'barcode': item['barcode']?.toString(),
            'system_quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
          });
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }
}
