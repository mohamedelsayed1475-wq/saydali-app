import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../models/models.dart';

// ════════════════════════════════════════════════════════════════════════════
// ▌ مزود المحادثة الذكي - المحسّن مع دعم أنواع الرسائل
// ════════════════════════════════════════════════════════════════════════════

class ChatProvider extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  bool _loading = false;

  List<ChatMessage> get messages => _messages;
  bool get loading => _loading;

  // ── إرسال رسالة مع نوع محدد (الميزة الجديدة) ──────────────────────────────────────────────────
  Future<void> sendWithType(
    String text, {
    required BuildContext context,
    List<String>? filePaths,
    MessageType? messageType,
  }) async {
    if (text.trim().isEmpty && (filePaths == null || filePaths.isEmpty)) return;

    // 1️⃣ إضافة رسالة المستخدم
    final userMsg = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      metadata: {
        'type': _getTypeLabel(messageType),
        'messageType': messageType?.toString(),
      },
    );
    _messages.insert(0, userMsg);
    _loading = true;
    notifyListeners();

    try {
      // 2️⃣ استدعاء الـ API مع النوع المحدد
      final response = await ChatService.instance.execute(
        text,
        filePaths: filePaths,
        messageType: messageType,
      );

      // 3️⃣ إضافة رد الذكاء الاصطناعي
      final aiMsg = ChatMessage(
        text: response.text,
        isUser: false,
        isError: !response.success,
        timestamp: DateTime.now(),
        metadata: {
          'intent': response.intent.toString(),
          'type': _getTypeLabel(messageType),
          'success': response.success,
        },
      );
      _messages.insert(0, aiMsg);
    } catch (e) {
      // 4️⃣ معالجة الأخطاء
      final errorMsg = ChatMessage(
        text: '⚠️ حدث خطأ غير متوقع.\n\n'
            '💡 تأكد من:\n'
            '• اتصال الإنترنت\n'
            '• إعدادات API الصحيحة\n'
            '• صحة الملفات المرفقة',
        isUser: false,
        isError: true,
        timestamp: DateTime.now(),
      );
      _messages.insert(0, errorMsg);
    }

    _loading = false;
    notifyListeners();
  }

  // ── إرسال رسالة (الدالة القديمة للتوافق) ──────────────────────────────────────────────────
  Future<void> send(
    String text, {
    required BuildContext context,
    List<String>? filePaths,
  }) async {
    // استخدام النوع العام كـ default
    await sendWithType(
      text,
      context: context,
      filePaths: filePaths,
      messageType: MessageType.general,
    );
  }

  // ── محادثة ذكية حرة (بدون نوع محدد) ──────────────────────────────────────────────────
  Future<void> smartChat(
    String text, {
    required BuildContext context,
    List<String>? filePaths,
  }) async {
    if (text.trim().isEmpty) return;

    final userMsg = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      metadata: {'type': '💬 محادثة ذكية'},
    );
    _messages.insert(0, userMsg);
    _loading = true;
    notifyListeners();

    try {
      final response = await ChatService.instance.execute(
        text,
        filePaths: filePaths,
      );

      final aiMsg = ChatMessage(
        text: response.text,
        isUser: false,
        isError: !response.success,
        timestamp: DateTime.now(),
      );
      _messages.insert(0, aiMsg);
    } catch (e) {
      final errorMsg = ChatMessage(
        text: '⚠️ حدث خطأ غير متوقع.',
        isUser: false,
        isError: true,
        timestamp: DateTime.now(),
      );
      _messages.insert(0, errorMsg);
    }

    _loading = false;
    notifyListeners();
  }

  // ── إضافة رسالة بسرعة (للإشعارات) ──────────────────────────────────────────────────
  void addMessage(String text, {bool isUser = false, bool isError = false}) {
    final msg = ChatMessage(
      text: text,
      isUser: isUser,
      isError: isError,
      timestamp: DateTime.now(),
    );
    _messages.insert(0, msg);
    notifyListeners();
  }

  // ── مسح المحادثة ──────────────────────────────────────────────────
  void clear() {
    _messages.clear();
    notifyListeners();
  }

  // ── حذف رسالة محددة ──────────────────────────────────────────────────
  void deleteMessage(int index) {
    if (index >= 0 && index < _messages.length) {
      _messages.removeAt(index);
      notifyListeners();
    }
  }

  // ── الحصول على نوع الرسالة بالإنجليزية ──────────────────────────────────────────────────
  String _getTypeLabel(MessageType? type) {
    if (type == null) return '💬';
    switch (type) {
      case MessageType.drug:
        return '💊';
      case MessageType.alternative:
        return '🔄';
      case MessageType.shortage:
        return '📋';
      case MessageType.debt:
        return '💰';
      case MessageType.rep:
        return '👥';
      case MessageType.stats:
        return '📊';
      case MessageType.general:
        return '💬';
      case MessageType.image:
        return '🖼️';
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ نموذج الرسالة
// ════════════════════════════════════════════════════════════════════════════

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    required this.timestamp,
    this.metadata,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ مزود اقتراحات الأدوية (للـ autocomplete)
// ════════════════════════════════════════════════════════════════════════════

class DrugSuggestionProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;
  String _lastQuery = '';

  List<Map<String, dynamic>> get suggestions => _suggestions;
  bool get loading => _loading;

  Future<void> search(String query) async {
    if (query.trim().length < 3) {
      _suggestions = [];
      notifyListeners();
      return;
    }

    if (query == _lastQuery) return;
    _lastQuery = query;
    _loading = true;
    notifyListeners();

    try {
      _suggestions = await ChatService.instance.suggestDrugNames(query);
    } catch (e) {
      _suggestions = [];
    }

    _loading = false;
    notifyListeners();
  }

  void clear() {
    _suggestions = [];
    _lastQuery = '';
    notifyListeners();
  }
}