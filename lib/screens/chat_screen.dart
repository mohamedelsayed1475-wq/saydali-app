import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/chat_provider.dart';
import '../services/chat_service.dart';
import '../utils/app_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// ▌ شاشة المحادثة المحسّنة - مع اختيار نوع الرسالة قبل الإرسال
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

  // اقتراحات سريعة
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

    // استخدام النوع المحدد مع الرسالة
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
        _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _selectType(MessageType type) {
    setState(() {
      _selectedType = type;
      _showTypeSelector = false;
      // تحديث الـ hint في حقل النص
      _ctrl.text = '';
      _ctrl.clearComposing();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    return Column(
      children: [
        // ════════════════════════════════════════════════════════════════
        // ▌ شريط اختيار نوع الرسالة (الميزة الجديدة)
        // ════════════════════════════════════════════════════════════════
        _MessageTypeBar(
          selectedType: _selectedType,
          onTypeSelected: _selectType,
          showAll: _showTypeSelector,
          onToggle: () => setState(() => _showTypeSelector = !_showTypeSelector),
          chips: _chips,
          onSend: _send,
        ),

        const Divider(height: 1, color: AppColors.darkBorder),

        // قائمة الرسائل
        Expanded(
          child: chat.messages.isEmpty
              ? _EmptyState(onTap: _send, selectedType: _selectedType)
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ')));
                      },
                      onShare: () => Share.share(msg.text),
                    );
                  },
                ),
        ),

        // حقل الإدخال
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
// ▌ شريط اختيار نوع الرسالة - Widget جديد
// ════════════════════════════════════════════════════════════════════════════

class _MessageTypeBar extends StatelessWidget {
  final MessageType selectedType;
  final void Function(MessageType) onTypeSelected;
  final bool showAll;
  final VoidCallback onToggle;
  final List<(String, String)> chips;
  final void Function(String, [List<String>?]) onSend;

  const _MessageTypeBar({
    required this.selectedType,
    required this.onTypeSelected,
    required this.showAll,
    required this.onToggle,
    required this.chips,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkCard,
      child: Column(
        children: [
          // ═══ النوع الحالي المحدد ════
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
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
                      Text(
                        selectedType.emoji,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        selectedType.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // زر إظهار/إخفاء الأنواع
                TextButton.icon(
                  onPressed: onToggle,
                  icon: Icon(
                    showAll ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    showAll ? 'اخفاء' : 'تغيير النوع',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ═══ جميع الأنواع (عند التوسع) ════
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: showAll ? 140 : 0,
            child: showAll
                ? Container(
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
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.darkBorder,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  type.emoji,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  type.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                    fontSize: 10,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    // اقتراحات خاصة بكل نوع
    List<(String, String)> getSuggestions() {
      switch (selectedType) {
        case MessageType.drug:
          return [('باراسيتامول', '💊'), ('بروفين', '💊'), ('أدول', '💊'), ('كونجستال', '💊'), ('أوميجا 3', '💊')];
        case MessageType.alternative:
          return [('بديل بروفين', '🔄'), ('بديل باراسيتامول', '🔄'), ('بديل أدول', '🔄')];
        case MessageType.shortage:
          return [('أضف ناقص', '📋'), ('سجل دواء', '📋'), ('ناقص جديد', '📋')];
        case MessageType.debt:
          return [('الديون', '💰'), ('عميل جديد', '💰'), ('تسجيل دين', '💰')];
        case MessageType.rep:
          return [('المندوبين', '👥'), ('أضف مندوب', '👥'), ('تقييم', '👥')];
        case MessageType.stats:
          return [('ملخص', '📊'), ('إحصائيات', '📊'), ('تقرير', '📊')];
        case MessageType.image:
          return [('ارفق صورة', '🖼️'), ('روشتة', '🖼️')];
        default:
          return chips;
      }
    }

    final suggestions = getSuggestions();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, icon) = suggestions[i];
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onTap(label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
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
// ▌ فقاعة الرسالة - مع خيارات النسخ والمشاركة
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

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return GestureDetector(
      onLongPress: isUser || message.isError ? null : () {
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
                  margin: const EdgeInsets.only(bottom: 12),
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
                child: const Center(
                  child: Text('🤖', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 8),
            ],
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // أيقونة نوع الرسالة (للردود من الـ AI)
                    if (!isUser && message.metadata?['type'] != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${message.metadata!['type']}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    // نص الرسالة
                    Text(
                      message.text,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: isUser ? AppColors.textColor : AppColors.textLight,
                        fontSize: 13.5,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    selectedTypeEmoji,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get selectedTypeEmoji {
    final type = message.metadata?['messageType'];
    if (type == null) return '👤';
    try {
      final msgType = MessageType.values.firstWhere(
        (t) => t.toString() == type,
        orElse: () => MessageType.general,
      );
      return msgType.emoji;
    } catch (_) {
      return '👤';
    }
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
            child: const Center(
              child: Text('🤖', style: TextStyle(fontSize: 16)),
            ),
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
                    final delay = i * 0.3;
                    final val = ((ctrl.value - delay).clamp(0.0, 1.0));
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
// ▌ حالة فارغة - مع عرض النوع المحدد
// ════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final void Function(String) onTap;
  final MessageType selectedType;

  const _EmptyState({required this.onTap, required this.selectedType});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                child: Text(
                  selectedType.emoji,
                  style: const TextStyle(fontSize: 48),
                ),
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
              _getSubtitle(),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // أمثلة سريعة
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
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
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

  String _getSubtitle() {
    switch (selectedType) {
      case MessageType.drug:
        return 'اكتب اسم الدواء أو اسأل عن معلوماته';
      case MessageType.alternative:
        return 'اكتب اسم الدواء لاقتراح بدائل';
      case MessageType.shortage:
        return 'اكتب اسم الدواء الناقص لإضافته';
      case MessageType.debt:
        return 'اسأل عن ديون العملاء أو أضف دين جديد';
      case MessageType.rep:
        return 'اسأل عن المندوبين أو أضف مندوب جديد';
      case MessageType.stats:
        return 'اطلب إحصائيات أو ملخص الصيدلية';
      case MessageType.general:
        return 'مساعدك الذكي للصيدلية';
      case MessageType.image:
        return 'أرفق صورة روشتة لاستخراج الأدوية';
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ حقل الإدخال - مع عرض hint خاص بالنوع المحدد
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
  late String _hint;

  @override
  void initState() {
    super.initState();
    _hint = widget.hint;
  }

  @override
  void didUpdateWidget(covariant _InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hint != widget.hint) {
      setState(() => _hint = widget.hint);
    }
  }

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
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: widget.attachedFiles.map((path) {
                  final name = path.split(Platform.pathSeparator).last;
                  final isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(
                    path.split('.').last.toLowerCase(),
                  );
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
              // زر إرفاق صورة
              IconButton(
                icon: const Icon(Icons.attach_file, color: AppColors.textMuted),
                onPressed: _pickFiles,
                tooltip: 'إرفاق ملف',
              ),
              // زر التقاط صورة
              IconButton(
                icon: const Icon(Icons.camera_alt, color: AppColors.textMuted),
                onPressed: () async {
                  // يمكن إضافة كاميرا هنا
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📷 يمكن التقاط صورة وإرفاقها من المعرض'),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
                tooltip: 'التقاط صورة',
              ),

              // حقل النص
              Expanded(
                child: TextField(
                  controller: widget.ctrl,
                  textDirection: TextDirection.rtl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: widget.loading ? null : (_) => _handleSend(),
                  style: const TextStyle(color: AppColors.textColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _hint,
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
// ▌ زر الإرسال - مع أيقونة النوع المحدد
// ════════════════════════════════════════════════════════════════════════════

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;
  final MessageType type;

  const _SendButton({
    required this.onTap,
    required this.loading,
    required this.type,
  });

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
              : const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark]),
          color: loading ? AppColors.darkBorder : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.send_rounded,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 20,
                  ),
                  Positioned(
                    bottom: 8,
                    child: Text(
                      type.emoji,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ ديالوج إعدادات API - نفس الكود القديم مع تحسينات
// ════════════════════════════════════════════════════════════════════════════

class ApiSettingsDialog extends StatefulWidget {
  const ApiSettingsDialog({super.key});

  @override
  State<ApiSettingsDialog> createState() => _ApiSettingsDialogState();
}

class _ApiSettingsDialogState extends State<ApiSettingsDialog> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  List<String> _knowledgeFiles = [];
  String _type = 'openai';
  bool _loading = true;
  bool _keyVisible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ChatService.instance.getApiSettings();
    setState(() {
      _urlCtrl.text = s['url'] ?? '';
      _keyCtrl.text = s['key'] ?? '';
      _nameCtrl.text = s['name'] ?? '';
      _type = s['type'] ?? 'openai';
      _knowledgeFiles = List<String>.from(s['files'] ?? []);
      _loading = false;
    });
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

  Future<void> _save() async {
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
        const SnackBar(
          content: Text('✅ تم حفظ إعدادات API'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<void> _clear() async {
    await ChatService.instance.clearApiSettings();
    _urlCtrl.clear();
    _keyCtrl.clear();
    _nameCtrl.clear();
    setState(() {
      _type = 'openai';
      _knowledgeFiles = [];
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🗑️ تم مسح إعدادات API'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  void dispose() {
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
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // العنوان
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('⚙️', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إعدادات الذكاء الاصطناعي',
                              style: TextStyle(
                                color: AppColors.textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'أضف مفتاح API الخاص بك',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // نوع API
                  const Text(
                    'نوع الـ API:',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _TypeChip(
                        label: 'Gemini',
                        value: 'gemini',
                        selected: _type == 'gemini',
                        onTap: () => setState(() {
                          _type = 'gemini';
                          _urlCtrl.text = '';
                        }),
                      ),
                      const SizedBox(width: 8),
                      _TypeChip(
                        label: 'OpenAI',
                        value: 'openai',
                        selected: _type == 'openai',
                        onTap: () => setState(() => _type = 'openai'),
                      ),
                      const SizedBox(width: 8),
                      _TypeChip(
                        label: 'مخصص',
                        value: 'custom',
                        selected: _type == 'custom',
                        onTap: () => setState(() => _type = 'custom'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // اسم الـ API
                  _ApiField(
                    controller: _nameCtrl,
                    label: 'اسم الـ API (اختياري)',
                    hint: 'مثال: ChatGPT الخاص',
                    icon: Icons.label_outline,
                  ),
                  const SizedBox(height: 12),

                  // رابط الـ API
                  if (_type != 'gemini')
                    _ApiField(
                      controller: _urlCtrl,
                      label: 'رابط الـ API',
                      hint: _type == 'openai'
                          ? 'https://api.openai.com/v1'
                          : 'https://your-api.com/endpoint',
                      icon: Icons.link,
                    ),
                  if (_type != 'gemini') const SizedBox(height: 12),

                  // مفتاح الـ API
                  _ApiField(
                    controller: _keyCtrl,
                    label: 'مفتاح الـ API (API Key)',
                    hint: 'sk-...',
                    icon: Icons.key,
                    obscure: !_keyVisible,
                    suffix: IconButton(
                      onPressed: () => setState(() => _keyVisible = !_keyVisible),
                      icon: Icon(
                        _keyVisible ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ملاحظة
                  if (_type == 'openai')
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: const Text(
                        '💡 يدعم: OpenAI, Groq, Together AI, OpenRouter, وأي API متوافق مع OpenAI',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  const SizedBox(height: 20),

                  // قاعدة المعرفة
                  const Text(
                    'قاعدة المعرفة (ملفات PDF/Excel/Word):',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                        if (_knowledgeFiles.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _knowledgeFiles.map((path) {
                              final name = path.split(Platform.pathSeparator).last;
                              return Chip(
                                label: Text(name, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                onDeleted: () {
                                  setState(() => _knowledgeFiles.remove(path));
                                },
                                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                                deleteIconColor: Colors.redAccent,
                              );
                            }).toList(),
                          )
                        else
                          const Text(
                            'لم تقم برفع أي ملفات حتى الآن.',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: const Text('رفع ملفات (PDF/Excel/Word)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // أزرار
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clear,
                          icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                          label: const Text('مسح', style: TextStyle(color: AppColors.danger)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_rounded, size: 16),
                          label: const Text('حفظ الإعدادات'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label, value;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
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
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
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

// ════════════════════════════════════════════════════════════════════════════
// ▌ مساعدة: عرض جميع الأوامر المتاحة
// ════════════════════════════════════════════════════════════════════════════

class CommandsHelpDialog extends StatelessWidget {
  const CommandsHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('🤖', style: TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'أوامر حكيم',
                  style: TextStyle(
                    color: AppColors.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.darkBorder),
            const SizedBox(height: 12),
            _buildSection('📋 إدارة النواقص', [
              'أضف دواء [الاسم] - إضافة للنواقص',
              'النواقص - عرض الكل',
              'النواقص المعلقة - عرض المعلقة فقط',
              'تم توفير [الاسم] - تعليم كمتوفر',
            ]),
            const SizedBox(height: 12),
            _buildSection('🔄 البحث والبدائل', [
              'ابحث عن [الاسم] - البحث في الإنترنت',
              'بديل [الاسم] - بدائل بنفس المادة الفعالة',
              'تحليل النواقص - أنماط وتكرارات',
            ]),
            const SizedBox(height: 12),
            _buildSection('💰 إدارة الديون', [
              'الديون - عرض كل العملاء',
              'دين [اسم العميل] - دين عميل محدد',
            ]),
            const SizedBox(height: 12),
            _buildSection('👥 المندوبين', [
              'المندوبين - عرض القائمة',
              'أضف مندوب - إضافة مندوب جديد',
            ]),
            const SizedBox(height: 12),
            _buildSection('📊 التقارير', [
              'ملخص - إحصائيات سريعة',
              'إحصائيات - تقرير مفصل',
            ]),
            const SizedBox(height: 12),
            _buildSection('🖼️ استخراج من صور', [
              'أرفق صورة روشتة',
              'أضف أدوية من الصورة',
            ]),
            const SizedBox(height: 16),
            const Divider(color: AppColors.darkBorder),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Text('💡', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'اختر نوع رسالتك من الشريط أعلى الشات لتسهيل فهم طلبك!',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<String> commands) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...commands.map((cmd) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Text('• ', style: TextStyle(color: AppColors.primary)),
              Expanded(
                child: Text(
                  cmd,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}