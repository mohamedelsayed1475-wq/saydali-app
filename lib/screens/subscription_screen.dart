import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';
import '../utils/env_config.dart';
import '../database/database_helper.dart';
import '../widgets/common_widgets.dart';
import '../services/supabase_service.dart';
import '../main.dart'; // import MainScreen
import 'package:url_launcher/url_launcher.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _codeCtrl = TextEditingController();
  bool _isValidating = false;
  String? _codeError;
  int _selectedPlan = 0; // 0=premium
  double _currentPrice = 200;
  int _discountPercent = 0;
  String _currency = 'ج.م';

  final _plans = [
    (
      name: 'بريميوم',
      medal: '🥇',
      price: 200,
      duration: 'شهر',
      color: AppColors.warning,
      features: [
        'إدارة النواقص والديون',
        'مندوبون غير محدودون',
        'تصدير فواتير (PDF & Excel)',
        'نسخ احتياطي سحابي',
        'دعم فني متميز 24/7'
      ],
    ),
  ];

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _validateCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _codeError = 'أدخل كود الخصم أو الاشتراك');
      return;
    }

    // Developer / Manager Bypass
    const fallbackCodes = {'ADMIN2026', 'DEV@SAYDALI2026'};
    if (code == EnvConfig.adminCode1 ||
        code == EnvConfig.adminCode2 ||
        fallbackCodes.contains(code)) {
      final expiry =
          DateTime.now().add(const Duration(days: 3650)).toIso8601String();
      await DatabaseHelper.instance.setSetting('subscription_expiry', expiry);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
      return;
    }

    setState(() {
      _isValidating = true;
      _codeError = null;
    });

    final db = DatabaseHelper.instance;
    final localDb = await db.database;

    List<Map<String, dynamic>> localCodes = [];
    try {
      localCodes = await localDb
          .query('subscription_codes', where: 'code = ?', whereArgs: [code]);
    } catch (_) {}

    Map<String, dynamic>? data;
    bool isLocal = false;

    if (localCodes.isNotEmpty) {
      data = localCodes.first;
      isLocal = true;
    } else {
      data = await SupabaseService.instance.checkSubscriptionCode(code);
    }

    if (mounted) {
      setState(() => _isValidating = false);

      if (data == null) {
        setState(() => _codeError = 'كود غير صحيح');
        return;
      }

      // ── التحقق من حالة الكود ──
      final rawActive = data['is_active'];
      final bool isActive = rawActive == true || rawActive == 1 ||
          rawActive == '1' || rawActive == 'true';
      if (!isActive) {
        setState(() => _codeError = '❌ الكود غير فعال أو منتهي');
        return;
      }

      final maxUses = (data['max_uses'] is int) ? data['max_uses'] : int.tryParse(data['max_uses']?.toString() ?? '1') ?? 1;
      final usedCount = (data['used_count'] is int) ? data['used_count'] : int.tryParse(data['used_count']?.toString() ?? '0') ?? 0;
      if (usedCount >= maxUses) {
        setState(() => _codeError = '❌ الكود تم استخدامه بالكامل');
        return;
      }

      final discount = (data['discount_percent'] is int) ? data['discount_percent'] : int.tryParse(data['discount_percent']?.toString() ?? '0') ?? 0;
      final duration = (data['duration_days'] is int) ? data['duration_days'] : int.tryParse(data['duration_days']?.toString() ?? '30') ?? 30;

      if (discount > 0 && discount < 100) {
        if (isLocal) {
          await localDb.update(
              'subscription_codes', {'used_count': usedCount + 1},
              where: 'code = ?', whereArgs: [code]);
        }
        await SupabaseService.instance.updateSubscriptionCodeUsage(code, usedCount + 1);
        
        setState(() {
          _discountPercent = discount;
          _currentPrice = 200 - (200 * discount / 100);
        });
        showSnack(context, '✅ تم تطبيق خصم $discount% بنجاح!');
      } else {
        if (isLocal) {
          await localDb.update(
              'subscription_codes', {'used_count': usedCount + 1},
              where: 'code = ?', whereArgs: [code]);
        }
        await SupabaseService.instance.updateSubscriptionCodeUsage(code, usedCount + 1);
        showSnack(context, '✅ تم تفعيل الاشتراك بنجاح!');
        final expiry =
            DateTime.now().add(Duration(days: duration)).toIso8601String();
        await db.setSetting('subscription_expiry', expiry);

        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MainScreen()),
                (route) => false);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('الاشتراك والتفعيل',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D2E1C), Color(0xFF132233)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryDark),
            ),
            child: Column(
              children: [
                const Text('💊', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                const Text('صيدلي PRO',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const Text('اختر الباقة المناسبة لصيدليتك',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Plans
          const Text('📦 الباقات المتاحة',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (int i = 0; i < _plans.length; i++) _buildPlanCard(i),
          const SizedBox(height: 20),

          // Discount Code
          const Text('🎟️ كود الخصم أو التفعيل',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        style: const TextStyle(
                            color: AppColors.textColor,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w700),
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'XXXXXXXX',
                          hintStyle: const TextStyle(
                              color: AppColors.textMuted, letterSpacing: 3),
                          errorText: _codeError,
                          prefixIcon: const Icon(
                              Icons.confirmation_number_rounded,
                              color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _isValidating ? null : _validateCode,
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16)),
                      child: _isValidating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('تفعيل'),
                    ),
                  ],
                ),
                if (_discountPercent > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('باقي الحساب للتحويل:',
                            style: TextStyle(
                                color: AppColors.textColor,
                                fontWeight: FontWeight.w700)),
                        Text('$_currentPrice $_currency',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Payment Methods
          const Text('💳 طرق الدفع',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          // Vodafone Cash
          _buildPaymentCard(
            emoji: '📱',
            title: 'Vodafone Cash',
            subtitle: 'اضغط لتحويل عبر فودافون كاش',
            color: const Color(0xFFE60028),
            onTap: () => _openLink('http://vf.eg/vfcash?id=mt&qrId=kJcnNk'),
          ),
          const SizedBox(height: 10),

          // InstaPay
          _buildPaymentCard(
            emoji: '💸',
            title: 'InstaPay',
            subtitle: 'drmohamedelsayed123@instapay',
            color: const Color(0xFF6366F1),
            onTap: () => _openLink(
                'https://ipn.eg/S/drmohamedelsayed123/instapay/3MXYr5'),
            trailing: IconButton(
              icon:
                  const Icon(Icons.copy, color: AppColors.textMuted, size: 18),
              onPressed: () {
                Clipboard.setData(
                    const ClipboardData(text: 'drmohamedelsayed123@instapay'));
                showSnack(context, 'تم نسخ عنوان InstaPay ✅');
              },
            ),
          ),
          const SizedBox(height: 20),

          // Contact Developer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFF229ED9).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF229ED9).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                      child: Text('✈️', style: TextStyle(fontSize: 24))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تواصل مع المطور',
                          style: TextStyle(
                              color: AppColors.textColor,
                              fontWeight: FontWeight.w700)),
                      const Text('للاستفسار أو المشاكل الفنية',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _openLink('https://t.me/Mohamed07Elsayed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF229ED9),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Telegram', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildPlanCard(int index) {
    final plan = _plans[index];
    final isSelected = _selectedPlan == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlan = index),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? plan.color.withValues(alpha: 0.1)
                : AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isSelected ? plan.color : AppColors.darkBorder,
                width: isSelected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(plan.medal, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Text(plan.name,
                      style: TextStyle(
                          color: plan.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const Spacer(),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                            text: '${plan.price}',
                            style: TextStyle(
                                color: plan.color,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                fontFamily: 'Cairo')),
                        const TextSpan(
                            text: '/شهر',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle_rounded, color: plan.color),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: plan.features
                    .map((f) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: plan.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: plan.color.withValues(alpha: 0.2)),
                          ),
                          child: Text('✓ $f',
                              style: TextStyle(
                                  color: plan.color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCard({
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12)),
              child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textColor,
                          fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            trailing ?? Icon(Icons.open_in_new_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  void _openLink(String urlStr) async {
    final url = Uri.parse(urlStr);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch');
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: urlStr));
      if (mounted)
        showSnack(context, 'لم نتمكن من فتح التطبيق - تم نسخ الرابط ✅');
    }
  }
}
