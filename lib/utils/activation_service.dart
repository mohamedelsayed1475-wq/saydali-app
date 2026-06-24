import 'dart:convert';
import 'package:http/http.dart' as http;
import 'env_config.dart';

/// يحذف الكود المستخدم من activation_codes.txt على GitHub
/// حتى لا تستطيع صيدلية أخرى استخدام نفس الكود.
class ActivationService {
  static const _owner = 'mohamedelsayed1475-wq';
  static const _repo  = 'saydali-app';
  static const _path  = 'activation_codes.txt';
  static const _apiBase = 'https://api.github.com';

  /// يحذف [code] من الملف على GitHub.
  /// لا يوقف التفعيل إذا فشل الحذف (مجرد حماية إضافية).
  static Future<void> removeCodeFromRemote(String code) async {
    final pat = EnvConfig.githubPat;
    if (pat.isEmpty) return;

    try {
      // 1 - جلب الملف الحالي + SHA
      final getResp = await http.get(
        Uri.parse('$_apiBase/repos/$_owner/$_repo/contents/$_path'),
        headers: {
          'Authorization': 'Bearer $pat',
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 15));

      if (getResp.statusCode != 200) return;

      final jsonData = jsonDecode(getResp.body) as Map<String, dynamic>;
      final sha = jsonData['sha'] as String;
      final rawContent = utf8.decode(
          base64.decode((jsonData['content'] as String).replaceAll('\n', '')));

      // 2 - حذف الكود من القائمة
      final updatedLines = rawContent
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l != code)
          .toList();

      final updatedContent =
          base64.encode(utf8.encode(updatedLines.join('\n')));

      // 3 - رفع الملف المحدث
      await http.put(
        Uri.parse('$_apiBase/repos/$_owner/$_repo/contents/$_path'),
        headers: {
          'Authorization': 'Bearer $pat',
          'Accept': 'application/vnd.github+json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': 'chore: remove used activation code',
          'content': updatedContent,
          'sha': sha,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      // فشل الحذف لا يوقف التفعيل - الحماية المحلية كافية
    }
  }
}
