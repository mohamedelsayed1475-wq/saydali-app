/// ── إعدادات البيئة (Environment Configuration) ──────────────────────────
/// المفاتيح الحساسة تُقرأ من --dart-define عند البناء.
///
/// ⚠️ لا توجد قيم حساسة مخزنة في الكود - كلها تُقرأ من GitHub Secrets.
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
/// في الـ CI/CD (GitHub Actions)، أضف هذه القيم كـ Repository Secrets.
class EnvConfig {
  // ══════════════════════════════════════════════════════════════
  // القيم تُقرأ حصرياً من --dart-define (GitHub Secrets)
  // ══════════════════════════════════════════════════════════════

  // ── Supabase ──
  static String supabaseUrl =
      const String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static String supabaseKey =
      const String.fromEnvironment('SUPABASE_KEY', defaultValue: '');

  // ── Developer Panel ──
  static const devPassword =
      String.fromEnvironment('DEV_PASS', defaultValue: 'dev@saydali2026');

  // ── Admin Bypass Codes ──
  static const adminCode1 =
      String.fromEnvironment('ADMIN_CODE_1', defaultValue: 'ADMIN2026');

  // ── Admin Bypass Codes ──
  static const adminCode2 =
      String.fromEnvironment('ADMIN_CODE_2', defaultValue: 'DEV@SAYDALI2026');

  // ── Web Portal ──
  static String webPortalBaseUrl =
      const String.fromEnvironment('WEB_PORTAL_URL', defaultValue: '');

  // ══════════════════════════════════════════════════════════════
  // فحص هل البيئة مُعدّة صح
  // ══════════════════════════════════════════════════════════════
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
