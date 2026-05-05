import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/chat_service.dart';
import '../utils/app_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late AnimationController _typingCtrl;

  // اقتراحات سريعة
  static const _chips = [
    ('النواقص', '📋'),
    ('الديون', '💰'),
    ('المندوبين', '👥'),
    ('ملخص اليوم', '📊'),
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

  void _send(String text) {
    if (text.trim().isEmpty) return;
    context.read<ChatProvider>().send(text.trim());
    _ctrl.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    return Column(
      children: [
        // شريط الاقتراحات السريعة
        _QuickChips(chips: _chips, onTap: _send),
        const Divider(height: 1, color: AppColors.darkBorder),

        // قائمة الرسائل
        Expanded(
          child: chat.messages.isEmpty
              ? _EmptyState(onTap: _send)
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
                    return _MessageBubble(message: msg);
                  },
                ),
        ),

        // حقل الإدخال
        _InputBar(
          ctrl: _ctrl,
          onSend: _send,
          loading: chat.loading,
        ),
      ],
    );
  }
}

// ── شريط الاقتراحات ──────────────────────────────────────────────────
class _QuickChips extends StatelessWidget {
  final List<(String, String)> chips;
  final void Function(String) onTap;
  const _QuickChips({required this.chips, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, icon) = chips[i];
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onTap(label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                '$icon $label',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── فقاعة الرسالة ──────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                  child: Text('🤖', style: TextStyle(fontSize: 16))),
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
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                  child: Text('👤', style: TextStyle(fontSize: 16))),
            ),
          ],
        ],
      ),
    );
  }
}

// ── مؤشر الكتابة ──────────────────────────────────────────────────
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
                  colors: [AppColors.primary, AppColors.primaryDark]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 16))),
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

// ── حالة فارغة ──────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final void Function(String) onTap;
  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 40))),
          ),
          const SizedBox(height: 16),
          const Text('حكيم',
              style: TextStyle(
                  color: AppColors.textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('مساعدك الذكي للصيدلية',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── حقل الإدخال ──────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final void Function(String) onSend;
  final bool loading;
  const _InputBar(
      {required this.ctrl, required this.onSend, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkCard,
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              textDirection: TextDirection.rtl,
              textInputAction: TextInputAction.send,
              onSubmitted: loading ? null : onSend,
              style: const TextStyle(color: AppColors.textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'اكتب أمراً أو سؤالاً...',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                filled: true,
                fillColor: AppColors.dark,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.darkBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.darkBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(onTap: () => onSend(ctrl.text), loading: loading),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;
  const _SendButton({required this.onTap, required this.loading});

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
                      strokeWidth: 2, color: AppColors.primary),
                ),
              )
            : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// ── ديالوج إعدادات API ──────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════
class ApiSettingsDialog extends StatefulWidget {
  const ApiSettingsDialog({super.key});
  @override
  State<ApiSettingsDialog> createState() => _ApiSettingsDialogState();
}

class _ApiSettingsDialogState extends State<ApiSettingsDialog> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
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
      _loading = false;
    });
  }

  Future<void> _save() async {
    await ChatService.instance.saveApiSettings(
      url: _urlCtrl.text.trim(),
      key: _keyCtrl.text.trim(),
      type: _type,
      name: _nameCtrl.text.trim(),
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
    setState(() => _type = 'openai');
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
          side: const BorderSide(color: AppColors.darkBorder)),
      child: _loading
          ? const SizedBox(
              height: 200,
              child: Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)))
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
                            child: Text('⚙️',
                                style: TextStyle(fontSize: 20))),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('إعدادات الذكاء الاصطناعي',
                                style: TextStyle(
                                    color: AppColors.textColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                            Text('أضف مفتاح API الخاص بك',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close,
                            color: AppColors.textMuted, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // نوع API
                  const Text('نوع الـ API:',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _TypeChip(
                          label: 'OpenAI',
                          value: 'openai',
                          selected: _type == 'openai',
                          onTap: () => setState(() => _type = 'openai')),
                      const SizedBox(width: 8),
                      _TypeChip(
                          label: 'مخصص',
                          value: 'custom',
                          selected: _type == 'custom',
                          onTap: () => setState(() => _type = 'custom')),
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
                  _ApiField(
                    controller: _urlCtrl,
                    label: 'رابط الـ API',
                    hint: _type == 'openai'
                        ? 'https://api.openai.com/v1'
                        : 'https://your-api.com/endpoint',
                    icon: Icons.link,
                  ),
                  const SizedBox(height: 12),

                  // مفتاح الـ API
                  _ApiField(
                    controller: _keyCtrl,
                    label: 'مفتاح الـ API (API Key)',
                    hint: 'sk-...',
                    icon: Icons.key,
                    obscure: !_keyVisible,
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _keyVisible = !_keyVisible),
                      icon: Icon(
                        _keyVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
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
                        border: Border.all(
                            color:
                                AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: const Text(
                        '💡 يدعم: OpenAI, Groq, Together AI, OpenRouter, وأي API متوافق مع OpenAI',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  const SizedBox(height: 20),

                  // أزرار
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clear,
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: AppColors.danger),
                          label: const Text('مسح',
                              style: TextStyle(color: AppColors.danger)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
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
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
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
  const _TypeChip(
      {required this.label,
      required this.value,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.dark,
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
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.w400,
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
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: AppColors.textColor, fontSize: 13),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 12),
            prefixIcon:
                Icon(icon, color: AppColors.textMuted, size: 18),
            suffixIcon: suffix,
            filled: true,
            fillColor: AppColors.dark,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.darkBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.darkBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppColors.primary, width: 1.5)),
          ),
        ),
      ],
    );
  }
}
