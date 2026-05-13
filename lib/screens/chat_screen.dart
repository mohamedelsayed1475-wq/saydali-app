import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../services/chat_service.dart';
import '../services/groq_service.dart';
import '../utils/app_theme.dart';
import 'setup_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
// ▌ شاشة المحادثة - v5.0
// ▌ مدمجة مع Groq + OpenFDA + RxNorm
// ════════════════════════════════════════════════════════════════════════════

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late AnimationController _typingCtrl;
  MessageType _selectedType = MessageType.general;
  List<String> _attachedFiles = [];
  bool _showTypeSelector = false;
  bool _groqConfigured = false;

  static const _chips = [
    ('النواقص', '📋'),
    ('الديون', '💰'),
    ('المندوبين', '👥'),
    ('ملخص اليوم', '📊'),
    ('تحليل النواقص', '📈'),
    ('ابحث عن دواء', '🔍'),
    ('مساعدة', '🤖'),
  ];

  @override
  void initState() {
    super.initState();
    _typingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _checkGroqSetup();
  }

  Future<void> _checkGroqSetup() async {
    final key = await ChatService.instance.getGroqKey();
    setState(() => _groqConfigured = key.isNotEmpty);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _typingCtrl.dispose();
    super.dispose();
  }

  void _send(String text, [List<String>? files]) {
    if (text.trim().isEmpty && (files == null || files.isEmpty)) return;

    context.read<ChatProvider>().sendWithType(
      text.trim(),
      context: context,
      filePaths: files,
      messageType: _selectedType,
    );

    _ctrl.clear();
    setState(() {
      _attachedFiles = [];
      _showTypeSelector = false;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _selectType(MessageType type) {
    setState(() {
      _selectedType = type;
      _showTypeSelector = false;
    });
  }

  // ── فتح إعدادات API ──────────────────────────────────────────────────
  void _openApiSettings() {
    showDialog(
      context: context,
      builder: (_) => ApiSettingsDialog(
        onGroqSaved: () {
          setState(() => _groqConfigured = true);
        },
      ),
    );
  }

  // ── فتح شاشة الإعداد الأولى ──────────────────────────────────────────────────
  void _openSetupScreen() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SetupScreen(
            onComplete: () {
              Navigator.pop(context);
              _checkGroqSetup();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    return Column(
      children: [
        // ═══ شريط التحذير لو Groq مش متضاف ════
        if (!_groqConfigured) _GroqWarningBanner(onSetup: _openSetupScreen),

        // ═══ شريط اختيار نوع الرسالة ════
        _MessageTypeBar(
          selectedType: _selectedType,
          onTypeSelected: _selectType,
          showAll: _showTypeSelector,
          onToggle: () => setState(() => _showTypeSelector = !_showTypeSelector),
          chips: _chips,
          onSend: _send,
          onSettings: _openApiSettings,
        ),

        const Divider(height: 1, color: AppColors.darkBorder),

        // ═══ قائمة الرسائل ════
        Expanded(
          child: chat.messages.isEmpty
              ? _EmptyState(
                  onTap: _send,
                  selectedType: _selectedType,
                  groqConfigured: _groqConfigured,
                  onSetup: _openSetupScreen,
                )
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: chat.messages.length + (chat.loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (chat.loading && i == 0) {
                      return _TypingIndicator(ctrl: _typingCtrl);
                    }
                    final msg = chat.messages[chat.loading ? i - 1 : i];
                    return _MessageBubble(
                      message: msg,
                      onCopy: () {
                        Clipboard.setData(ClipboardData(text: msg.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم النسخ ✅')),
                        );
                      },
                      onShare: () => Share.share(msg.text),
                    );
                  },
                ),
        ),

        // ═══ حقل الإدخال ════
        _InputBar(
          ctrl: _ctrl,
          onSend: _send,
          loading: chat.loading,
          hint: _selectedType.hint,
          selectedType: _selectedType,
          attachedFiles: _attachedFiles,
          onFilesChanged: (files) => setState(() => _attachedFiles = files),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ شريط تحذير Groq
// ════════════════════════════════════════════════════════════════════════════

class _GroqWarningBanner extends StatelessWidget {
  final VoidCallback onSetup;
  const _GroqWarningBanner({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSetup,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          border: const Border(
            bottom: BorderSide(color: Colors.orange, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'حكيم يحتاج Groq API للعمل بشكل كامل - اضغط هنا للإعداد المجاني',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.orange, size: 14),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ شريط اختيار نوع الرسالة
// ════════════════════════════════════════════════════════════════════════════

class _MessageTypeBar extends StatelessWidget {
  final MessageType selectedType;
  final void Function(MessageType) onTypeSelected;
  final bool showAll;
  final VoidCallback onToggle;
  final List<(String, String)> chips;
  final void Function(String, [List<String>?]) onSend;
  final VoidCallback onSettings;

  const _MessageTypeBar({
    required this.selectedType,
    required this.onTypeSelected,
    required this.showAll,
    required this.onToggle,
    required this.chips,
    required this.onSend,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkCard,
      child: Column(
        children: [
          // ═══ النوع الحالي ════
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // النوع المحدد
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(selectedType.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          selectedType.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          showAll ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // زر الإعدادات
                IconButton(
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined, color: AppColors.textMuted, size: 20),
                  tooltip: 'إعدادات API',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),

          // ═══ جميع الأنواع ════
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: showAll ? 140 : 0,
            child: showAll
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: MessageType.values.map((type) {
                        final isSelected = type == selectedType;
                        return GestureDetector(
                          onTap: () => onTypeSelected(type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.2)
                                  : AppColors.dark,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : AppColors.darkBorder,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(type.emoji, style: const TextStyle(fontSize: 18)),
                                const SizedBox(height: 2),
                                Text(
                                  type.label,
                                  style: TextStyle(
                                    color: isSelected ? AppColors.primary : AppColors.textMuted,
                                    fontSize: 10,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ═══ اقتراحات سريعة ════
          _QuickChips(chips: chips, onTap: onSend, selectedType: selectedType),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ شريط الاقتراحات السريعة
// ════════════════════════════════════════════════════════════════════════════

class _QuickChips extends StatelessWidget {
  final List<(String, String)> chips;
  final void Function(String) onTap;
  final MessageType selectedType;

  const _QuickChips({
    required this.chips,
    required this.onTap,
    required this.selectedType,
  });

  List<(String, String)> get _suggestions {
    switch (selectedType) {
      case MessageType.drug:
        return [('باراسيتامول', '💊'), ('بروفين', '💊'), ('أدول', '💊'), ('كونجستال', '💊')];
      case MessageType.alternative:
        return [('بديل بروفين', '🔄'), ('بديل باراسيتامول', '🔄'), ('بديل أدول', '🔄')];
      case MessageType.shortage:
        return [('أضف ناقص', '📋'), ('سجل دواء', '📋'), ('النواقص المعلقة', '📋')];
      case MessageType.debt:
        return [('الديون', '💰'), ('عميل جديد', '💰'), ('تسجيل دين', '💰')];
      case MessageType.rep:
        return [('المندوبين', '👥'), ('أضف مندوب', '👥'), ('تقييم', '👥')];
      case MessageType.stats:
        return [('ملخص', '📊'), ('إحصائيات', '📊'), ('تحليل النواقص', '📈')];
      case MessageType.image:
        return [('ارفق صورة', '🖼️'), ('روشتة', '🖼️')];
      default:
        return chips;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, icon) = _suggestions[i];
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onTap(label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                '$icon $label',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ فقاعة الرسالة
// ════════════════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;

  const _MessageBubble({
    required this.message,
    this.onCopy,
    this.onShare,
  });

  String get _typeEmoji {
    final type = message.metadata?['messageType'];
    if (type == null) return '👤';
    try {
      return MessageType.values
          .firstWhere((t) => t.toString() == type, orElse: () => MessageType.general)
          .emoji;
    } catch (_) {
      return '👤';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return GestureDetector(
      onLongPress: isUser || message.isError
          ? null
          : () {
              showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.darkCard,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 8, bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.darkBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.copy, color: AppColors.textMuted),
                        title: const Text('نسخ', style: TextStyle(color: AppColors.textColor)),
                        onTap: () {
                          Navigator.pop(ctx);
                          onCopy?.call();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.share, color: AppColors.textMuted),
                        title: const Text('مشاركة', style: TextStyle(color: AppColors.textColor)),
                        onTap: () {
                          Navigator.pop(ctx);
                          onShare?.call();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // أيقونة حكيم
            if (!isUser) ...[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: Text('🤖', style: TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 8),
            ],

            // الفقاعة
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : message.isError
                          ? AppColors.danger.withValues(alpha: 0.12)
                          : AppColors.darkCard,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: Border.all(
                    color: isUser
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : message.isError
                            ? AppColors.danger.withValues(alpha: 0.3)
                            : AppColors.darkBorder,
                  ),
                ),
                child: Text(
                  message.text,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: isUser ? AppColors.textColor : AppColors.textLight,
                    fontSize: 13.5,
                    height: 1.55,
                  ),
                ),
              ),
            ),

            // أيقونة المستخدم
            if (isUser) ...[
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(_typeEmoji, style: const TextStyle(fontSize: 16))),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ مؤشر الكتابة
// ════════════════════════════════════════════════════════════════════════════

class _TypingIndicator extends StatelessWidget {
  final AnimationController ctrl;
  const _TypingIndicator({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(child: Text('🤖', style: TextStyle(fontSize: 16))),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: ctrl,
                  builder: (_, __) {
                    final val = ((ctrl.value - i * 0.3).clamp(0.0, 1.0));
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 7,
                      height: 7 + val * 5,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.5 + val * 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ الشاشة الفارغة
// ════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final void Function(String) onTap;
  final MessageType selectedType;
  final bool groqConfigured;
  final VoidCallback onSetup;

  const _EmptyState({
    required this.onTap,
    required this.selectedType,
    required this.groqConfigured,
    required this.onSetup,
  });

  String get _subtitle {
    switch (selectedType) {
      case MessageType.drug: return 'اكتب اسم الدواء أو اسأل عن معلوماته';
      case MessageType.alternative: return 'اكتب اسم الدواء لاقتراح بدائل';
      case MessageType.shortage: return 'اكتب اسم الدواء الناقص لإضافته';
      case MessageType.debt: return 'اسأل عن ديون العملاء أو أضف دين جديد';
      case MessageType.rep: return 'اسأل عن المندوبين أو أضف مندوب جديد';
      case MessageType.stats: return 'اطلب إحصائيات أو ملخص الصيدلية';
      case MessageType.general: return 'مساعدك الذكي للصيدلية';
      case MessageType.image: return 'أرفق صورة روشتة لاستخراج الأدوية';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // أيقونة
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Center(
                child: Text(selectedType.emoji, style: const TextStyle(fontSize: 48)),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'حكيم - ${selectedType.label}',
              style: const TextStyle(
                color: AppColors.textColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // بطاقة Groq لو مش متضاف
            if (!groqConfigured) ...[
              GestureDetector(
                onTap: onSetup,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Text('⚡', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'فعّل حكيم بالكامل مجاناً',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'أضف Groq API في دقيقتين\nمجاني 100% - بدون بطاقة بنكية',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.orange, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // اقتراحات سريعة
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: selectedType.sampleCommands.map((cmd) {
                return InkWell(
                  onTap: () => onTap(cmd),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      cmd,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ حقل الإدخال
// ════════════════════════════════════════════════════════════════════════════

class _InputBar extends StatefulWidget {
  final TextEditingController ctrl;
  final void Function(String, List<String>?) onSend;
  final bool loading;
  final String hint;
  final MessageType selectedType;
  final List<String> attachedFiles;
  final void Function(List<String>) onFilesChanged;

  const _InputBar({
    required this.ctrl,
    required this.onSend,
    required this.loading,
    required this.hint,
    required this.selectedType,
    required this.attachedFiles,
    required this.onFilesChanged,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'xlsx', 'xls', 'csv', 'doc', 'docx'],
      allowMultiple: true,
    );
    if (result != null) {
      widget.onFilesChanged(result.paths.whereType<String>().toList());
    }
  }

  void _handleSend() {
    widget.onSend(widget.ctrl.text, widget.attachedFiles);
    widget.onFilesChanged([]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkCard,
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الملفات المرفقة
          if (widget.attachedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: widget.attachedFiles.map((path) {
                  final name = path.split(Platform.pathSeparator).last;
                  final isImage = ['jpg', 'jpeg', 'png', 'webp']
                      .contains(path.split('.').last.toLowerCase());
                  return Chip(
                    avatar: Icon(
                      isImage ? Icons.image : Icons.description,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: Text(
                      name.length > 20 ? '${name.substring(0, 17)}...' : name,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    onDeleted: () {
                      final newFiles = List<String>.from(widget.attachedFiles);
                      newFiles.remove(path);
                      widget.onFilesChanged(newFiles);
                    },
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    deleteIconColor: Colors.redAccent,
                  );
                }).toList(),
              ),
            ),

          // شريط الأزرار
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file, color: AppColors.textMuted),
                onPressed: _pickFiles,
                tooltip: 'إرفاق ملف',
              ),
              Expanded(
                child: TextField(
                  controller: widget.ctrl,
                  textDirection: TextDirection.rtl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: widget.loading ? null : (_) => _handleSend(),
                  style: const TextStyle(color: AppColors.textColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.dark,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppColors.darkBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppColors.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(
                onTap: _handleSend,
                loading: widget.loading,
                type: widget.selectedType,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ زر الإرسال
// ════════════════════════════════════════════════════════════════════════════

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;
  final MessageType type;

  const _SendButton({required this.onTap, required this.loading, required this.type});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: loading
              ? null
              : const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
          color: loading ? AppColors.darkBorder : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
              )
            : Center(
                child: Text(type.emoji, style: const TextStyle(fontSize: 20)),
              ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ ApiSettingsDialog - بيطلبه main.dart
// ════════════════════════════════════════════════════════════════════════════

class ApiSettingsDialog extends StatefulWidget {
  final VoidCallback? onGroqSaved;

  const ApiSettingsDialog({super.key, this.onGroqSaved});

  @override
  State<ApiSettingsDialog> createState() => _ApiSettingsDialogState();
}

class _ApiSettingsDialogState extends State<ApiSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Groq
  final _groqKeyCtrl = TextEditingController();
  bool _groqKeyVisible = false;
  bool _groqLoading = false;
  bool _groqValid = false;
  String? _groqError;

  // Gemini / OpenAI (اختياري)
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  List<String> _knowledgeFiles = [];
  String _type = 'openai';
  bool _keyVisible = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final settings = await ChatService.instance.getApiSettings();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _groqKeyCtrl.text = settings['groq_key'] ?? '';
      _groqValid = _groqKeyCtrl.text.isNotEmpty;
      _urlCtrl.text = settings['url'] ?? '';
      _keyCtrl.text = settings['key'] ?? '';
      _nameCtrl.text = settings['name'] ?? '';
      _type = settings['type'] ?? 'openai';
      _knowledgeFiles = List<String>.from(settings['files'] ?? []);
      _loading = false;
    });
  }

  Future<void> _validateGroqKey() async {
    final key = _groqKeyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _groqError = 'أدخل المفتاح أولاً');
      return;
    }

    setState(() {
      _groqLoading = true;
      _groqError = null;
    });

    final valid = await GroqService.instance.validateKey(key);

    if (valid) {
      await ChatService.instance.saveGroqKey(key);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_complete', true);
      setState(() {
        _groqValid = true;
        _groqLoading = false;
      });
      widget.onGroqSaved?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حفظ Groq API بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      setState(() {
        _groqError = '❌ المفتاح غير صحيح';
        _groqLoading = false;
      });
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xlsx', 'xls', 'doc', 'docx'],
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        _knowledgeFiles.addAll(result.paths.whereType<String>());
        _knowledgeFiles = _knowledgeFiles.toSet().toList();
      });
    }
  }

  Future<void> _saveOptionalApi() async {
    await ChatService.instance.saveApiSettings(
      url: _urlCtrl.text.trim(),
      key: _keyCtrl.text.trim(),
      type: _type,
      name: _nameCtrl.text.trim(),
      files: _knowledgeFiles,
    );
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ الإعدادات'), backgroundColor: AppColors.primary),
      );
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _groqKeyCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      child: _loading
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(child: Text('⚙️', style: TextStyle(fontSize: 20))),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'إعدادات الذكاء الاصطناعي',
                          style: TextStyle(
                            color: AppColors.textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                      ),
                    ],
                  ),
                ),

                // Tabs
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textMuted,
                  tabs: const [
                    Tab(text: '⚡ Groq (أساسي)'),
                    Tab(text: '🔧 اختياري'),
                  ],
                ),

                // Tab Content
                SizedBox(
                  height: 380,
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildGroqTab(),
                      _buildOptionalTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ═══ تاب Groq ════
  Widget _buildGroqTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // حالة Groq
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _groqValid
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _groqValid
                    ? Colors.green.withValues(alpha: 0.4)
                    : Colors.orange.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Text(_groqValid ? '✅' : '⚡', style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _groqValid
                        ? 'Groq مفعّل - حكيم يعمل بالكامل مجاناً!'
                        : 'Groq غير مفعّل - أضف المفتاح المجاني',
                    style: TextStyle(
                      color: _groqValid ? Colors.greenAccent : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // رابط الحصول على المفتاح
          if (!_groqValid)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📋 خطوات الحصول على المفتاح:',
                    style: TextStyle(color: AppColors.textLight, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1️⃣ افتح console.groq.com\n'
                    '2️⃣ اعمل حساب مجاني\n'
                    '3️⃣ اضغط "API Keys"\n'
                    '4️⃣ اضغط "Create API Key" وانسخ المفتاح',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.7),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // حقل المفتاح
          const Text(
            'مفتاح Groq API:',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _groqError != null
                    ? Colors.redAccent
                    : _groqValid
                        ? Colors.green.withValues(alpha: 0.5)
                        : AppColors.darkBorder,
              ),
            ),
            child: TextField(
              controller: _groqKeyCtrl,
              obscureText: !_groqKeyVisible,
              style: const TextStyle(color: AppColors.textColor, fontSize: 13, fontFamily: 'monospace'),
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() {
                _groqError = null;
                _groqValid = false;
              }),
              decoration: InputDecoration(
                hintText: 'gsk_xxxxxxxxxxxxxxxxxxxx',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.key, color: AppColors.textMuted, size: 18),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _groqKeyVisible = !_groqKeyVisible),
                  icon: Icon(
                    _groqKeyVisible ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          ),

          if (_groqError != null) ...[
            const SizedBox(height: 6),
            Text(_groqError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          const SizedBox(height: 16),

          // زر التحقق
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _groqLoading ? null : _validateGroqKey,
              style: ElevatedButton.styleFrom(
                backgroundColor: _groqValid ? Colors.green : AppColors.primary,
                disabledBackgroundColor: AppColors.darkBorder,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _groqLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      _groqValid ? '✅ تم التحقق' : 'تحقق واحفظ',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ تاب الاختياري ════
  Widget _buildOptionalTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Text(
              '💡 هذا القسم اختياري.\nحكيم يعمل بالكامل بدونه.\nيمكنك إضافة Gemini أو OpenAI كـ Fallback إضافي.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.6),
            ),
          ),
          const SizedBox(height: 16),

          // نوع API
          Row(
            children: [
              _TypeChip(label: 'Gemini', value: 'gemini', selected: _type == 'gemini',
                  onTap: () => setState(() => _type = 'gemini')),
              const SizedBox(width: 8),
              _TypeChip(label: 'OpenAI', value: 'openai', selected: _type == 'openai',
                  onTap: () => setState(() => _type = 'openai')),
            ],
          ),
          const SizedBox(height: 12),

          if (_type != 'gemini') ...[
            _ApiField(controller: _urlCtrl, label: 'رابط API',
                hint: 'https://api.openai.com/v1', icon: Icons.link),
            const SizedBox(height: 12),
          ],

          _ApiField(controller: _keyCtrl, label: 'مفتاح API',
              hint: 'sk-... أو AIza...', icon: Icons.key,
              obscure: !_keyVisible,
              suffix: IconButton(
                onPressed: () => setState(() => _keyVisible = !_keyVisible),
                icon: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textMuted, size: 18),
              )),
          const SizedBox(height: 12),

          // قاعدة المعرفة
          OutlinedButton.icon(
            onPressed: _pickFiles,
            icon: const Icon(Icons.upload_file, size: 16),
            label: Text('رفع ملفات PDF/Excel (${_knowledgeFiles.length})'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveOptionalApi,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ Widgets مساعدة
// ════════════════════════════════════════════════════════════════════════════

class _TypeChip extends StatelessWidget {
  final String label, value;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label, required this.value,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.dark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.darkBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textMuted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ApiField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;

  const _ApiField({
    required this.controller, required this.label,
    required this.hint, required this.icon,
    this.obscure = false, this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
            color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: AppColors.textColor, fontSize: 13),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
            suffixIcon: suffix,
            filled: true,
            fillColor: AppColors.dark,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.darkBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.darkBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
