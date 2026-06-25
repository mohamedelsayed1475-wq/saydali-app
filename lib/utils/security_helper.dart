import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  // ── HMAC signing key (device-specific, stored in secure storage) ──
  static String? _cachedHmacKey;

  static Future<String> _getHmacKey() async {
    if (_cachedHmacKey != null) return _cachedHmacKey!;
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    var key = await storage.read(key: 'hmac_signing_key');
    if (key == null || key.isEmpty) {
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      key = base64.encode(bytes);
      await storage.write(key: 'hmac_signing_key', value: key);
    }
    _cachedHmacKey = key;
    return key;
  }

  /// ── توقيع قيمة بـ HMAC-SHA256 ──
  static Future<String> signValue(String key, String value) async {
    final secretKey = await _getHmacKey();
    final hmac = Hmac(sha256, utf8.encode(secretKey));
    final digest = hmac.convert(utf8.encode('$key:$value'));
    return digest.toString();
  }

  /// ── التحقق من صحة التوقيع ──
  static Future<bool> verifyValue(String key, String value, String signature) async {
    final expected = await signValue(key, value);
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
    try {
      final db = DatabaseHelper.instance;
      final isActivated = await db.getSetting('is_activated');
      if (isActivated != '1') return false;

      final expiry = await readSignedSetting('subscription_expiry');
      if (expiry == null || expiry.isEmpty) return true; // lifetime activation

      final expiryDate = DateTime.tryParse(expiry);
      if (expiryDate == null) return false;

      // Use server time if available, fall back to device time
      final now = await getServerTime() ?? DateTime.now();
      return now.isBefore(expiryDate);
    } catch (_) {
      return false;
    }
  }

  /// ── التحقق السحابي من الاشتراك ──
  static Future<bool?> verifySubscriptionCloud() async {
    try {
      if (EnvConfig.supabaseUrl.isEmpty) return null;
      final db = DatabaseHelper.instance;
      final isActivated = await db.getSetting('is_activated');
      if (isActivated != '1') return false;

      final expiry = await readSignedSetting('subscription_expiry');
      if (expiry == null || expiry.isEmpty) return true; // lifetime

      final expiryDate = DateTime.tryParse(expiry);
      if (expiryDate == null) return false;

      final now = await getServerTime() ?? DateTime.now();
      return now.isBefore(expiryDate);
    } catch (_) {
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
      if (!await verifyValue('subscription_expiry', expiry, sig)) {
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

  /// ── التحقق من صحة الـ PIN (مع دعم Plaintext والـ SHA-256 القديم) ──
  static bool verifyPin(String enteredPin, String storedPinValue) {
    if (!storedPinValue.contains('\$')) {
      // Legacy compatibility: Plaintext or old SHA-256 fallback
      if (storedPinValue.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(storedPinValue)) {
        // Old SHA-256 format: sha256(pin + salt).toString()
        return storedPinValue == _hashPinLegacy(enteredPin);
      }
      return enteredPin == storedPinValue;
    }

    final parts = storedPinValue.split('\$');
    if (parts.length != 2) return false;

    // Try new PBKDF2 format (base64 salt)
    try {
      base64.decode(parts[0]); // valid base64 = new format
      final expected = hashPin(enteredPin, saltBase64: parts[0]);
      final expectedHash = expected.split('\$')[1];
      final storedHash = parts[1];
      // Timing-safe comparison
      if (storedHash.length != expectedHash.length) return false;
      int result = 0;
      for (int i = 0; i < storedHash.length; i++) {
        result |= storedHash.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
      }
      return result == 0;
    } catch (_) {
      // Unknown format
      return false;
    }
  }

  // Legacy SHA-256 hash for migration (old pin_lock_screen format)
  static String _hashPinLegacy(String pin) {
    return sha256.convert(utf8.encode(pin + 'saydali_salt_2024')).toString();
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
