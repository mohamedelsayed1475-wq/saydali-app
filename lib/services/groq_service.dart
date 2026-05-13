import 'dart:convert';
import 'package:http/http.dart' as http;

// ════════════════════════════════════════════════════════════════════════════
// ▌ Groq Service - مجاني بحد كبير جداً
// ════════════════════════════════════════════════════════════════════════════

class GroqService {
  static final GroqService instance = GroqService._();
  GroqService._();

  static const _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama3-8b-8192'; // مجاني وسريع

  // ── إرسال سؤال لـ Groq ──────────────────────────────────────────────────
  Future<String?> ask({
    required String apiKey,
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1024,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userMessage},
              ],
              'max_tokens': maxTokens,
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['choices']?[0]?['message']?['content'] as String?;
      }

      if (res.statusCode == 401) throw GroqException('مفتاح API غير صحيح');
      if (res.statusCode == 429) throw GroqException('تجاوزت الحد المسموح، انتظر قليلاً');
      throw GroqException('خطأ ${res.statusCode}');
    } on GroqException {
      rethrow;
    } catch (e) {
      throw GroqException('تعذر الاتصال بـ Groq: $e');
    }
  }

  // ── التحقق من صحة المفتاح ──────────────────────────────────────────────────
  Future<bool> validateKey(String apiKey) async {
    try {
      final result = await ask(
        apiKey: apiKey,
        systemPrompt: 'أنت مساعد.',
        userMessage: 'قل "مرحباً" فقط.',
        maxTokens: 10,
      );
      return result != null;
    } catch (_) {
      return false;
    }
  }
}

class GroqException implements Exception {
  final String message;
  GroqException(this.message);
  @override
  String toString() => message;
}
