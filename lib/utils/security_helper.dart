import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import 'env_config.dart';
import '../database/database_helper.dart';

/// ── حماية القيم الحساسة بتوقيع HMAC ──────────────────────────────
/// يمنع التلاعب بقيم الاشتراك في قاعدة البيانات المحلية
class SecurityHelper {
  SecurityHelper._();

  /// ── توليد معرف فريد UUID v4 محلياً ──
  static String generateUUID() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // version 4
    values[8] = (values[8] & 0x3f) | 0x80; // variant 10
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  // مفتاح التوقيع (مزيج من مفاتيح البيئة + ثابت)
  static String get _secretKey {
    const salt = 'SaYdAlI_pRo_2026_sEcUrE';
    final envPart = EnvConfig.supabaseKey.isNotEmpty
        ? EnvConfig.supabaseKey.substring(0, 8)
        : 'fallback';
    return '$salt$envPart';
  }

  /// ── توقيع قيمة بـ HMAC-SHA256 ──
  static String signValue(String key, String value) {
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    final digest = hmac.convert(utf8.encode('$key:$value'));
    return digest.toString();
  }

  /// ── التحقق من صحة التوقيع ──
  static bool verifyValue(String key, String value, String signature) {
    final expected = signValue(key, value);
    return expected == signature;
  }

  /// ── حفظ قيمة موقعة في الإعدادات ──
  static Future<void> saveSignedSetting(String key, String value) async {
    final db = DatabaseHelper.instance;
    await db.setSetting(key, value);
    await db.setSetting('${key}_sig', signValue(key, value));
  }

  /// ── قراءة قيمة موقعة والتحقق منها ──
  /// يرجع القيمة لو التوقيع صحيح، أو null لو تم التلاعب
  static Future<String?> readSignedSetting(String key) async {
    final db = DatabaseHelper.instance;
    final value = await db.getSetting(key);
    if (value == null) return null;

    final signature = await db.getSetting('${key}_sig');
    if (signature == null) {
      // لو مفيش توقيع (مستخدم قديم) → نوقع ونرجع القيمة
      await db.setSetting('${key}_sig', signValue(key, value));
      return value;
    }

    if (verifyValue(key, value, signature)) {
      return value; // التوقيع صحيح
    }

    // ⚠️ تم التلاعب! امسح القيمة
    debugPrint('🚨 تم اكتشاف تلاعب في: $key');
    await db.setSetting(key, '');
    await db.setSetting('${key}_sig', '');
    return null;
  }

  /// ── الحصول على الوقت من السيرفر ──
  /// يمنع المستخدم من تغيير ساعة الجهاز لتمديد الاشتراك
  static Future<DateTime?> getServerTime() async {
    // 1. محاولة Supabase RPC (get_server_time يرجع NOW())
    if (EnvConfig.supabaseUrl.isNotEmpty) {
      try {
        final res = await http
            .post(
              Uri.parse('${EnvConfig.supabaseUrl}/rpc/get_server_time'),
              headers: {
                'apikey': EnvConfig.supabaseKey,
                'Authorization': 'Bearer ${EnvConfig.supabaseKey}',
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final serverTime = jsonDecode(res.body) as String?;
          if (serverTime != null) {
            return DateTime.tryParse(serverTime);
          }
        }
      } catch (_) {}
    }

    // Fallback: محاولة HEAD على Supabase
    if (EnvConfig.supabaseUrl.isNotEmpty) {
      try {
        final res = await http
            .head(Uri.parse(EnvConfig.supabaseUrl))
            .timeout(const Duration(seconds: 5));
        final dateHeader = res.headers['date'];
        if (dateHeader != null) {
          return HttpDate.parse(dateHeader);
        }
      } catch (_) {}
    }

    return null; // مفيش إنترنت
  }

  /// ── فحص الاشتراك المحلي مع حماية ──
  /// يرجع true لو الاشتراك صالح وما تمش التلاعب بيه
  static Future<bool> isSubscriptionValid() async {
    return true; // تفعيل دائم مدى الحياة للمشتري محلياً
  }

  /// ── التحقق السحابي من الاشتراك ──
  static Future<bool?> verifySubscriptionCloud() async {
    return true; // تفعيل دائم
  }

  // ══════════════════════════════════════════════════════════════
  // حماية الجهاز (Root / Jailbreak Detection)
  // ══════════════════════════════════════════════════════════════

  /// ── فحص إذا الجهاز rooted/jailbroken ──
  static Future<bool> isDeviceCompromised() async {
    try {
      final jailbroken = await FlutterJailbreakDetection.jailbroken;
      if (jailbroken) {
        debugPrint('🚨 جهاز مشبوه! يحتوي على صلاحيات الروت (Root)');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ فحص الجهاز فشل: $e');
      return false;
    }
  }

  /// ── فحص شامل للأمان عند فتح التطبيق ──
  static Future<List<String>> runSecurityChecks() async {
    final warnings = <String>[];

    try {
      final jailbroken = await FlutterJailbreakDetection.jailbroken;

      if (jailbroken) {
        warnings.add('📱 جهازك يحتوي على صلاحيات الروت (Root) - قد تكون بياناتك معرضة للخطر');
      }
    } catch (e) {
      debugPrint('⚠️ فحص أمان الجهاز فشل: $e');
    }

    // 2. فحص التلاعب بالاشتراك
    final db = DatabaseHelper.instance;
    final expiry = await db.getSetting('subscription_expiry');
    final sig = await db.getSetting('subscription_expiry_sig');
    if (expiry != null && expiry.isNotEmpty && sig != null) {
      if (!verifyValue('subscription_expiry', expiry, sig)) {
        warnings.add('🔐 تم اكتشاف تلاعب في بيانات الاشتراك');
      }
    }

    // 3. فحص وضع Debug
    if (kDebugMode) {
      warnings.add('🐛 التطبيق يعمل في وضع التطوير');
    }

    return warnings;
  }

  /// ── تشفير PIN باستخدام PBKDF2-SHA256 حقيقي ──
  /// salt = 16 bytes random, iterations = 200000, dkLen = 32 bytes
  static String hashPin(String pin, {String? saltBase64}) {
    final rng = SecureRandom("Fortuna")
      ..seed(KeyParameter(utf8.encode(generateUUID())));
    final salt = saltBase64 != null
        ? base64.decode(saltBase64)
        : rng.nextBytes(16);

    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(salt, 200000, 32));
    final derived = derivator.process(utf8.encode(pin));

    final saltEncoded = base64.encode(salt);
    final hashEncoded = base64.encode(derived);
    return '$saltEncoded\$$hashEncoded';
  }

  /// ── التحقق من صحة الـ PIN (مع دعم Plaintext القديم) ──
  static bool verifyPin(String enteredPin, String storedPinValue) {
    if (!storedPinValue.contains('\$')) {
      // Legacy compatibility: Plaintext fallback
      return enteredPin == storedPinValue;
    }

    final parts = storedPinValue.split('\$');
    if (parts.length != 2) return false;

    final saltB64 = parts[0];
    final storedHash = parts[1];
    final expected = hashPin(enteredPin, saltBase64: saltB64);
    final expectedHash = expected.split('\$')[1];
    // Timing-safe comparison
    if (storedHash.length != expectedHash.length) return false;
    int result = 0;
    for (int i = 0; i < storedHash.length; i++) {
      result |= storedHash.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return result == 0;
  }

  /// ── تشفير SHA-256 للنصوص ──
  static String hashSHA256(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// ── التحقق من كود الإدارة المشفر ──
  static bool verifyAdminCode(String enteredCode, String storedHash) {
    if (storedHash.isEmpty) return false;
    final hashed = hashSHA256(enteredCode);
    return hashed == storedHash;
  }
}
