/// ── إعدادات البيئة (Environment Configuration) ──────────────────────────
/// المفاتيح الحساسة تُقرأ من --dart-define عند البناء.
///
/// ⚠️ مهم: لو الـ Secret في GitHub Actions فاضي، القيمة الافتراضية هتتستخدم.
///
/// مثال البناء:
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxx.supabase.co/rest/v1 \
///   --dart-define=SUPABASE_KEY=your_key \
///   --dart-define=DEV_PASS=your_dev_password \
///   --dart-define=ADMIN_CODE_1=CODE1 \
///   --dart-define=ADMIN_CODE_2=CODE2 \
///   --dart-define=WEB_PORTAL_URL=https://your-site.github.io/app
/// ```
///
/// في الـ CI/CD (GitHub Actions)، أضف هذه القيم كـ secrets.
class EnvConfig {
  // ══════════════════════════════════════════════════════════════
  // القيم الخام من البيئة (قد تكون فارغة لو الـ Secret مش مضبوط)
  // ══════════════════════════════════════════════════════════════
  static const _rawSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _rawSupabaseKey = String.fromEnvironment('SUPABASE_KEY');
  static const _rawDevPass = String.fromEnvironment('DEV_PASS');
  static const _rawAdminCode1 = String.fromEnvironment('ADMIN_CODE_1');
  static const _rawAdminCode2 = String.fromEnvironment('ADMIN_CODE_2');
  static const _rawWebPortalUrl = String.fromEnvironment('WEB_PORTAL_URL');

  // ══════════════════════════════════════════════════════════════
  // القيم النهائية مع Fallback آمن ضد القيم الفارغة
  // ══════════════════════════════════════════════════════════════

  // ── Supabase ──
  static const supabaseUrl = _rawSupabaseUrl == ''
      ? 'https://kmrszdvsdqfaaksqhnqf.supabase.co/rest/v1'
      : _rawSupabaseUrl;

  static const supabaseKey = _rawSupabaseKey == ''
      ? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImttcnN6ZHZzZHFmYWFrc3FobnFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0OTYwNTIsImV4cCI6MjA5MzA3MjA1Mn0.ac8p574OhOG9OPuHzCDOxeHNdEiUkFEtFG_l535Pl3A'
      : _rawSupabaseKey;

  // ── Developer Panel ──
  static const devPassword = _rawDevPass == ''
      ? 'dev@saydali2026'
      : _rawDevPass;

  // ── Admin Bypass Codes ──
  static const adminCode1 = _rawAdminCode1 == ''
      ? 'ADMIN2026'
      : _rawAdminCode1;

  static const adminCode2 = _rawAdminCode2 == ''
      ? 'DEV@SAYDALI2026'
      : _rawAdminCode2;

  // ── Web Portal ──
  static const webPortalBaseUrl = _rawWebPortalUrl == ''
      ? 'https://mohamedelsayed1475-wq.github.io/saydali-app1'
      : _rawWebPortalUrl;
}
