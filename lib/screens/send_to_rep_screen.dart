import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'rep_response_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class SendToRepScreen extends StatefulWidget {
  final Representative rep;
  const SendToRepScreen({super.key, required this.rep});

  @override
  State<SendToRepScreen> createState() => _SendToRepScreenState();
}

class _SendToRepScreenState extends State<SendToRepScreen> {
  List<Shortage> _shortages = [];
  Set<int> _selected = {};
  bool _loading = true;
  bool _sending = false;
  String? _generatedLink;

  @override
  void initState() {
    super.initState();
    _loadShortages();
  }

  Future<void> _loadShortages() async {
    final data = await DatabaseHelper.instance.getShortages();
    if (mounted) {
      setState(() {
        // فقط الأصناف pending أو stubborn
        _shortages = data
            .map(Shortage.fromMap)
            .where((s) => s.status == 'pending' || s.status == 'stubborn')
            .toList();
        // اختيار كل الـ pending تلقائياً
        _selected = _shortages
            .where((s) => s.status == 'pending' && !s.isUrgent)
            .map((s) => s.id!)
            .toSet();
        _loading = false;
      });
    }
  }

  Future<void> _sendToRep() async {
    if (_selected.isEmpty) {
      showSnack(context, 'اختر صنفاً واحداً على الأقل', isError: true);
      return;
    }

    setState(() => _sending = true);

    final selectedItems = _shortages.where((s) => _selected.contains(s.id)).toList();
    final pharmacyName = await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدليتي';

    final items = selectedItems.map((s) => {
      'name': s.name,
      'company': s.company,
      'quantity': s.quantity,
      'is_private': 0,
    }).toList();

    final code = await SupabaseService.instance.createSession(
      repName: widget.rep.name,
      repPhone: widget.rep.phone ?? '',
      pharmacyName: pharmacyName,
      items: items,
    );

    if (mounted) {
      setState(() => _sending = false);
      if (code != null) {
        setState(() {
          _generatedLink = SupabaseService.instance.buildRepLink(code);
        });
        _showLinkSheet();
      } else {
        showSnack(context, 'فشل الإرسال - تحقق من الاتصال', isError: true);
      }
    }
  }

  void _showLinkSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.darkBorder, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 20),
            const Text('✅ تم إنشاء الرابط!', style: TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('أرسل الرابط لـ ${widget.rep.name}', style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 20),

            // الرابط
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _generatedLink ?? '',
                      style: const TextStyle(color: AppColors.primary, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AppColors.primary, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _generatedLink ?? ''));
                      showSnack(ctx, 'تم نسخ الرابط ✅');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // أزرار المشاركة
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final msg = 'مرحباً ${widget.rep.name}،\nيرجى مراجعة النواقص والرد عبر الرابط:\n$_generatedLink';
                      // فتح واتساب
                      final phone = widget.rep.phone?.replaceAll('+', '').replaceAll(' ', '') ?? '';
                      final urlStr = phone.isNotEmpty
                          ? 'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}'
                          : 'https://wa.me/?text=${Uri.encodeComponent(msg)}';
                      final url = Uri.parse(urlStr);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } else {
                        Clipboard.setData(ClipboardData(text: msg));
                        if (ctx.mounted) showSnack(ctx, 'تم نسخ الرسالة - افتح واتساب يدويًا');
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                    icon: const Icon(Icons.message, size: 16),
                    label: const Text('واتساب'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _generatedLink ?? ''));
                      showSnack(ctx, 'تم نسخ الرابط ✅');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkBorder),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('نسخ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // زر استقبال الرد
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RepResponseScreen()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('استقبال رد المندوب', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingItems = _shortages.where((s) => s.status == 'pending').toList();
    final stubbornItems = _shortages.where((s) => s.status == 'stubborn').toList();

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: Text('إرسال لـ ${widget.rep.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                '${_selected.length} محدد',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _shortages.isEmpty
              ? const EmptyState(
                  emoji: '🎉',
                  title: 'لا توجد نواقص',
                  subtitle: 'لا توجد أصناف بانتظار الرد',
                )
              : Column(
                  children: [
                    // Info Banner
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'اختر الأصناف التي تريد إرسالها. الأصناف العلامة 🔒 لن تُرسل.',
                              style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        children: [
                          if (pendingItems.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('⏳ بانتظار الرد', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                                TextButton(
                                  onPressed: () => setState(() {
                                    for (final s in pendingItems) _selected.add(s.id!);
                                  }),
                                  child: const Text('تحديد الكل', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                                ),
                              ],
                            ),
                            ...pendingItems.map((s) => _buildItemTile(s)),
                          ],

                          if (stubbornItems.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text('🔴 مستعصية', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            ...stubbornItems.map((s) => _buildItemTile(s)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: AppColors.darkCard,
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: SafeArea(
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _sendToRep,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(_sending ? 'جاري الإرسال...' : 'إرسال ${_selected.length} صنف'),
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile(Shortage item) {
    final isSelected = _selected.contains(item.id);
    return GestureDetector(
      onTap: () => setState(() {
        if (isSelected) _selected.remove(item.id);
        else _selected.add(item.id!);
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary.withValues(alpha: 0.5) : AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isSelected ? AppColors.primary : AppColors.textMuted),
              ),
              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: const TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('${item.company} · ${item.quantity} علبة', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (item.isUrgent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('🚨 عاجل', style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}
