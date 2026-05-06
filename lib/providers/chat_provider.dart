import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import 'app_providers.dart';

// ── نموذج الرسالة ──────────────────────────────────────────────────
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? ts,
    this.isError = false,
  }) : timestamp = ts ?? DateTime.now();
}

// ── Provider الشات ──────────────────────────────────────────────────
class ChatProvider extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  bool _loading = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;

  ChatProvider() {
    _messages.add(ChatMessage(
      text: '👋 أهلاً! أنا حكيم، مساعدك الذكي.\n\n'
          'اكتب "مساعدة" لعرض الأوامر المتاحة، أو ابدأ مباشرة!',
      isUser: false,
    ));
  }

  Future<void> send(String text, {BuildContext? context, List<String>? filePaths}) async {
    if (text.trim().isEmpty && (filePaths == null || filePaths.isEmpty)) return;
    _messages.insert(0, ChatMessage(text: text.trim().isNotEmpty ? text.trim() : '📄 مرفق', isUser: true));
    _loading = true;
    notifyListeners();

    try {
      final response = await ChatService.instance.execute(text.trim(), filePaths: filePaths);
      _messages.insert(
        0,
        ChatMessage(
          text: response.text,
          isUser: false,
          isError: !response.success,
        ),
      );

      // Refresh global state if needed
      if (context != null && response.success) {
        if (response.intent == ChatIntent.addShortage || 
            response.intent == ChatIntent.addShortagesFromImage || 
            response.intent == ChatIntent.markCovered) {
          context.read<ShortagesProvider>().load();
        } else if (response.intent == ChatIntent.addCustomer) {
          context.read<CustomersProvider>().load();
        }
      }

    } catch (e) {
      _messages.insert(
        0,
        ChatMessage(
          text: '⚠️ حدث خطأ غير متوقع: $e',
          isUser: false,
          isError: true,
        ),
      );
    }

    _loading = false;
    notifyListeners();
  }

  void clearHistory() {
    _messages.clear();
    _messages.add(ChatMessage(
      text: '🗑️ تم مسح المحادثة.\n\nاكتب "مساعدة" للبدء من جديد.',
      isUser: false,
    ));
    notifyListeners();
  }
}
