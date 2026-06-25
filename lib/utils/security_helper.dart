import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:http/http.dart' as http;
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
    try {
      // استخدام WorldTimeAPI كمصدر موثوق للوقت
      final res = await http
          .get(Uri.parse('https://worldtimeapi.org/api/ip'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return DateTime.parse(data['datetime']);
      }
    } catch (_) {}

    // Fallback: محاولة Supabase
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

  /// ── تشفير PIN باستخدام PBKDF2-like SHA256 ──
  static String hashPin(String pin, {String? salt}) {
    final cleanSalt = salt ?? generateUUID().substring(0, 8);
    var h = utf8.encode('$cleanSalt$pin');
    for (var i = 0; i < 10000; i++) {
      h = sha256.convert(h).bytes;
    }
    final hash = base64.encode(h);
    return '$cleanSalt\$$hash'; // Salt inside the value itself
  }

  /// ── التحقق من صحة الـ PIN (مع دعم Plaintext القديم) ──
  static bool verifyPin(String enteredPin, String storedPinValue) {
    if (!storedPinValue.contains('\$')) {
      // Legacy compatibility: Plaintext fallback
      return enteredPin == storedPinValue;
    }

    final parts = storedPinValue.split('\$');
    if (parts.length != 2) return false;

    final salt = parts[0];
    final expected = hashPin(enteredPin, salt: salt);
    return expected == storedPinValue;
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
