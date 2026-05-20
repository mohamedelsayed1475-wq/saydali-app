import 'dart:convert';
import 'dart:io';
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
    final expiryStr = await readSignedSetting('subscription_expiry');
    if (expiryStr == null || expiryStr.isEmpty) return false;

    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null) return false;

    // محاولة استخدام وقت السيرفر
    final serverTime = await getServerTime();
    final now = serverTime ?? DateTime.now();

    // لو فرق الوقت بين الجهاز والسيرفر أكتر من يوم ← مشبوه
    if (serverTime != null) {
      final diff = DateTime.now().difference(serverTime).abs();
      if (diff.inHours > 24) {
        debugPrint('🚨 فرق التوقيت مشبوه: ${diff.inHours} ساعة');
        return expiry.isAfter(serverTime);
      }
    }

    return expiry.isAfter(now);
  }

  /// ── التحقق السحابي من الاشتراك ──
  static Future<bool?> verifySubscriptionCloud() async {
    if (!EnvConfig.isConfigured) return null;

    try {
      final pharmacyCode =
          await DatabaseHelper.instance.getSetting('pharmacy_code');
      if (pharmacyCode == null || pharmacyCode.isEmpty) return null;

      final res = await http
          .get(
            Uri.parse(
                '${EnvConfig.supabaseUrl}/pharmacies?pharmacy_code=eq.$pharmacyCode&select=subscription_expiry'),
            headers: {
              'apikey': EnvConfig.supabaseKey,
              'Authorization': 'Bearer ${EnvConfig.supabaseKey}',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) {
        // ⚠️ تم حذف الصيدلية من السحابة! نقوم بمسح تفعيل التطبيق محلياً فوراً
        final db = DatabaseHelper.instance;
        await db.setSetting('pharmacy_code', '');
        await db.setSetting('pharmacy_cloud_id', '');
        await db.setSetting('is_assistant_device', '0');
        await db.setSetting('subscription_expiry', '');
        await db.setSetting('subscription_expiry_sig', '');
        await db.setSetting('assistants_activated', '0');
        await db.setSetting('assistant_slots', '0');
        await db.setSetting('extra_assistant_slots', '0');
        await db.setSetting('last_sync_at', '');
        return false;
      }

      final cloudExpiry = data[0]['subscription_expiry'];
      if (cloudExpiry == null) return null;

      final expiry = DateTime.tryParse(cloudExpiry.toString());
      if (expiry == null) return null;

      final serverTime = await getServerTime();
      final now = serverTime ?? DateTime.now();

      await saveSignedSetting(
          'subscription_expiry', expiry.toIso8601String());

      return expiry.isAfter(now);
    } catch (e) {
      debugPrint('⚠️ verifySubscriptionCloud error: $e');
      return null;
    }
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
      final developerMode = await FlutterJailbreakDetection.developerMode;

      if (jailbroken) {
        warnings.add('📱 جهازك يحتوي على صلاحيات الروت (Root) - قد تكون بياناتك معرضة للخطر');
      }
      if (developerMode) {
        warnings.add('🛠️ وضع خيارات المطور (Developer Options) نشط في جهازك');
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
}
