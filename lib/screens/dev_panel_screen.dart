import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/app_theme.dart';
import '../utils/env_config.dart';
import '../database/database_helper.dart';
import '../widgets/common_widgets.dart';
import '../services/supabase_service.dart';

class DevPanelScreen extends StatefulWidget {
  const DevPanelScreen({super.key});

  @override
  State<DevPanelScreen> createState() => _DevPanelScreenState();
}

class _DevPanelScreenState extends State<DevPanelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _passCtrl = TextEditingController();
  bool _authenticated = false;
  static const _devPass = EnvConfig.devPassword;

  // أكواد الاشتراك
  List<Map<String, dynamic>> _codes = [];

  // الإعلانات
  List<Map<String, dynamic>> _ads = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _initDevTables();
  }

  Future<void> _initDevTables() async {
    // الجداول تم إنشاؤها في database_helper.dart → _onCreate
    // هنا فقط نحمل البيانات
    _loadCodes();
    _loadAds();
  }

  Future<void> _loadCodes() async {
    final db = await DatabaseHelper.instance.database;
    final codes =
        await db.query('subscription_codes', orderBy: 'created_at DESC');
    if (mounted) setState(() => _codes = codes);
  }

  Future<void> _loadAds() async {
    final db = await DatabaseHelper.instance.database;
    final ads = await db.query('ads', orderBy: 'created_at DESC');
    if (mounted) setState(() => _ads = ads);
  }

  // خريطة الباقات مع التفاصيل
  static const _planOptions = [
    {'id': 'premium', 'label': '👑 بريميوم', 'desc': 'كل ميزات التطبيق (199 ج.م/شهر)'},
    {'id': 'assistant', 'label': '👥 3 مساعدين', 'desc': '3 أماكن مساعدين (99 ج.م/شهر)'},
    {'id': 'assistant_1', 'label': '👤 مساعد إضافي', 'desc': 'مكان واحد - تسعير تصاعدي (49→99→149 ج.م)'},
    {'id': 'premium_assistants', 'label': '💎 بريميوم+مساعدين', 'desc': 'كل الميزات + 3 مساعدين (300 ج.م/شهر)'},
  ];

  String _getPlanLabel(String planId) {
    for (final p in _planOptions) {
      if (p['id'] == planId) return p['label']!;
    }
    return planId;
  }

  Future<void> _addCode() async {
    final codeCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '30');
    final discountCtrl = TextEditingController(text: '0');
    final maxUsesCtrl = TextEditingController(text: '1');
    String plan = 'premium';

    void generateRandomCode() {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rnd = Random();
      codeCtrl.text = String.fromCharCodes(Iterable.generate(
          8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) {
          final selectedPlan = _planOptions.firstWhere(
              (p) => p['id'] == plan, orElse: () => _planOptions.first);

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 20, right: 20, top: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: AppColors.darkBorder,
                          borderRadius: BorderRadius.circular(99)))),
                  const SizedBox(height: 12),
                  const Text('🎟️ إضافة كود جديد',
                      style: TextStyle(color: AppColors.primary,
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 16),

                  // ── الكود ──
                  Row(
                    children: [
                      Expanded(child: AppTextField(
                          hint: 'الكود (مثال: SAYDALI2026)',
                          controller: codeCtrl)),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.autorenew, color: AppColors.primary),
                        onPressed: () => setBS(() => generateRandomCode()),
                        tooltip: 'توليد تلقائي',
                      )
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── اختيار الباقة ──
                  const Text('📦 نوع الباقة',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in _planOptions)
                      ChoiceChip(
                        label: Text(p['label']!, style: const TextStyle(fontSize: 11)),
                        selected: plan == p['id'],
                        onSelected: (_) => setBS(() => plan = p['id']!),
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.dark,
                        labelStyle: TextStyle(
                            color: plan == p['id'] ? Colors.white : AppColors.textMuted),
                        side: BorderSide(
                            color: plan == p['id'] ? AppColors.primary : AppColors.darkBorder),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                    ),
                    child: Text('ℹ️ ${selectedPlan['desc']}',
                      style: const TextStyle(color: AppColors.textLight, fontSize: 11, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 14),

                  // ── الإعدادات ──
                  Row(children: [
                    Expanded(child: AppTextField(
                        hint: 'مدة (أيام)', controller: daysCtrl,
                        keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: AppTextField(
                        hint: 'خصم %', controller: discountCtrl,
                        keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: AppTextField(
                        hint: 'مرات الاستخدام', controller: maxUsesCtrl,
                        keyboardType: TextInputType.number)),
                  ]),
                  const SizedBox(height: 16),

                  PrimaryButton(
                    text: 'إضافة الكود',
                    onTap: () async {
                      final code = codeCtrl.text.trim().toUpperCase();
                      if (code.isEmpty) {
                        showSnack(ctx, 'أدخل الكود', isError: true);
                        return;
                      }
                      final db = await DatabaseHelper.instance.database;
                      final data = {
                        'code': code,
                        'plan': plan,
                        'duration_days': int.tryParse(daysCtrl.text) ?? 30,
                        'discount_percent': int.tryParse(discountCtrl.text) ?? 0,
                        'max_uses': int.tryParse(maxUsesCtrl.text) ?? 1,
                        'used_count': 0,
                        'is_active': 1,
                        'created_at': DateTime.now().toIso8601String(),
                      };
                      await db.insert('subscription_codes', data);
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _loadCodes();
                      if (mounted) showSnack(context, 'تم حفظ الكود ✅ جاري الرفع للسحابة...');
                      SupabaseService.instance.insertSubscriptionCode(data).then((ok) {
                        if (mounted) {
                          if (ok) {
                            showSnack(context, 'تم رفع الكود للسحابة بنجاح ☁️✅');
                          } else {
                            showSnack(context, 'فشل الرفع للسحابة - محفوظ محلياً فقط ⚠️', isError: true, durationMs: 3000);
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addAd() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    final whatsappCtrl = TextEditingController();
    final msgCtrl = TextEditingController(
        text: 'مرحباً، أنا أستخدم تطبيق صيدلي PRO وأود طلب منتجكم.');
    final btnTextCtrl = TextEditingController(text: 'التواصل عبر واتساب');
    final durationCtrl = TextEditingController(text: '0');
    final expiryDaysCtrl = TextEditingController(text: '7');
    String screen = 'home';
    String? pickedImagePath;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📢 إضافة إعلان',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 16),
                AppTextField(hint: 'عنوان الإعلان', controller: titleCtrl),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'نص الإعلان', controller: bodyCtrl, maxLines: 3),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.platform
                              .pickFiles(type: FileType.image);
                          if (result != null) {
                            setBS(() =>
                                pickedImagePath = result.files.single.path);
                          }
                        },
                        icon: const Icon(Icons.image),
                        label: const Text('اختيار صورة من الهاتف'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                if (pickedImagePath != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(pickedImagePath!),
                        height: 120, width: double.infinity, fit: BoxFit.cover),
                  ),
                ],
                const SizedBox(height: 10),
                const Text('لتفعيل الطلب عبر الواتساب (لتتبع المبيعات):',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 5),
                AppTextField(
                    hint: 'رقم الواتساب للشركة (مثال: 20100000000+)',
                    controller: whatsappCtrl,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'الرسالة التلقائية لتأكيد المصدر',
                    controller: msgCtrl,
                    maxLines: 2),
                const SizedBox(height: 10),
                const Divider(color: AppColors.darkBorder),
                AppTextField(
                    hint:
                        'أو رابط خارجي عادي (يُترك فارغاً إذا كتبت رقم واتساب)',
                    controller: linkCtrl),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'نص زر التواصل (مثال: اطلب العرض الآن)',
                    controller: btnTextCtrl),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'مدة الإجبار قبل التخطي (ثواني)',
                    controller: durationCtrl,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'مدة الإعلان (أيام) - 0 = بدون انتهاء',
                    controller: expiryDaysCtrl,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                const Text('الشاشة',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  for (final s in [
                    {'id': 'home', 'label': 'الرئيسية'},
                    {'id': 'shortages', 'label': 'النواقص'},
                    {'id': 'reports', 'label': 'التقارير'}
                  ])
                    ChoiceChip(
                      label: Text(s['label']!),
                      selected: screen == s['id'],
                      onSelected: (_) => setBS(() => screen = s['id']!),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.dark,
                      labelStyle: TextStyle(
                          color: screen == s['id']
                              ? Colors.white
                              : AppColors.textMuted,
                          fontSize: 12),
                      side: BorderSide(
                          color: screen == s['id']
                              ? AppColors.primary
                              : AppColors.darkBorder),
                    ),
                ]),
                const SizedBox(height: 16),
                PrimaryButton(
                  text: 'نشر الإعلان',
                  onTap: () async {
                    if (titleCtrl.text.trim().isEmpty) return;

                    String finalLink = linkCtrl.text.trim();
                    final phone = whatsappCtrl.text.trim();
                    if (phone.isNotEmpty) {
                      final msg = Uri.encodeComponent(msgCtrl.text.trim());
                      final formattedPhone =
                          phone.replaceAll('+', '').replaceAll(' ', '');
                      finalLink = 'https://wa.me/$formattedPhone?text=$msg';
                    }

                    String? imageUrl;
                    if (pickedImagePath != null) {
                      imageUrl = await SupabaseService.instance.uploadAdImage(pickedImagePath!);
                    }

                    final now = DateTime.now();
                    final expiryDays = int.tryParse(expiryDaysCtrl.text) ?? 0;
                    final expiresAt = expiryDays > 0
                        ? now.add(Duration(days: expiryDays)).toIso8601String()
                        : '';

                    final db = await DatabaseHelper.instance.database;
                    final data = {
                      'title': titleCtrl.text.trim(),
                      'body': bodyCtrl.text.trim(),
                      'image_url': imageUrl ?? '',
                      'link': finalLink,
                      'button_text': btnTextCtrl.text.trim().isEmpty
                          ? 'التفاصيل'
                          : btnTextCtrl.text.trim(),
                      'is_active': 1,
                      'screen': screen,
                      'skip_duration': int.tryParse(durationCtrl.text) ?? 0,
                      'expires_at': expiresAt,
                      'created_at': now.toIso8601String(),
                    };
                    await db.insert('ads', data);
                    // أغلق الشيت فوراً بدون انتظار السحابة
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadAds();
                    if (mounted) showSnack(context, 'تم نشر الإعلان ✅');
                    // رفع للسحابة في الخلفية
                    SupabaseService.instance.insertAd(data).then((ok) {
                      if (mounted && !ok) {
                        showSnack(context, 'فشل رفع الإعلان للسحابة ⚠️', isError: true, durationMs: 3000);
                      }
                    });
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_authenticated) return _buildLogin();
    return _buildPanel();
  }

  Widget _buildLogin() {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('لوحة المطور',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2D1B00), Color(0xFF4A3200)]),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: AppColors.warning.withValues(alpha: 0.3), blurRadius: 24)],
              ),
              child: const Center(child: Text('🔐', style: TextStyle(fontSize: 44))),
            ),
            const SizedBox(height: 20),
            const Text('لوحة تحكم المطور',
                style: TextStyle(color: AppColors.textColor, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('أدخل كلمة مرور المطور للوصول',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 28),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: const TextStyle(color: AppColors.textColor),
              decoration: InputDecoration(
                hintText: 'كلمة المرور',
                prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.warning),
                filled: true,
                fillColor: AppColors.darkCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.warning, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_passCtrl.text == _devPass) {
                    setState(() => _authenticated = true);
                  } else {
                    showSnack(context, 'كلمة مرور خاطئة', isError: true);
                  }
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text('دخول', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('لوحة المطور 🛠️',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.warning,
          indicatorWeight: 3,
          labelColor: AppColors.warning,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: '🎟️ الأكواد'),
            Tab(text: '📢 الإعلانات'),
            Tab(text: '📊 الإحصاء'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildCodesTab(),
          _buildAdsTab(),
          _buildStatsTab(),
        ],
      ),
    );
  }

  Widget _buildCodesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(
              text: '➕ إضافة كود جديد', onTap: _addCode, icon: Icons.add),
        ),
        Expanded(
          child: _codes.isEmpty
              ? const EmptyState(
                  emoji: '🎟️',
                  title: 'لا توجد أكواد',
                  subtitle: 'أضف أكواد الاشتراك والخصم')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _codes.length,
                  itemBuilder: (ctx, i) {
                    final c = _codes[i];
                    final isActive = c['is_active'] == 1;
                    final planLabel = _getPlanLabel(c['plan'] ?? '');
                    return Dismissible(
                      key: Key('code_${c['id']}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 24),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete_outline, color: AppColors.danger),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.darkCard,
                            title: const Text('حذف الكود؟', style: TextStyle(color: AppColors.danger)),
                            content: Text('هل تريد حذف الكود ${c['code']}؟',
                                style: const TextStyle(color: AppColors.textMuted)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('إلغاء')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('حذف'),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (_) async {
                        final db = await DatabaseHelper.instance.database;
                        await db.delete('subscription_codes', where: 'id = ?', whereArgs: [c['id']]);
                        _loadCodes();
                        if (mounted) showSnack(context, 'تم حذف الكود 🗑️');
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: isActive
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : AppColors.darkBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: c['code']));
                                      showSnack(context, 'تم نسخ الكود 📋');
                                    },
                                    child: Row(
                                      children: [
                                        Text(c['code'],
                                            style: const TextStyle(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                                letterSpacing: 2)),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.copy_rounded, color: AppColors.textMuted, size: 14),
                                      ],
                                    ),
                                  ),
                                ),
                                // Toggle active/inactive
                                GestureDetector(
                                  onTap: () async {
                                    final db = await DatabaseHelper.instance.database;
                                    await db.update('subscription_codes',
                                        {'is_active': isActive ? 0 : 1},
                                        where: 'id = ?', whereArgs: [c['id']]);
                                    _loadCodes();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppColors.primaryLight
                                          : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(isActive ? '✅ فعال' : '⛔ معطل',
                                        style: TextStyle(
                                            color: isActive ? AppColors.primary : AppColors.danger,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                _codeInfo('📦', planLabel),
                                _codeInfo('📅', '${c['duration_days']} يوم'),
                                if ((c['discount_percent'] ?? 0) > 0)
                                  _codeInfo('🏷️', 'خصم ${c['discount_percent']}%'),
                                _codeInfo('👥', '${c['used_count']}/${c['max_uses']} استخدام'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _codeInfo(String emoji, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$emoji ', style: const TextStyle(fontSize: 11)),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildAdsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(
              text: '📢 إضافة إعلان جديد', onTap: _addAd, icon: Icons.campaign),
        ),
        Expanded(
          child: _ads.isEmpty
              ? const EmptyState(
                  emoji: '📢',
                  title: 'لا توجد إعلانات',
                  subtitle: 'أضف إعلانات لعرضها للمستخدمين')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _ads.length,
                  itemBuilder: (ctx, i) {
                    final ad = _ads[i];
                    final isActive = ad['is_active'] == 1;
                    final expiresAt = ad['expires_at']?.toString() ?? '';
                    final isExpired = expiresAt.isNotEmpty &&
                        DateTime.tryParse(expiresAt)?.isBefore(DateTime.now()) == true;
                    String expiryText = 'بدون انتهاء';
                    if (expiresAt.isNotEmpty) {
                      final dt = DateTime.tryParse(expiresAt);
                      if (dt != null) {
                        final diff = dt.difference(DateTime.now()).inDays;
                        expiryText = isExpired ? 'منتهي ❌' : 'متبقي $diff يوم';
                      }
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isExpired
                              ? AppColors.danger.withValues(alpha: 0.3)
                              : isActive
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : AppColors.darkBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(ad['title'],
                                    style: const TextStyle(
                                        color: AppColors.textColor,
                                        fontWeight: FontWeight.w700)),
                              ),
                              // Delete button
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                                onPressed: () async {
                                  final db = await DatabaseHelper.instance.database;
                                  await db.delete('ads', where: 'id = ?', whereArgs: [ad['id']]);
                                  await _loadAds();
                                  if (mounted) showSnack(context, 'تم حذف الإعلان 🗑️');
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: isActive,
                                activeThumbColor: AppColors.primary,
                                onChanged: (v) async {
                                  final db = await DatabaseHelper.instance.database;
                                  await db.update('ads', {'is_active': v ? 1 : 0},
                                      where: 'id = ?', whereArgs: [ad['id']]);
                                  await _loadAds();
                                },
                              ),
                            ],
                          ),
                          Text(ad['body'],
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('📺 ${ad['screen']}',
                                    style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isExpired
                                      ? AppColors.danger.withValues(alpha: 0.1)
                                      : AppColors.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('⏳ $expiryText',
                                    style: TextStyle(
                                        color: isExpired ? AppColors.danger : AppColors.warning,
                                        fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatsTab() {
    return FutureBuilder<Map<String, int>>(
      future: DatabaseHelper.instance.getShortageStats(),
      builder: (ctx, snap) {
        if (!snap.hasData)
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        final stats = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statRow('💊 إجمالي النواقص', '${stats['total']}'),
            _statRow('✅ تمت التغطية', '${stats['covered']}'),
            _statRow('⚠️ مستعصية', '${stats['stubborn']}'),
            _statRow('🎟️ أكواد مفعلة',
                '${_codes.where((c) => c['is_active'] == 1).length}'),
            _statRow('📢 إعلانات نشطة',
                '${_ads.where((a) => a['is_active'] == 1).length}'),
          ],
        );
      },
    );
  }

  Widget _statRow(String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.darkBorder)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textLight)),
            Text(value,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
          ],
        ),
      );
}
