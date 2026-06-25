import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';
import '../utils/env_config.dart';
import '../database/database_helper.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pharmacy_logo.dart';
import '../services/supabase_service.dart';
import '../utils/security_helper.dart';
import '../main.dart';
import 'assistant_pin_login_screen.dart';
import '../services/sync_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with SingleTickerProviderStateMixin {
  final _codeCtrl = TextEditingController();
  bool _isValidating = false;
  String? _codeError;
  int _selectedPlan = 0;
  double _currentPrice = 300;
  int _discountPercent = 0;
  String _currency = 'ج.م';
  late AnimationController _glowCtrl;
  int _extraSlots = 0;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _loadExtraSlots();
  }

  Future<void> _loadExtraSlots() async {
    final extras = await DatabaseHelper.instance.getExtraAssistantSlots();
    final currency = await DatabaseHelper.instance.getCurrency();
    if (mounted) setState(() {
      _extraSlots = extras;
      _currency = currency;
    });
  }

  final _plans = [
    (
      name: 'بريميوم + مساعدين',
      medal: '💎',
      badge: '🔥 الأفضل قيمة',
      price: 300,
      duration: 'شهر',
      color: const Color(0xFFAB47BC),
      gradient: const [Color(0xFF1A0A2E), Color(0xFF2D1060)],
      features: [
        'كل ميزات البريميوم بلا حدود',
        '3 مساعدين + صلاحيات + تتبع نشاط',
        'مزامنة سحابية بين الأجهزة',
        'تصدير فواتير PDF & Excel',
        'تقارير وإحصائيات متقدمة',
        'نسخ احتياطي تلقائي',
        'دعم فني متميز 24/7',
      ],
    ),
    (
      name: 'بريميوم',
      medal: '👑',
      badge: '⭐ الأكثر شعبية',
      price: 199,
      duration: 'شهر',
      color: const Color(0xFFFFD700),
      gradient: const [Color(0xFF2D1B00), Color(0xFF4A3200)],
      features: [
        'كل ميزات التطبيق بلا حدود',
        'مزامنة سحابية بين الأجهزة',
        'تصدير فواتير PDF & Excel',
        'تقارير وإحصائيات متقدمة',
        'نسخ احتياطي تلقائي',
        'دعم فني متميز 24/7',
      ],
    ),
    (
      name: 'باقة المساعدين',
      medal: '👥',
      badge: '',
      price: 99,
      duration: 'شهر',
      color: AppColors.primary,
      gradient: const [Color(0xFF0D2E1C), Color(0xFF0A3525)],
      features: [
        'إضافة 3 مساعدين',
        'صلاحيات مخصصة لكل مساعد',
        'تتبع نشاط المساعدين',
        'مزامنة فورية بين الأجهزة',
      ],
    ),
    (
      name: 'مساعد إضافي',
      medal: '👤',
      badge: '',
      price: 49, // سعر أساسي (يتغير ديناميكياً)
      duration: 'شهر',
      color: Colors.teal,
      gradient: const [Color(0xFF0D1B2E), Color(0xFF132A3E)],
      features: [
        'إضافة مساعد واحد إضافي',
        'بحد أقصى 3 أماكن إضافية',
        'التسعير: الأول 49 · الثاني 99 · الثالث 149 ج.م',
      ],
    ),
  ];

  @override
  void dispose() {
    _codeCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _joinAsAssistant() async {
    final codeCtrl = TextEditingController();
    bool isJoining = false;
    String error = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('👨‍⚕️ دخول كمساعد صيدلي', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('أدخل كود الصيدلية المكون من 6 أرقام (يمكن للمالك الحصول عليه من الإعدادات)', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textColor, fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  hintText: '• • • • • •',
                  counterText: '',
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: error.isNotEmpty ? AppColors.danger : AppColors.darkBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
                ),
                onChanged: (v) {
                  if (error.isNotEmpty) setDlg(() => error = '');
                },
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isJoining ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: isJoining ? null : () async {
                final code = codeCtrl.text.trim().toUpperCase();
                if (code.length != 8) {
                  setDlg(() => error = 'كود الصيدلية يجب أن يكون 8 أرقام/حروف');
                  return;
                }
                setDlg(() { isJoining = true; error = ''; });
                final res = await SyncService.instance.joinPharmacy(code);
                setDlg(() => isJoining = false);
                
                if (res.success) {
                  // joinPharmacy بيستدعي pullAssistantsFromServer داخلياً ويحفظ المساعدين تلقائياً
                  // فقط نحفظ الإعدادات وننتقل لشاشة الـ PIN
                  final db = DatabaseHelper.instance;

                  // تأكيد إضافي: لو ما فيش مساعدين محلياً، نجرب مرة ثانية
                  final localCount = await db.getActiveAssistantCount();
                  if (localCount == 0) {
                    try {
                      await SyncService.instance.pullAssistantsFromServer()
                          .timeout(const Duration(seconds: 8));
                    } catch (e) {
                      debugPrint('⚠️ retry pullAssistants error: $e');
                    }
                  }
                  await db.setSetting('assistants_activated', '1');
                  await db.setSetting('is_assistant_device', '1');
                  final expiry = DateTime.now().add(const Duration(days: 3650)).toIso8601String();
                  await SecurityHelper.saveSignedSetting('subscription_expiry', expiry);
                  
                  if (ctx.mounted) {
                    Navigator.pop(ctx); // Close Dialog
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AssistantPinLoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                } else {
                  setDlg(() => error = res.error ?? 'حدث خطأ غير معروف');
                }
              },
              child: isJoining ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('انضمام'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _validateCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _codeError = 'أدخل كود الخصم أو الاشتراك');
      return;
    }


    // Admin bypass (عبر الهاش الآمن من Secrets)
    if (SecurityHelper.verifyAdminCode(code, EnvConfig.adminCode1Hash) ||
        SecurityHelper.verifyAdminCode(code, EnvConfig.adminCode2Hash)) {
      final expiry =
          DateTime.now().add(const Duration(days: 3650)).toIso8601String();
      await SecurityHelper.saveSignedSetting('subscription_expiry', expiry);
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

    // ── مزامنة الأكواد من السحابة أولاً (مع حد زمني قصير) ──
    try {
      final cloudCodes = await SupabaseService.instance.fetchSubscriptionCodes()
          .timeout(const Duration(seconds: 4), onTimeout: () => []);
      if (cloudCodes.isNotEmpty) {
        await db.syncCodesFromCloud(cloudCodes);
      }
    } catch (_) {}

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
      // محاولة أخيرة مباشرة من Supabase
      try {
        data = await SupabaseService.instance.checkSubscriptionCode(code)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
      } catch (_) {}
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

      final plan = data['plan']?.toString() ?? '';
      final discount = (data['discount_percent'] is int) ? data['discount_percent'] : int.tryParse(data['discount_percent']?.toString() ?? '0') ?? 0;
      final duration = (data['duration_days'] is int) ? data['duration_days'] : int.tryParse(data['duration_days']?.toString() ?? '30') ?? 30;

      // ── تحديث عدد الاستخدام (مشترك لكل الأنواع) ──
      if (isLocal) {
        await localDb.update(
            'subscription_codes', {'used_count': usedCount + 1},
            where: 'code = ?', whereArgs: [code]);
      }
      SupabaseService.instance.updateSubscriptionCodeUsage(code, usedCount + 1);

      // ── كود بريميوم + مساعدين: يفعل الاشتراك + 3 مساعدين ──
      if (plan == 'premium_assistants') {
        // تفعيل الاشتراك
        final expiry = DateTime.now().add(Duration(days: duration)).toIso8601String();
        await SecurityHelper.saveSignedSetting('subscription_expiry', expiry);
        // تفعيل المساعدين
        await db.addAssistantSlots(3);
        await db.setSetting('assistants_activated', '1');
        final totalSlots = await db.getAssistantSlots();
        showSnack(context, '✅ تم تفعيل البريميوم + 3 مساعدين! (الإجمالي: $totalSlots)');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MainScreen()),
                (route) => false);
          }
        });
        return;
      }

      // ── كود مساعدين: يضيف 3 أماكن مساعدين ──
      if (plan == 'assistant' || plan == 'assistant_3') {
        await db.addAssistantSlots(3);
        await db.setSetting('assistants_activated', '1');
        final totalSlots = await db.getAssistantSlots();
        showSnack(context, '✅ تم تفعيل 3 أماكن مساعدين! (الإجمالي: $totalSlots)');
        return;
      }

      // ── كود مساعد إضافي: يضيف مكان واحد (بحد أقصى 3 إضافية) ──
      if (plan == 'assistant_1') {
        final extras = await db.getExtraAssistantSlots();
        if (extras >= DatabaseHelper.maxExtraAssistantSlots) {
          setState(() => _codeError = '❌ وصلت للحد الأقصى (${DatabaseHelper.maxExtraAssistantSlots} أماكن إضافية)');
          return;
        }
        await db.addAssistantSlots(1);
        final totalSlots = await db.getAssistantSlots();
        showSnack(context, '✅ تم تفعيل مكان مساعد إضافي! (${extras + 1}/${DatabaseHelper.maxExtraAssistantSlots} إضافي - الإجمالي: $totalSlots)');
        return;
      }

      // ── كود خصم ──
      if (discount > 0 && discount < 100) {
        setState(() {
          _discountPercent = discount;
          final basePrice = _plans[_selectedPlan].price;
          _currentPrice = basePrice - (basePrice * discount / 100);
        });
        showSnack(context, '✅ تم تطبيق خصم $discount% بنجاح!');
      } else {
        // ── كود اشتراك كامل ──
        showSnack(context, '✅ تم تفعيل الاشتراك بنجاح!');
        final expiry =
            DateTime.now().add(Duration(days: duration)).toIso8601String();
        await SecurityHelper.saveSignedSetting('subscription_expiry', expiry);

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
          // ── Premium Hero Section ──
          AnimatedBuilder(
            animation: _glowCtrl,
            builder: (context, child) {
              final glow = _glowCtrl.value * 0.3 + 0.1;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0A1628), Color(0xFF0D2E1C), Color(0xFF132233)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: glow),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 70, height: 70,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withValues(alpha: 0.5), blurRadius: 20),
                        ],
                      ),
                      child: const Center(child: PharmacyLogo(size: 36)),
                    ),
                    const SizedBox(height: 14),
                    const Text('صيدلي PRO',
                        style: TextStyle(color: AppColors.primary, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    const Text('أدِر صيدليتك باحترافية',
                        style: TextStyle(color: AppColors.textLight, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 16),
                    // Trust signals
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _trustBadge('🔒', 'مشفّر'),
                        const SizedBox(width: 12),
                        _trustBadge('⚡', 'فوري'),
                        const SizedBox(width: 12),
                        _trustBadge('💬', 'دعم 24/7'),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // ── Plans Section ──
          Row(
            children: [
              const Text('📦', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('اختر باقتك',
                  style: TextStyle(color: AppColors.textColor, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('4 باقات', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _plans.length; i++) _buildPlanCard(i),
          const SizedBox(height: 24),

          // ── Code Section ──
          Row(
            children: [
              const Text('🎟️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('كود التفعيل أو الخصم',
                  style: TextStyle(color: AppColors.textColor, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
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

          // ── Payment Methods ──
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('💳', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('طرق الدفع',
                  style: TextStyle(color: AppColors.textColor, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          // How-to steps
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
            ),
            child: const Row(
              children: [
                Expanded(child: Column(
                  children: [
                    Text('1️⃣', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 2),
                    Text('ادفع', style: TextStyle(color: AppColors.textLight, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                )),
                Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted, size: 16),
                Expanded(child: Column(
                  children: [
                    Text('2️⃣', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 2),
                    Text('أرسل الإيصال', style: TextStyle(color: AppColors.textLight, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                )),
                Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted, size: 16),
                Expanded(child: Column(
                  children: [
                    Text('3️⃣', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 2),
                    Text('استلم الكود', style: TextStyle(color: AppColors.textLight, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                )),
              ],
            ),
          ),

          // ── InstaPay Card ──
          GestureDetector(
            onTap: () => _openLink(
                'https://ipn.eg/S/drmohamedelsayed123/instapay/3MXYr5'),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1040), Color(0xFF2D1B69)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // أيقونة InstaPay
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Center(
                            child: Text('💸',
                                style: TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('InstaPay',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17)),
                            Text('تحويل فوري عبر انستاباي',
                                style: TextStyle(
                                    color: Color(0xFFB4B4FF),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.send_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('ادفع',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // عنوان انستاباي مع نسخ
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(const ClipboardData(
                          text: 'drmohamedelsayed123@instapay'));
                      showSnack(context, 'تم نسخ عنوان InstaPay ✅');
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                const Color(0xFF6366F1).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.copy_rounded,
                              color: Color(0xFFB4B4FF), size: 16),
                          SizedBox(width: 8),
                          Text('drmohamedelsayed123@instapay',
                              style: TextStyle(
                                  color: Color(0xFFE0E0FF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Vodafone Cash Card ──
          GestureDetector(
            onTap: () => _openLink('http://vf.eg/vfcash?id=mt&qrId=kJcnNk'),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D0A0A), Color(0xFF3D1515)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: const Color(0xFFE60028).withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE60028).withValues(alpha: 0.12),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // أيقونة فودافون
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE60028), Color(0xFFFF3355)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFFE60028).withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Center(
                        child:
                            Text('📱', style: TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vodafone Cash',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        Text('تحويل عبر فودافون كاش',
                            style: TextStyle(
                                color: Color(0xFFFFB4B4), fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE60028),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFFE60028).withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.send_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('ادفع',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Contact Developer ──
          Row(
            children: [
              const Text('📞', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('تواصل مع المطور',
                  style: TextStyle(color: AppColors.textColor, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D1B2E), Color(0xFF132A3E)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: const Color(0xFF229ED9).withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Text('👨‍💻', style: TextStyle(fontSize: 30)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('د. محمد السيد',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          Text('للاستفسار والدعم الفني والأكواد',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // زر تليجرام
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            _openLink('https://t.me/Mohamed07Elsayed'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF229ED9), Color(0xFF1A8BC7)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF229ED9)
                                    .withValues(alpha: 0.35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('✈️',
                                  style: TextStyle(fontSize: 18)),
                              SizedBox(width: 8),
                              Text('Telegram',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // زر واتساب
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openLink(
                            'https://wa.me/201055261422'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF25D366), Color(0xFF1EBE5D)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF25D366)
                                    .withValues(alpha: 0.35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('💬',
                                  style: TextStyle(fontSize: 18)),
                              SizedBox(width: 8),
                              Text('WhatsApp',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── Assistant Join ──
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF132233), Color(0xFF1A2D42)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: InkWell(
              onTap: _joinAsAssistant,
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: Text('👨‍⚕️', style: TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('هل أنت مساعد صيدلي؟', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('انضم لصيدليتك بكود الصيدلية', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _trustBadge(String emoji, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.textLight, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPlanCard(int index) {
    final plan = _plans[index];
    final isSelected = _selectedPlan == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedPlan = index;
          _currentPrice = plan.price.toDouble();
          if (_discountPercent > 0) {
            _currentPrice = plan.price - (plan.price * _discountPercent / 100);
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isSelected
                  ? plan.gradient
                  : [AppColors.darkCard, AppColors.darkCard],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? plan.color.withValues(alpha: 0.6) : AppColors.darkBorder,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected ? [
              BoxShadow(color: plan.color.withValues(alpha: 0.15), blurRadius: 16, spreadRadius: 1),
            ] : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Icon circle
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: plan.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(child: Text(plan.medal, style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.name, style: TextStyle(color: plan.color, fontWeight: FontWeight.w800, fontSize: 16)),
                        if (plan.badge.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: plan.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(plan.badge, style: TextStyle(color: plan.color, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // السعر الديناميكي للمساعد الإضافي
                      if (index == 3 && _extraSlots < DatabaseHelper.maxExtraAssistantSlots) ...[
                        Text('${DatabaseHelper.getNextExtraPrice(_extraSlots)}', style: TextStyle(color: plan.color, fontWeight: FontWeight.w800, fontSize: 24)),
                        Text('$_currency/شهر', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        Text('(${_extraSlots}/3 مفعّل)', style: TextStyle(color: plan.color.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w600)),
                      ] else if (index == 3 && _extraSlots >= DatabaseHelper.maxExtraAssistantSlots) ...[
                        Text('مكتمل', style: TextStyle(color: plan.color, fontWeight: FontWeight.w800, fontSize: 16)),
                        const Text('3/3 ✅', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ] else ...[
                        Text('${plan.price}', style: TextStyle(color: plan.color, fontWeight: FontWeight.w800, fontSize: 24)),
                        Text('$_currency/شهر', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ],
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: plan.color,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              // Features as clean list
              ...plan.features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: plan.color, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: const TextStyle(color: AppColors.textLight, fontSize: 13, fontWeight: FontWeight.w500))),
                  ],
                ),
              )),
            ],
          ),
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
