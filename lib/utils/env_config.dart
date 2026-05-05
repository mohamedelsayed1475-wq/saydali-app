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
    defaultValue: 'https://kmrszdvsdqfaaksqhnqf.supabase.co/rest/v1',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImttcnN6ZHZzZHFmYWFrc3FobnFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0OTYwNTIsImV4cCI6MjA5MzA3MjA1Mn0.ac8p574OhOG9OPuHzCDOxeHNdEiUkFEtFG_l535Pl3A',
  );

  // ── Developer Panel ──────────────────────────────────────────────────
  static const devPassword = String.fromEnvironment(
    'DEV_PASS',
    defaultValue: 'dev@saydali2026',
  );

  // ── Admin Bypass Codes ──────────────────────────────────────────────────
  static const adminCode1 = String.fromEnvironment(
    'ADMIN_CODE_1',
    defaultValue: 'ADMIN2026',
  );

  static const adminCode2 = String.fromEnvironment(
    'ADMIN_CODE_2',
    defaultValue: 'DEV@SAYDALI2026',
  );

  // ── Web Portal ──────────────────────────────────────────────────
  static const webPortalBaseUrl = String.fromEnvironment(
    'WEB_PORTAL_URL',
    defaultValue: 'https://mohamedelsayed1475-wq.github.io/saydali-app1',
  );
}
