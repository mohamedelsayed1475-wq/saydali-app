/// ── إعدادات البيئة (Environment Configuration) ──────────────────────────
/// المفاتيح الحساسة تُقرأ من --dart-define عند البناء.
///
/// مثال البناء:
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxx.supabase.co/rest/v1 \
///   --dart-define=SUPABASE_KEY=your_key \
///   --dart-define=DEV_PASS=your_dev_password \
///   --dart-define=ADMIN_CODE_1=CODE1 \
///   --dart-define=ADMIN_CODE_2=CODE2
/// ```
///
/// في الـ CI/CD (GitHub Actions)، أضف هذه القيم كـ secrets.
class EnvConfig {
  // ── Supabase ──────────────────────────────────────────────────
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: '',
  );

  // ── Developer Panel ──────────────────────────────────────────────────
  static const devPassword = String.fromEnvironment(
    'DEV_PASS',
    defaultValue: '',
  );

  // ── Admin Bypass Codes ──────────────────────────────────────────────────
  static const adminCode1 = String.fromEnvironment(
    'ADMIN_CODE_1',
    defaultValue: '',
  );

  static const adminCode2 = String.fromEnvironment(
    'ADMIN_CODE_2',
    defaultValue: '',
  );

  // ── Web Portal ──────────────────────────────────────────────────
  static const webPortalBaseUrl = String.fromEnvironment(
    'WEB_PORTAL_URL',
    defaultValue: '',
  );
}
