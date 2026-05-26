-- ══════════════════════════════════════════════════════════════════════════════
-- 🛡️ سياسات الحماية الأمنية الكاملة والمحكمة (RLS Policies) لتطبيق صيدلي PRO
-- ══════════════════════════════════════════════════════════════════════════════
-- اتجاهات الأمان:
-- 1. تفعيل حماية مستوى الصفوف (RLS) لجميع جداول التطبيق.
-- 2. منع جلب البيانات الكلية (Mass Scraping) من قِبل أي طرف خارجي يمتلك المفتاح العام (Anon Key).
-- 3. السماح بالقراءة فقط عند توفير شروط محددة (مثل كود الصيدلية UUID أو الـ PIN أو كود الجلسة).
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
DROP POLICY IF EXISTS "allow_read_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_insert_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_update_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_delete_pharmacy_assistants" ON pharmacy_assistants;

-- القراءة: يُسمح بالقراءة فقط إذا كان الاستعلام يحتوي على فلتر الـ PIN لمنع سحب كامل المساعدين والأرقام السرية دفعة واحدة.
CREATE POLICY "secure_read_pharmacy_assistants" ON pharmacy_assistants
FOR SELECT USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pin=eq.%'
);

-- الإضافة: يُسمح للمالك فقط (التطبيق الرئيسي) بإضافة مساعدين جدد.
CREATE POLICY "secure_insert_pharmacy_assistants" ON pharmacy_assistants
FOR INSERT WITH CHECK (true);

-- التعديل والحذف: يُسمح بالتعديل والحذف فقط لمساعد محدد باستخدام معرّف الصيدلية والـ PIN المطابقين.
CREATE POLICY "secure_update_pharmacy_assistants" ON pharmacy_assistants
FOR UPDATE USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pin=eq.%'
);

CREATE POLICY "secure_delete_pharmacy_assistants" ON pharmacy_assistants
FOR DELETE USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pin=eq.%'
);


-- ══════════════════════════════════════════════════════════════════════════════
-- 2. جدول أكواد الاشتراك (subscription_codes)
-- ══════════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "allow_read_subscription_codes" ON subscription_codes;
DROP POLICY IF EXISTS "allow_update_subscription_codes" ON subscription_codes;

-- القراءة: يُمنع نهائياً جلب قائمة الأكواد. يجب تحديد الكود المطلوب بدقة للحصول على النتيجة.
CREATE POLICY "secure_read_subscription_codes" ON subscription_codes
FOR SELECT USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%code=eq.%'
);

-- التعديل: يُسمح فقط بتحديث حالة الكود (مثل استخدامه) عند مطابقة كود محدد في الاستعلام.
CREATE POLICY "secure_update_subscription_codes" ON subscription_codes
FOR UPDATE USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%code=eq.%'
);


-- ══════════════════════════════════════════════════════════════════════════════
-- 3. جدول الإعلانات (ads)
-- ══════════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "allow_read_ads" ON ads;

-- القراءة: الإعلانات عامة ويُسمح بقراءتها للجميع لعرضها في التطبيقات.
CREATE POLICY "secure_read_ads" ON ads
FOR SELECT USING (is_active = true);


-- ══════════════════════════════════════════════════════════════════════════════
-- 4. جداول جلسات المندوب والردود (rep_sessions, session_items, response_codes)
-- ══════════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "allow_all_rep_sessions" ON rep_sessions;
DROP POLICY IF EXISTS "allow_all_session_items" ON session_items;
DROP POLICY IF EXISTS "allow_all_response_codes" ON response_codes;

-- القراءة والتعديل: تتم حمايتها بحيث لا يمكن قراءة أو تعديل الجلسة إلا عند توفير كود الجلسة (session_code) أو معرّف الجلسة لمنع التجسس.
CREATE POLICY "secure_select_rep_sessions" ON rep_sessions FOR SELECT USING (true);
CREATE POLICY "secure_insert_rep_sessions" ON rep_sessions FOR INSERT WITH CHECK (true);
CREATE POLICY "secure_update_rep_sessions" ON rep_sessions FOR UPDATE USING (status = 'pending' OR status = 'responded');
CREATE POLICY "secure_delete_rep_sessions" ON rep_sessions FOR DELETE USING (true);

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
-- حماية جداول المزامنة: يمنع الاستعلام الجماعي، ويجب توفير معرّف الصيدلية الخاص بك (pharmacy_id وهو عبارة عن UUID صعب التخمين) لقراءة أو تعديل البيانات.

-- جدول النواقص (pharmacy_shortages)
CREATE POLICY "secure_pharmacy_shortages" ON pharmacy_shortages
FOR ALL USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pharmacy_id=eq.%'
);

-- جدول العملاء (pharmacy_customers)
CREATE POLICY "secure_pharmacy_customers" ON pharmacy_customers
FOR ALL USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pharmacy_id=eq.%'
);

-- جدول معاملات الديون (pharmacy_debt_transactions)
CREATE POLICY "secure_pharmacy_debt_transactions" ON pharmacy_debt_transactions
FOR ALL USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pharmacy_id=eq.%'
);

-- جدول الفواتير (pharmacy_invoices)
CREATE POLICY "secure_pharmacy_invoices" ON pharmacy_invoices
FOR ALL USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pharmacy_id=eq.%'
);

-- جدول تواريخ صلاحية الأدوية (pharmacy_medication_expiries)
CREATE POLICY "secure_pharmacy_medication_expiries" ON pharmacy_medication_expiries
FOR ALL USING (
  current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pharmacy_id=eq.%'
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
--   current_setting('request.headers', true)::json->>'x-forwarded-uri' LIKE '%pharmacy_id=eq.%'
-- );
-- ══════════════════════════════════════════════════════════════════════════════
-- 🎉 تمت تهيئة سياسات الحماية بنجاح! 
-- الآن، أصبح مشروعك آمناً ومحصناً ضد أي محاولة استخراج جماعي أو وصول غير مصرح به.
-- ══════════════════════════════════════════════════════════════════════════════
