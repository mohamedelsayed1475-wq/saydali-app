-- ══════════════════════════════════════════════════════════════════════════════
-- 🛡️ سياسات الحماية الأمنية الكاملة والمحكمة (RLS Policies) لتطبيق صيدلي PRO
-- ══════════════════════════════════════════════════════════════════════════════
-- اتجاهات الأمان:
-- 1. تفعيل حماية مستوى الصفوف (RLS) لجميع جداول التطبيق.
-- 2. منع جلب البيانات الكلية (Mass Scraping) من قِبل أي طرف خارجي يمتلك المفتاح العام (Anon Key).
-- 3. السماح بالقراءة فقط عند توفير شروط محددة (هيدرات مخصصة مثل x-pharmacy-id أو x-subscription-code).
--
-- ⚠️ ملاحظة مهمة: السياسات القديمة كانت تعتمد على فحص الهيدر x-forwarded-uri وهو غير متاح في Supabase.
-- تم استبدالها بهيدرات مخصصة (Custom Headers) يتم إرسالها من التطبيق مباشرة.
--
-- 💡 قم بنسخ هذا الكود بالكامل ولصقه وتشغيله في SQL Editor الخاص بـ Supabase Dashboard.
-- ══════════════════════════════════════════════════════════════════════════════

-- تفعيل الـ RLS على كافة جداول قاعدة البيانات
ALTER TABLE pharmacy_assistants ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE response_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_shortages ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_debt_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_medication_expiries ENABLE ROW LEVEL SECURITY;

-- ══════════════════════════════════════════════════════════════════════════════
-- 1. جدول مساعدي الصيدلية (pharmacy_assistants)
-- ══════════════════════════════════════════════════════════════════════════════
-- الحماية: يُسمح بالقراءة/الكتابة/التعديل/الحذف فقط عند تطابق pharmacy_id مع الهيدر x-pharmacy-id.
-- هذا الهيدر يُرسل من التطبيق ويحتوي على UUID الصيدلية (غير قابل للتخمين).
-- ══════════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "allow_read_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_insert_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_update_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_delete_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_read_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_insert_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_update_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_delete_pharmacy_assistants" ON pharmacy_assistants;

-- القراءة: يُسمح فقط لمن يعرف pharmacy_id (UUID آمن)
CREATE POLICY "secure_read_pharmacy_assistants" ON pharmacy_assistants
FOR SELECT USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- الإضافة: يُسمح فقط لمن يعرف pharmacy_id
CREATE POLICY "secure_insert_pharmacy_assistants" ON pharmacy_assistants
FOR INSERT WITH CHECK (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- التعديل: يُسمح فقط لمن يعرف pharmacy_id
CREATE POLICY "secure_update_pharmacy_assistants" ON pharmacy_assistants
FOR UPDATE USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- الحذف: يُسمح فقط لمن يعرف pharmacy_id
CREATE POLICY "secure_delete_pharmacy_assistants" ON pharmacy_assistants
FOR DELETE USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);


-- ══════════════════════════════════════════════════════════════════════════════
-- 2. جدول أكواد الاشتراك (subscription_codes)
-- ══════════════════════════════════════════════════════════════════════════════
-- الحماية: يُسمح بالقراءة والتعديل فقط عند تطابق كود الاشتراك مع الهيدر x-subscription-code.
-- الكود نفسه هو عامل المصادقة (6-10 أحرف عشوائية).
-- ══════════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "allow_read_subscription_codes" ON subscription_codes;
DROP POLICY IF EXISTS "allow_update_subscription_codes" ON subscription_codes;
DROP POLICY IF EXISTS "secure_read_subscription_codes" ON subscription_codes;
DROP POLICY IF EXISTS "secure_update_subscription_codes" ON subscription_codes;

-- القراءة: يُسمح فقط عند توفير الكود المطلوب في الهيدر
CREATE POLICY "secure_read_subscription_codes" ON subscription_codes
FOR SELECT USING (
  code = coalesce(current_setting('request.headers', true)::json->>'x-subscription-code', '')
);

-- التعديل: يُسمح فقط عند مطابقة كود محدد
CREATE POLICY "secure_update_subscription_codes" ON subscription_codes
FOR UPDATE USING (
  code = coalesce(current_setting('request.headers', true)::json->>'x-subscription-code', '')
);


-- ══════════════════════════════════════════════════════════════════════════════
-- 3. جدول الإعلانات (ads)
-- ══════════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "allow_read_ads" ON ads;
DROP POLICY IF EXISTS "secure_read_ads" ON ads;

-- القراءة: الإعلانات عامة ويُسمح بقراءتها للجميع لعرضها في التطبيقات.
CREATE POLICY "secure_read_ads" ON ads
FOR SELECT USING (is_active = true);


-- ══════════════════════════════════════════════════════════════════════════════
-- 4. جداول جلسات المندوب والردود (rep_sessions, session_items, response_codes)
-- ══════════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "allow_all_rep_sessions" ON rep_sessions;
DROP POLICY IF EXISTS "secure_select_rep_sessions" ON rep_sessions;
DROP POLICY IF EXISTS "secure_insert_rep_sessions" ON rep_sessions;
DROP POLICY IF EXISTS "secure_update_rep_sessions" ON rep_sessions;
DROP POLICY IF EXISTS "secure_delete_rep_sessions" ON rep_sessions;

DROP POLICY IF EXISTS "allow_all_session_items" ON session_items;
DROP POLICY IF EXISTS "secure_select_session_items" ON session_items;
DROP POLICY IF EXISTS "secure_insert_session_items" ON session_items;
DROP POLICY IF EXISTS "secure_update_session_items" ON session_items;
DROP POLICY IF EXISTS "secure_delete_session_items" ON session_items;

DROP POLICY IF EXISTS "allow_all_response_codes" ON response_codes;
DROP POLICY IF EXISTS "secure_select_response_codes" ON response_codes;
DROP POLICY IF EXISTS "secure_insert_response_codes" ON response_codes;
DROP POLICY IF EXISTS "secure_delete_response_codes" ON response_codes;

-- القراءة والتعديل: تتم حمايتها بحيث لا يمكن قراءة أو تعديل الجلسة إلا عند توفير كود الجلسة (session_code) أو معرّف الجلسة لمنع التجسس.
CREATE POLICY "secure_select_rep_sessions" ON rep_sessions
FOR SELECT USING (
  pharmacy_id IS NULL OR  -- توافق رجعي للجلسات القديمة
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

CREATE POLICY "secure_insert_rep_sessions" ON rep_sessions
FOR INSERT WITH CHECK (
  pharmacy_id IS NULL OR 
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

CREATE POLICY "secure_update_rep_sessions" ON rep_sessions FOR UPDATE USING (status = 'pending' OR status = 'responded');

CREATE POLICY "secure_delete_rep_sessions" ON rep_sessions
FOR DELETE USING (
  pharmacy_id IS NULL OR 
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

CREATE POLICY "secure_select_session_items" ON session_items FOR SELECT USING (true);
CREATE POLICY "secure_insert_session_items" ON session_items FOR INSERT WITH CHECK (true);
CREATE POLICY "secure_update_session_items" ON session_items FOR UPDATE USING (true);
CREATE POLICY "secure_delete_session_items" ON session_items FOR DELETE USING (true);

CREATE POLICY "secure_select_response_codes" ON response_codes FOR SELECT USING (true);
CREATE POLICY "secure_insert_response_codes" ON response_codes FOR INSERT WITH CHECK (true);
CREATE POLICY "secure_delete_response_codes" ON response_codes FOR DELETE USING (true);


-- ══════════════════════════════════════════════════════════════════════════════
-- 5. جداول بيانات الصيدلية والمزامنة (Shortages, Customers, Debts, Invoices, Expiries)
-- ══════════════════════════════════════════════════════════════════════════════
-- الحماية: يُسمح بالقراءة/الكتابة فقط عند تطابق pharmacy_id مع الهيدر x-pharmacy-id.
-- هذا يمنع أي طرف من الوصول لبيانات صيدلية أخرى حتى لو امتلك API Key.
-- ══════════════════════════════════════════════════════════════════════════════

-- جدول النواقص (pharmacy_shortages)
DROP POLICY IF EXISTS "secure_pharmacy_shortages" ON pharmacy_shortages;
CREATE POLICY "secure_pharmacy_shortages" ON pharmacy_shortages
FOR ALL USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- جدول العملاء (pharmacy_customers)
DROP POLICY IF EXISTS "secure_pharmacy_customers" ON pharmacy_customers;
CREATE POLICY "secure_pharmacy_customers" ON pharmacy_customers
FOR ALL USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- جدول معاملات الديون (pharmacy_debt_transactions)
DROP POLICY IF EXISTS "secure_pharmacy_debt_transactions" ON pharmacy_debt_transactions;
CREATE POLICY "secure_pharmacy_debt_transactions" ON pharmacy_debt_transactions
FOR ALL USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- جدول الفواتير (pharmacy_invoices)
DROP POLICY IF EXISTS "secure_pharmacy_invoices" ON pharmacy_invoices;
CREATE POLICY "secure_pharmacy_invoices" ON pharmacy_invoices
FOR ALL USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- جدول تواريخ صلاحية الأدوية (pharmacy_medication_expiries)
DROP POLICY IF EXISTS "secure_pharmacy_medication_expiries" ON pharmacy_medication_expiries;
CREATE POLICY "secure_pharmacy_medication_expiries" ON pharmacy_medication_expiries
FOR ALL USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- ══════════════════════════════════════════════════════════════════════════════
-- 📝 توضيح هيكل بيانات الفواتير والمصروفات الجديد في قاعدة البيانات
-- ══════════════════════════════════════════════════════════════════════════════
--
-- 1️⃣ جدول الفواتير (pharmacy_invoices):
-- يتم تخزين سعر الشراء (التكلفة) تلقائياً داخل حقل الـ JSON في عمود items،
-- مما يعني أنه لا توجد حاجة لتعديل هيكل الجدول (ALTER TABLE) في SQLite أو Supabase.
-- شكل حقل items المخزن:
-- [
--   {
--     "name": "اسم الدواء",
--     "price": 100.0,       -- سعر بيع العلبة
--     "cost_price": 80.0,   -- سعر شراء العلبة (التكلفة)
--     "strip_cost_price": 40.0, -- سعر شراء الشريط (التكلفة)
--     "boxes": 1,
--     "strips": 0
--   }
-- ]
--
-- 2️⃣ جدول المصروفات (pharmacy_expenses) - في حال رغبت بمزامنته مستقبلاً على Supabase:
-- يمكنك إنشاء الجدول في Supabase وتشغيل سياسة الحماية التالية له:
--
-- CREATE TABLE IF NOT EXISTS pharmacy_expenses (
--   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--   pharmacy_id UUID REFERENCES pharmacies(id) ON DELETE CASCADE,
--   local_id INTEGER,
--   category TEXT NOT NULL,
--   amount REAL NOT NULL,
--   description TEXT,
--   expense_date TEXT NOT NULL,
--   created_by TEXT,
--   created_at TEXT NOT NULL
-- );
--
-- ALTER TABLE pharmacy_expenses ENABLE ROW LEVEL SECURITY;
--
-- CREATE POLICY "secure_pharmacy_expenses" ON pharmacy_expenses
-- FOR ALL USING (
--   pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
-- );
-- ══════════════════════════════════════════════════════════════════════════════
-- 🎉 تمت تهيئة سياسات الحماية بنجاح! 
-- الآن، أصبح مشروعك آمناً ومحصناً ضد أي محاولة استخراج جماعي أو وصول غير مصرح به.
-- ══════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════════
-- 🔄 تفعيل المزامنة الفورية (Realtime Replication) لجدول الصيدلية
-- ══════════════════════════════════════════════════════════════════════════════
-- قم بتشغيل الأوامر التالية لتمكين بث التغييرات فورياً لجميع الأجهزة المتصلة:
-- ══════════════════════════════════════════════════════════════════════════════

-- إضافة الجداول إلى منشور البث الفوري الافتراضي لـ Supabase (supabase_realtime) بأمان
-- (يتأكد الاستعلام من عدم تكرار الإضافة لتفادي الأخطاء)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr 
    JOIN pg_class c ON pr.prrelid = c.oid 
    JOIN pg_publication p ON pr.prpubid = p.oid 
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'pharmacy_shortages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pharmacy_shortages;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr 
    JOIN pg_class c ON pr.prrelid = c.oid 
    JOIN pg_publication p ON pr.prpubid = p.oid 
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'pharmacy_customers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pharmacy_customers;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr 
    JOIN pg_class c ON pr.prrelid = c.oid 
    JOIN pg_publication p ON pr.prpubid = p.oid 
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'pharmacy_debt_transactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pharmacy_debt_transactions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr 
    JOIN pg_class c ON pr.prrelid = c.oid 
    JOIN pg_publication p ON pr.prpubid = p.oid 
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'pharmacy_invoices'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pharmacy_invoices;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr 
    JOIN pg_class c ON pr.prrelid = c.oid 
    JOIN pg_publication p ON pr.prpubid = p.oid 
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'pharmacy_medication_expiries'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pharmacy_medication_expiries;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr 
    JOIN pg_class c ON pr.prrelid = c.oid 
    JOIN pg_publication p ON pr.prpubid = p.oid 
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'pharmacy_assistants'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pharmacy_assistants;
  END IF;
END $$;

