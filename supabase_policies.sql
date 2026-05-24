-- سياسات الحماية (RLS Policies) لجدول pharmacy_assistants في Supabase
-- قم بنسخ هذا الكود وتشغيله في SQL Editor الخاص بـ Supabase Dashboard

-- 1. تفعيل سياسة الحماية RLS (إذا لم تكن مفعلة بالفعل)
ALTER TABLE pharmacy_assistants ENABLE ROW LEVEL SECURITY;

-- 2. سياسة السماح بالقراءة (SELECT)
-- تسمح لجميع المستخدمين (أو الأجهزة التي تمتلك مفتاح الـ API) بقراءة بيانات المساعدين
-- لمطابقتها للـ PIN أثناء تسجيل الدخول
DROP POLICY IF EXISTS "allow_read_pharmacy_assistants" ON pharmacy_assistants;
CREATE POLICY "allow_read_pharmacy_assistants" 
ON pharmacy_assistants
FOR SELECT 
USING (true);

-- 3. سياسة السماح بالإدراج (INSERT)
-- تسمح بإضافة مساعدين جدد من قبل التطبيق
DROP POLICY IF EXISTS "allow_insert_pharmacy_assistants" ON pharmacy_assistants;
CREATE POLICY "allow_insert_pharmacy_assistants"
ON pharmacy_assistants
FOR INSERT
WITH CHECK (true);

-- 4. سياسة السماح بالتحديث (UPDATE)
-- تسمح بتعديل بيانات المساعدين أو حالة النشاط
DROP POLICY IF EXISTS "allow_update_pharmacy_assistants" ON pharmacy_assistants;
CREATE POLICY "allow_update_pharmacy_assistants"
ON pharmacy_assistants
FOR UPDATE
USING (true);

-- 5. سياسة السماح بالحذف (DELETE)
-- تسمح بحذف المساعدين
DROP POLICY IF EXISTS "allow_delete_pharmacy_assistants" ON pharmacy_assistants;
CREATE POLICY "allow_delete_pharmacy_assistants"
ON pharmacy_assistants
FOR DELETE
USING (true);
