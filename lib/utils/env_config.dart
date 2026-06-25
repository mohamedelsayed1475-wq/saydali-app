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
  // وتُحمّل مرّة واحدة – لا يمكن تغييرها بعد التهيئة.
  // ══════════════════════════════════════════════════════════════

  static String? _supabaseUrl;
  static String? _supabaseKey;
  static String? _webPortalBaseUrl;

  // ── Supabase ──
  static String get supabaseUrl {
    _initFromEnv();
    return _supabaseUrl ?? '';
  }

  static String get supabaseKey {
    _initFromEnv();
    return _supabaseKey ?? '';
  }

  // ── Developer Panel ──
  static const devPassword =
      String.fromEnvironment('DEV_PASS', defaultValue: '');

  // ── Admin Bypass Codes (SHA-256 Hashes) ──
  static const adminCode1Hash =
      String.fromEnvironment('ADMIN_CODE_1_HASH', defaultValue: '');

  static const adminCode2Hash =
      String.fromEnvironment('ADMIN_CODE_2_HASH', defaultValue: '');

  // ── Web Portal ──
  static String get webPortalBaseUrl {
    _initFromEnv();
    return _webPortalBaseUrl ?? '';
  }

  // ══════════════════════════════════════════════════════════════
  // تهيئة لمرة واحدة – تُستدعى من SupabaseService.initializeDynamic
  // لتعويض القيم بالقيم المخزنة في قاعدة البيانات.
  // ══════════════════════════════════════════════════════════════
  static void override({String? url, String? key, String? webUrl}) {
    if (url != null && url.isNotEmpty) _supabaseUrl = url;
    if (key != null && key.isNotEmpty) _supabaseKey = key;
    if (webUrl != null && webUrl.isNotEmpty) _webPortalBaseUrl = webUrl;
  }

  static void _initFromEnv() {
    _supabaseUrl ??= const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    _supabaseKey ??= const String.fromEnvironment('SUPABASE_KEY', defaultValue: '');
    _webPortalBaseUrl ??= const String.fromEnvironment('WEB_PORTAL_URL', defaultValue: '');
  }

  // ══════════════════════════════════════════════════════════════
  // فحص هل البيئة مُعدّة صح
  // ══════════════════════════════════════════════════════════════
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
