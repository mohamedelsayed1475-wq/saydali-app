import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'env_config.dart';

/// خدمة التفعيل السحابي الآمن عبر Edge Function
class ActivationService {
  /// يتحقق من كود التفعيل ويقوم بتمييزه كمستخدم في الخادم في طلب واحد آمن ومحمي
  static Future<bool> activateCode(String code) async {
    final url = EnvConfig.supabaseUrl;
    final key = EnvConfig.supabaseKey;
    if (url.isEmpty || key.isEmpty) {
      debugPrint('⚠️ إعدادات السحابة الافتراضية فارغة، لا يمكن إجراء التفعيل.');
      return false;
    }

    try {
      final cleanUrl = url.endsWith('/') ? url : '$url/';
      final response = await http.post(
        Uri.parse('${cleanUrl}functions/v1/activate-code'),
        headers: {
          'apikey': key,
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'code': code}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error during activation call: $e');
      return false;
    }
  }
}
