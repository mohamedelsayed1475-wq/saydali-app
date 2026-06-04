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
ALTER TABLE pharmacies ENABLE ROW LEVEL SECURITY;
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
ALTER TABLE renewal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_devices ENABLE ROW LEVEL SECURITY;

-- ══════════════════════════════════════════════════════════════════════════════
-- ⚠️ تنظيف ديناميكي شامل لجميع السياسات القديمة في الـ public schema لمنع التكرار وأي سياسات غير آمنة
-- ══════════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN 
    SELECT policyname, tablename 
    FROM pg_policies 
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
  END LOOP;
END $$;


-- ══════════════════════════════════════════════════════════════════════════════
-- 0. جدول الصيدليات (pharmacies) — سياسات الوصول
-- ══════════════════════════════════════════════════════════════════════════════
-- القراءة: مفتوحة للـ authenticated والمساعدين (الممررين في الهيدر x-pharmacy-id)، ومغلقة للـ anon المباشر
-- الإضافة: مفتوحة للـ authenticated فقط (تسجيل صيدلية جديدة) أو الـ service_role
-- التعديل/الحذف: مقيدة بـ pharmacy_id أو الـ authenticated/service_role

DROP POLICY IF EXISTS "anon_all" ON pharmacies;
DROP POLICY IF EXISTS "secure_select_pharmacies" ON pharmacies;
DROP POLICY IF EXISTS "secure_select_pharmacies_anon" ON pharmacies;
DROP POLICY IF EXISTS "secure_insert_pharmacies" ON pharmacies;
DROP POLICY IF EXISTS "secure_update_pharmacies" ON pharmacies;
DROP POLICY IF EXISTS "secure_update_pharmacies_anon" ON pharmacies;
DROP POLICY IF EXISTS "secure_delete_pharmacies" ON pharmacies;

-- القراءة للـ authenticated والـ service_role
CREATE POLICY "secure_select_pharmacies" ON pharmacies
FOR SELECT TO authenticated, service_role USING (auth.uid() IS NOT NULL);

-- القراءة للـ anon فقط عند إرسال الهيدر الصحيح المطابق لمعرف الصيدلية
CREATE POLICY "secure_select_pharmacies_anon" ON pharmacies
FOR SELECT TO anon USING (
  id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- الإضافة للـ authenticated والـ service_role
CREATE POLICY "secure_insert_pharmacies" ON pharmacies
FOR INSERT TO authenticated, service_role WITH CHECK (auth.uid() IS NOT NULL);

-- التعديل للـ authenticated والـ service_role
CREATE POLICY "secure_update_pharmacies" ON pharmacies
FOR UPDATE TO authenticated, service_role USING (auth.uid() IS NOT NULL);

-- التعديل للـ anon فقط عند إرسال الهيدر الصحيح المطابق لمعرف الصيدلية
CREATE POLICY "secure_update_pharmacies_anon" ON pharmacies
FOR UPDATE TO anon USING (
  id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- الحذف للـ authenticated والـ service_role
CREATE POLICY "secure_delete_pharmacies" ON pharmacies
FOR DELETE TO authenticated, service_role USING (auth.uid() IS NOT NULL);

-- ══════════════════════════════════════════════════════════════════════════════
-- 1. جدول مساعدي الصيدلية (pharmacy_assistants)
-- ══════════════════════════════════════════════════════════════════════════════
-- الحماية: يُسمح للـ authenticated والـ service_role بالوصول الكامل.
-- بالنسبة للـ anon، يُشترط تطابق pharmacy_id مع الهيدر x-pharmacy-id فقط لمنع الوصول المباشر.
-- ══════════════════════════════════════════════════════════════════════════════

-- تحديث الهيكل: إضافة الأعمدة المفقودة لجدول المساعدين
ALTER TABLE pharmacy_assistants ADD COLUMN IF NOT EXISTS can_manage_shortages BOOLEAN DEFAULT TRUE;
ALTER TABLE pharmacy_assistants ADD COLUMN IF NOT EXISTS can_manage_reps BOOLEAN DEFAULT FALSE;

DROP POLICY IF EXISTS "anon_all" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_read_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_insert_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_update_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "allow_delete_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_read_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_all_pharmacy_assistants_auth" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_select_pharmacy_assistants_anon" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_insert_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_insert_pharmacy_assistants_anon" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_update_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_update_pharmacy_assistants_anon" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_delete_pharmacy_assistants" ON pharmacy_assistants;
DROP POLICY IF EXISTS "secure_delete_pharmacy_assistants_anon" ON pharmacy_assistants;

-- وصول كامل للـ authenticated والـ service_role
CREATE POLICY "secure_all_pharmacy_assistants_auth" ON pharmacy_assistants
FOR ALL TO authenticated, service_role USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

-- القراءة للـ anon فقط عند إرسال الهيدر المطابق
CREATE POLICY "secure_select_pharmacy_assistants_anon" ON pharmacy_assistants
FOR SELECT TO anon USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- الإضافة للـ anon فقط عند إرسال الهيدر المطابق
CREATE POLICY "secure_insert_pharmacy_assistants_anon" ON pharmacy_assistants
FOR INSERT TO anon WITH CHECK (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- التعديل للـ anon فقط عند إرسال الهيدر المطابق
CREATE POLICY "secure_update_pharmacy_assistants_anon" ON pharmacy_assistants
FOR UPDATE TO anon USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- الحذف للـ anon فقط عند إرسال الهيدر المطابق
CREATE POLICY "secure_delete_pharmacy_assistants_anon" ON pharmacy_assistants
FOR DELETE TO anon USING (
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
-- 4. جداول جلسات المندوب والردود (rep_sessions, session_items, response_codes, renewal_requests)
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

DROP POLICY IF EXISTS "secure_select_renewal_requests" ON renewal_requests;
DROP POLICY IF EXISTS "secure_insert_renewal_requests" ON renewal_requests;
DROP POLICY IF EXISTS "secure_update_renewal_requests" ON renewal_requests;
DROP POLICY IF EXISTS "secure_delete_renewal_requests" ON renewal_requests;

-- ─── 4.1 جدول جلسات المندوب (rep_sessions) ───
-- القراءة: يُسمح للصيدلية بقراءة جلساتها الخاصة، ويُسمح للمندوبين بقراءة الجلسات النشطة أو المنتهية حديثاً (أقل من 3 أيام)
CREATE POLICY "secure_select_rep_sessions" ON rep_sessions
FOR SELECT USING (
  pharmacy_id IS NULL OR
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
  OR expires_at > now() - interval '3 days'
);

-- الإضافة: تُضاف الجلسات فقط من قِبل الصيدلية المالكة لها
CREATE POLICY "secure_insert_rep_sessions" ON rep_sessions
FOR INSERT WITH CHECK (
  pharmacy_id IS NULL OR
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

-- التعديل: تُعدل الجلسة من قِبل الصيدلية، أو من قِبل المندوب (فقط لتحديث الحالة ومدة الصلاحية إذا كانت الجلسة معلقة ولم تنتهِ صلاحيتها بعد)
CREATE POLICY "secure_update_rep_sessions" ON rep_sessions
FOR UPDATE USING (
  pharmacy_id IS NULL OR
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
  OR (status = 'pending' AND expires_at > now())
);

-- الحذف: متاح فقط للصيدلية المالكة للجلسة
CREATE POLICY "secure_delete_rep_sessions" ON rep_sessions
FOR DELETE USING (
  pharmacy_id IS NULL OR
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);


-- ─── 4.2 جدول عناصر الجلسة (session_items) ───
-- القراءة: للصيدلية المالكة أو للمندوبين المهتمين بالجلسات النشطة/المعدلة حديثاً
CREATE POLICY "secure_select_session_items" ON session_items
FOR SELECT USING (
  session_id IN (
    SELECT id FROM rep_sessions 
    WHERE pharmacy_id IS NULL 
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
    OR expires_at > now() - interval '3 days'
  )
);

-- الإضافة: الصيدلية فقط هي من تضيف أصناف إلى الجلسة
CREATE POLICY "secure_insert_session_items" ON session_items
FOR INSERT WITH CHECK (
  session_id IN (
    SELECT id FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
  )
);

-- التعديل: الصيدلية تعدل الأصناف، أو المندوب يملأ ردوده طالما الجلسة نشطة ومعلقة
CREATE POLICY "secure_update_session_items" ON session_items
FOR UPDATE USING (
  session_id IN (
    SELECT id FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
    OR (status = 'pending' AND expires_at > now())
  )
);

-- الحذف: الصيدلية فقط من تحذف أصناف من الجلسة
CREATE POLICY "secure_delete_session_items" ON session_items
FOR DELETE USING (
  session_id IN (
    SELECT id FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
  )
);


-- ─── 4.3 جدول أكواد الردود (response_codes) ───
-- القراءة: للصيدلية أو للمندوب للحصول على كود الرد المسجل للجلسة النشطة
CREATE POLICY "secure_select_response_codes" ON response_codes
FOR SELECT USING (
  session_id IN (
    SELECT id FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
    OR expires_at > now() - interval '3 days'
  )
);

-- الإضافة: المندوب أو الصيدلية تسجل كود الرد عند إنهاء الجلسة النشطة بنجاح
CREATE POLICY "secure_insert_response_codes" ON response_codes
FOR INSERT WITH CHECK (
  session_id IN (
    SELECT id FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
    OR (status = 'pending' AND expires_at > now())
  )
);

-- الحذف: متاح فقط للصيدلية عند إدارة أو حذف السجلات
CREATE POLICY "secure_delete_response_codes" ON response_codes
FOR DELETE USING (
  session_id IN (
    SELECT id FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
  )
);


-- ─── 4.4 جدول طلبات التجديد (renewal_requests) ───
-- القراءة: للصيدلية لمتابعة طلبات تجديد الجلسات المنتهية الخاصة بها
CREATE POLICY "secure_select_renewal_requests" ON renewal_requests
FOR SELECT USING (
  session_code IN (
    SELECT session_code FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
  )
);

-- الإضافة: يُسمح للمندوب بتقديم طلب تجديد إذا كان كود الجلسة صحيحاً وموجوداً بقاعدة البيانات
CREATE POLICY "secure_insert_renewal_requests" ON renewal_requests
FOR INSERT WITH CHECK (
  session_code IN (
    SELECT session_code FROM rep_sessions
  )
);

-- التعديل: للصيدلية فقط لتغيير حالة الطلب (مثلاً من معلق إلى تم التجديد)
CREATE POLICY "secure_update_renewal_requests" ON renewal_requests
FOR UPDATE USING (
  session_code IN (
    SELECT session_code FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
  )
);

-- الحذف: للصيدلية فقط لمسح الطلبات القديمة
CREATE POLICY "secure_delete_renewal_requests" ON renewal_requests
FOR DELETE USING (
  session_code IN (
    SELECT session_code FROM rep_sessions 
    WHERE pharmacy_id IS NULL
    OR pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
  )
);


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
DROP POLICY IF EXISTS "anon_all" ON pharmacy_customers;
DROP POLICY IF EXISTS "secure_pharmacy_customers" ON pharmacy_customers;
DROP POLICY IF EXISTS "secure_all_pharmacy_customers_auth" ON pharmacy_customers;
DROP POLICY IF EXISTS "secure_all_pharmacy_customers_anon" ON pharmacy_customers;

-- وصول كامل للـ authenticated والـ service_role
CREATE POLICY "secure_all_pharmacy_customers_auth" ON pharmacy_customers
FOR ALL TO authenticated, service_role USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

-- وصول للـ anon مقيد فقط بمطابقة الهيدر x-pharmacy-id
CREATE POLICY "secure_all_pharmacy_customers_anon" ON pharmacy_customers
FOR ALL TO anon USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
) WITH CHECK (
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


-- ══════════════════════════════════════════════════════════════════════════════
-- 6. إصلاح مشكلة Function Search Path Mutable في الدوال الأمنية (جميع الدوال)
-- ══════════════════════════════════════════════════════════════════════════════
-- لتفادي هجمات حقن مسار البحث (Search Path Hijacking)، نقوم بتثبيت مسار البحث 
-- على public و pg_temp لجميع الدوال التي تعمل بصلاحيات المنشئ (SECURITY DEFINER)
DO $$
DECLARE
  func_record RECORD;
BEGIN
  FOR func_record IN 
    SELECT p.oid::regprocedure AS func_signature
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.prosecdef = true
  LOOP
    EXECUTE 'ALTER FUNCTION ' || func_record.func_signature || ' SET search_path = public, pg_temp';
  END LOOP;
END $$;


-- ══════════════════════════════════════════════════════════════════════════════
-- 7. إصلاح مشكلة Public Can Execute SECURITY DEFINER (جميع الدوال)
-- ══════════════════════════════════════════════════════════════════════════════
-- الدوال التي تعمل بصلاحيات المنشئ يجب سحب إمكانية تنفيذها من العامة (PUBLIC)
-- ونمنح الصلاحية بشكل صريح للأدوار المسموح لها:
-- (المستخدمين الموثقين والـ service_role، ونسمح لـ anon فقط على دوال تقديم ردود المندوب)
DO $$
DECLARE
  func_record RECORD;
BEGIN
  FOR func_record IN 
    SELECT p.oid::regprocedure AS func_signature, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.prosecdef = true
  LOOP
    -- إلغاء صلاحية التنفيذ من العامة (PUBLIC)
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || func_record.func_signature || ' FROM PUBLIC';
    
    -- منح الصلاحية للأدوار الآمنة
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || func_record.func_signature || ' TO authenticated, service_role';
    
    -- إذا كانت دالة رد المندوب، يجب السماح للـ anon بتنفيذها
    IF func_record.proname LIKE 'submit_rep_response%' THEN
      EXECUTE 'GRANT EXECUTE ON FUNCTION ' || func_record.func_signature || ' TO anon';
    END IF;
  END LOOP;
END $$;


-- ══════════════════════════════════════════════════════════════════════════════
-- 8. حماية Storage Bucket (ads-images) ومنع سرد الملفات (Listing) للعامة
-- ══════════════════════════════════════════════════════════════════════════════
-- نقوم بحذف أي سياسة تسمح للعامة (anon) بسرد أو استعلام جدول storage.objects للـ bucket 'ads-images'
-- ونسمح فقط بالوصول للمستخدمين الموثقين أو الـ service_role
-- (ملاحظة: تظل الصور قابلة للتحميل للعامة عبر روابطها المباشرة لأن الـ Bucket معرف كـ Public)
DROP POLICY IF EXISTS "Allow public select on ads-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public listing on ads-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read on ads-images" ON storage.objects;
DROP POLICY IF EXISTS "Give public access to ads-images" ON storage.objects;
DROP POLICY IF EXISTS "ads-images-public-listing" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated listing of ads-images" ON storage.objects;

-- إنشاء سياسة تسمح للموثقين والـ service_role فقط بسرد واستعلام الملفات
CREATE POLICY "Allow authenticated listing of ads-images" ON storage.objects
FOR SELECT TO authenticated, service_role
USING (bucket_id = 'ads-images');


-- ══════════════════════════════════════════════════════════════════════════════
-- 9. حماية جداول المزامنة والأجهزة (sync_confirmations, sync_devices)
-- ══════════════════════════════════════════════════════════════════════════════
-- وصول كامل للـ authenticated والـ service_role، وللـ anon مقيد بـ x-pharmacy-id
CREATE POLICY "secure_all_sync_confirmations_auth" ON sync_confirmations
FOR ALL TO authenticated, service_role USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "secure_all_sync_confirmations_anon" ON sync_confirmations
FOR ALL TO anon USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
) WITH CHECK (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);

CREATE POLICY "secure_all_sync_devices_auth" ON sync_devices
FOR ALL TO authenticated, service_role USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "secure_all_sync_devices_anon" ON sync_devices
FOR ALL TO anon USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
) WITH CHECK (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);


-- ══════════════════════════════════════════════════════════════════════════════
-- 10. تعديل الدوال الأمنية لتكون SECURITY INVOKER وتقييد تنفيذها
-- ══════════════════════════════════════════════════════════════════════════════
-- الدوال المستهدفة:
-- add_ad_rpc, add_subscription_code, add_subscription_code_rpc,
-- delete_subscription_code, delete_subscription_code_rpc,
-- submit_rep_response, update_subscription_code, update_subscription_code_rpc
--
-- نقوم بتحويلها إلى SECURITY INVOKER وسحب صلاحيات التنفيذ من الجميع باستثناء service_role
DO $$
DECLARE
  func_record RECORD;
BEGIN
  FOR func_record IN 
    SELECT p.oid::regprocedure AS func_signature, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
      AND p.proname IN (
        'add_ad_rpc', 
        'add_subscription_code', 
        'add_subscription_code_rpc',
        'delete_subscription_code', 
        'delete_subscription_code_rpc',
        'submit_rep_response', 
        'update_subscription_code', 
        'update_subscription_code_rpc'
      )
  LOOP
    -- تغيير الصلاحية لتكون SECURITY INVOKER
    EXECUTE 'ALTER FUNCTION ' || func_record.func_signature || ' SECURITY INVOKER';
    
    -- سحب صلاحية التنفيذ من العامة (PUBLIC) والمستخدمين anon و authenticated
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || func_record.func_signature || ' FROM PUBLIC';
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || func_record.func_signature || ' FROM anon';
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || func_record.func_signature || ' FROM authenticated';
    
    -- منح الصلاحية حصرياً للـ service_role
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || func_record.func_signature || ' TO service_role';
    
    RAISE NOTICE 'Secured function: %', func_record.func_signature;
  END LOOP;
END $$;


-- ══════════════════════════════════════════════════════════════════════════════
-- 11. سياسات الحماية لجداول delegates, orders, pharmacists
-- ══════════════════════════════════════════════════════════════════════════════
-- هذه الجداول عندها RLS مفعّل بدون سياسات (مما يمنع الوصول تماماً).
-- نضيف سياسات مناسبة حسب طبيعة كل جدول.
-- ══════════════════════════════════════════════════════════════════════════════

-- ─── 11.1 جدول المندوبين (delegates) ───
DROP POLICY IF EXISTS "secure_all_delegates_auth" ON delegates;
DROP POLICY IF EXISTS "secure_all_delegates_anon" ON delegates;

CREATE POLICY "secure_all_delegates_auth" ON delegates
FOR ALL TO authenticated, service_role USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "secure_all_delegates_anon" ON delegates
FOR ALL TO anon USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
) WITH CHECK (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);


-- ─── 11.2 جدول الطلبات (orders) ───
DROP POLICY IF EXISTS "secure_all_orders_auth" ON orders;
DROP POLICY IF EXISTS "secure_all_orders_anon" ON orders;

CREATE POLICY "secure_all_orders_auth" ON orders
FOR ALL TO authenticated, service_role USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "secure_all_orders_anon" ON orders
FOR ALL TO anon USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
) WITH CHECK (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);


-- ─── 11.3 جدول الصيادلة (pharmacists) ───
DROP POLICY IF EXISTS "secure_all_pharmacists_auth" ON pharmacists;
DROP POLICY IF EXISTS "secure_all_pharmacists_anon" ON pharmacists;

CREATE POLICY "secure_all_pharmacists_auth" ON pharmacists
FOR ALL TO authenticated, service_role USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "secure_all_pharmacists_anon" ON pharmacists
FOR ALL TO anon USING (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
) WITH CHECK (
  pharmacy_id::text = coalesce(current_setting('request.headers', true)::json->>'x-pharmacy-id', '')
);


-- ══════════════════════════════════════════════════════════════════════════════
-- 12. تقييد سرد ملفات ads-images من قبل anon (حل تحذير Security Advisor)
-- ══════════════════════════════════════════════════════════════════════════════
-- الصور تظل قابلة للتحميل عبر روابطها المباشرة لأن الـ Bucket عام
-- لكن نمنع الـ anon من استعلام/سرد كافة الملفات في الـ bucket
DROP POLICY IF EXISTS "Deny anon listing on ads-images" ON storage.objects;
CREATE POLICY "Deny anon listing on ads-images" ON storage.objects
FOR SELECT TO anon USING (
  bucket_id != 'ads-images'
);
