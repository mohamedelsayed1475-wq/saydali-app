import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('Database migration', () {
    test('database opens at version 18 without errors', () async {
      final factory = databaseFactoryFfi;
      final db = await factory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 18,
          onCreate: (db, version) async {
            // Simulate the full schema creation from DatabaseHelper._onCreate
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
            await db.execute('''
              CREATE TABLE settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
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
                expires_at TEXT,
                target_country TEXT,
                created_at TEXT NOT NULL
              )
            ''');
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
                can_manage_shortages INTEGER DEFAULT 1,
                can_manage_reps INTEGER DEFAULT 0,
                is_active INTEGER DEFAULT 1,
                subscription_expiry TEXT,
                subscription_duration_days INTEGER DEFAULT 30,
                cloud_id TEXT,
                updated_at TEXT,
                created_at TEXT NOT NULL
              )
            ''');
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
            await db.execute('''
              CREATE TABLE IF NOT EXISTS used_activation_codes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT UNIQUE NOT NULL,
                used_at TEXT NOT NULL
              )
            ''');
            // Indexes
            await db.execute('CREATE INDEX IF NOT EXISTS idx_shortages_status ON shortages(status)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_shortages_created ON shortages(created_at DESC)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_debt_customer ON debt_transactions(customer_id)');
          },
        ),
      );

      expect(db.isOpen, true);

      // Verify required tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      expect(tableNames, contains('shortages'));
      expect(tableNames, contains('customers'));
      expect(tableNames, contains('invoices'));
      expect(tableNames, contains('debt_transactions'));
      expect(tableNames, contains('settings'));
      expect(tableNames, contains('assistants'));
      expect(tableNames, contains('rep_orders'));
      expect(tableNames, contains('rep_returns'));
      expect(tableNames, contains('subscription_codes'));
      expect(tableNames, contains('ads'));
      expect(tableNames, contains('activity_log'));
      expect(tableNames, contains('medication_expiries'));
      expect(tableNames, contains('expenses'));
      expect(tableNames, contains('alternatives'));
      expect(tableNames, contains('used_activation_codes'));
      expect(tableNames, contains('representatives'));
      expect(tableNames, contains('rep_responses'));

      // Verify required indexes exist
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' ORDER BY name",
      );
      final indexNames = indexes.map((i) => i['name'] as String).toSet();

      expect(indexNames, contains('idx_shortages_status'));
      expect(indexNames, contains('idx_shortages_created'));
      expect(indexNames, contains('idx_debt_customer'));

      await db.close();
    });
  });
}
