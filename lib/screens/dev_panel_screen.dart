import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
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

  Future<void> _addCode() async {
    final codeCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '30');
    final discountCtrl = TextEditingController(text: '0');
    final maxUsesCtrl = TextEditingController(text: '1');
    String plan = 'pro';

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
                const Text('🎟️ إضافة كود جديد',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: AppTextField(
                            hint: 'الكود (مثال: SAYDALI2026)',
                            controller: codeCtrl)),
                    const SizedBox(width: 8),
                    IconButton(
                      icon:
                          const Icon(Icons.autorenew, color: AppColors.primary),
                      onPressed: () => setBS(() => generateRandomCode()),
                      tooltip: 'توليد تلقائي',
                    )
                  ],
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: AppTextField(
                          hint: 'مدة (أيام)',
                          controller: daysCtrl,
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: AppTextField(
                          hint: 'خصم %',
                          controller: discountCtrl,
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: AppTextField(
                          hint: 'عدد مرات الاستخدام',
                          controller: maxUsesCtrl,
                          keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 10),
                const Text('الباقة',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  for (final p in ['basic', 'pro', 'premium', 'assistant'])
                    ChoiceChip(
                      label: Text(p == 'assistant' ? '👥 مساعدين' : p),
                      selected: plan == p,
                      onSelected: (_) => setBS(() => plan = p),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.dark,
                      labelStyle: TextStyle(
                          color: plan == p ? Colors.white : AppColors.textMuted,
                          fontSize: 12),
                      side: BorderSide(
                          color: plan == p
                              ? AppColors.primary
                              : AppColors.darkBorder),
                    ),
                ]),
                const SizedBox(height: 16),
                PrimaryButton(
                  text: 'إضافة الكود',
                  onTap: () async {
                    final code = codeCtrl.text.trim().toUpperCase();
                    if (code.isEmpty) return;
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
                    // أغلق الشيت فوراً وحدّث القائمة بدون انتظار السحابة
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadCodes();
                    if (mounted) showSnack(context, 'تم حفظ الكود ✅ جاري الرفع للسحابة...');
                    // رفع للسحابة في الخلفية
                    SupabaseService.instance.insertSubscriptionCode(data).then((ok) {
                      if (mounted) {
                        if (ok) {
                          showSnack(context, 'تم رفع الكود للسحابة بنجاح ☁️✅');
                        } else {
                          showSnack(context, 'فشل الرفع للسحابة - الكود محفوظ محلياً فقط ⚠️', isError: true, durationMs: 3000);
                        }
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

  Future<void> _addAd() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    final whatsappCtrl = TextEditingController();
    final msgCtrl = TextEditingController(
        text: 'مرحباً، أنا أستخدم تطبيق صيدلي PRO وأود طلب منتجكم.');
    final btnTextCtrl = TextEditingController(text: 'التواصل عبر واتساب');
    final durationCtrl = TextEditingController(text: '0');
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
                      'created_at': DateTime.now().toIso8601String(),
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
        title: const Text('لوحة المطور 🔐',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔐', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            const Text('الدخول مقصور على المطور فقط',
                style: TextStyle(
                    color: AppColors.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('أدخل كلمة مرور المطور',
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 24),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: const TextStyle(color: AppColors.textColor),
              decoration: const InputDecoration(
                hintText: 'كلمة المرور',
                prefixIcon: Icon(Icons.lock_rounded, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              text: 'دخول',
              icon: Icons.login_rounded,
              onTap: () {
                if (_passCtrl.text == _devPass) {
                  setState(() => _authenticated = true);
                } else {
                  showSnack(context, 'كلمة مرور خاطئة', isError: true);
                }
              },
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
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
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
                    return Container(
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
                                child: Text(c['code'],
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        letterSpacing: 2)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppColors.primaryLight
                                      : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(isActive ? 'فعال' : 'منتهي',
                                    style: TextStyle(
                                        color: isActive
                                            ? AppColors.primary
                                            : AppColors.danger,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            children: [
                              _codeInfo('الباقة', c['plan']),
                              _codeInfo('المدة', '${c['duration_days']} يوم'),
                              _codeInfo('خصم', '${c['discount_percent']}%'),
                              _codeInfo('الاستخدام',
                                  '${c['used_count']}/${c['max_uses']}'),
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

  Widget _codeInfo(String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
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
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ad['title'],
                                    style: const TextStyle(
                                        color: AppColors.textColor,
                                        fontWeight: FontWeight.w700)),
                                Text(ad['body'],
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                Text('الشاشة: ${ad['screen']}',
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 11)),
                              ],
                            ),
                          ),
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
