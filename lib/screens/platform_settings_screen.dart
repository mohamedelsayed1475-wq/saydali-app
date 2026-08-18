import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/platform_service.dart';
import '../widgets/common_widgets.dart';

class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({super.key});
  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  List<PlatformConfig> _platforms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PlatformService.instance.getPlatforms();
    if (mounted) setState(() { _platforms = list; _loading = false; });
  }

  Future<void> _addPlatform() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final searchCtrl = TextEditingController(text: '/api/search?q={query}');
    final orderCtrl = TextEditingController(text: '/api/order');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('🏪', style: TextStyle(fontSize: 24)),
                  SizedBox(width: 10),
                  Text('إضافة منصة جديدة',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'أضف منصة شركة الأدوية اللي بتتعامل معاها',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              AppTextField(
                  hint: 'اسم المنصة (مثال: دوايا)',
                  controller: nameCtrl),
              const SizedBox(height: 10),
              AppTextField(
                  hint: 'رابط API (مثال: https://api.dawaya.com)',
                  controller: urlCtrl),
              const SizedBox(height: 10),
              AppTextField(
                  hint: 'مفتاح API (من حسابك في المنصة)',
                  controller: keyCtrl),
              const SizedBox(height: 10),
              AppTextField(
                  hint: 'مسار البحث (مثال: /api/search?q={query})',
                  controller: searchCtrl),
              const SizedBox(height: 10),
              AppTextField(
                  hint: 'مسار الطلب (مثال: /api/order)',
                  controller: orderCtrl),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Text(
                  '💡 نصيحة: تواصل مع شركة الأدوية واطلب منهم بيانات الـ API (الرابط والمفتاح). '
                  'أغلب المنصات الكبيرة بتوفر API للصيدليات.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  textDirection: TextDirection.rtl,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                text: 'إضافة المنصة',
                icon: Icons.add_rounded,
                onTap: () async {
                  if (nameCtrl.text.trim().isEmpty ||
                      urlCtrl.text.trim().isEmpty) {
                    showSnack(context, 'أدخل الاسم والرابط على الأقل',
                        isError: true);
                    return;
                  }
                  await PlatformService.instance.addPlatform(PlatformConfig(
                    name: nameCtrl.text.trim(),
                    baseUrl: urlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
                    apiKey: keyCtrl.text.trim(),
                    searchPath: searchCtrl.text.trim(),
                    orderPath: orderCtrl.text.trim(),
                  ));
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                  if (mounted) showSnack(context, '✅ تم إضافة المنصة');
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('📱 منصات الأدوية',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'platform_settings_fab',
        onPressed: _addPlatform,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة منصة',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _platforms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🏪', style: TextStyle(fontSize: 50)),
                      const SizedBox(height: 12),
                      const Text('لا توجد منصات',
                          style: TextStyle(
                              color: AppColors.textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text(
                        'أضف منصات شركات الأدوية\nللبحث والطلب من الشات بوت',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _addPlatform,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة أول منصة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _platforms.length,
                  itemBuilder: (ctx, i) {
                    final p = _platforms[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                                child: Text('🏪',
                                    style: TextStyle(fontSize: 20))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    style: const TextStyle(
                                        color: AppColors.textColor,
                                        fontWeight: FontWeight.w700)),
                                Text(p.baseUrl,
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                Text(
                                  p.apiKey.isNotEmpty
                                      ? '🔑 مفتاح API مضاف'
                                      : '⚠️ بدون مفتاح',
                                  style: TextStyle(
                                    color: p.apiKey.isNotEmpty
                                        ? AppColors.primary
                                        : AppColors.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.danger, size: 20),
                            onPressed: () async {
                              await PlatformService.instance
                                  .removePlatform(p.name);
                              await _load();
                              if (mounted) {
                                showSnack(context, '🗑️ تم حذف ${p.name}');
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
