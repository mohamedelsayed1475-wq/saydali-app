import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../providers/current_user_provider.dart';
import '../utils/app_theme.dart';
import '../services/sync_service.dart';
import '../services/scheduled_sync_service.dart';
import 'subscription_screen.dart';
import '../widgets/pharmacy_logo.dart';
import '../main.dart';

class AssistantPinLoginScreen extends StatefulWidget {
  final String? initialErrorMessage;
  const AssistantPinLoginScreen({super.key, this.initialErrorMessage});

  @override
  State<AssistantPinLoginScreen> createState() => _AssistantPinLoginScreenState();
}

class _AssistantPinLoginScreenState extends State<AssistantPinLoginScreen>
    with SingleTickerProviderStateMixin {
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  // ── تشخيص المشكلة (اضغط على الأيقونة 5 مرات) ──
  int _diagTapCount = 0;
  DateTime? _lastDiagTap;

  void _onLogoDiagTap() {
    final now = DateTime.now();
    if (_lastDiagTap == null || now.difference(_lastDiagTap!) > const Duration(seconds: 3)) {
      _diagTapCount = 0;
    }
    _lastDiagTap = now;
    _diagTapCount++;
    if (_diagTapCount >= 5) {
      _diagTapCount = 0;
      _runDiagnostics();
    }
  }

  Future<void> _runDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF1E293B),
        content: Row(
          children: [
            CircularProgressIndicator(color: Color(0xFF10B981)),
            SizedBox(width: 16),
            Text('جاري التشخيص...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    final db = DatabaseHelper.instance;
    final results = <String, dynamic>{};

    // 1. تحقق من إعدادات الصيدلية المحلية
    final pharmacyCloudId = await db.getSetting('pharmacy_cloud_id');
    final pharmacyCode = await db.getSetting('pharmacy_code');
    final pharmacyName = await db.getSetting('pharmacy_name');
    final isAssistantDevice = await db.getSetting('is_assistant_device');
    results['pharmacy_cloud_id'] = pharmacyCloudId ?? '❌ غير موجود';
    results['pharmacy_code'] = pharmacyCode ?? '❌ غير موجود';
    results['pharmacy_name'] = pharmacyName ?? '❌ غير موجود';
    results['is_assistant_device'] = isAssistantDevice ?? '❌ غير موجود';

    // 2. تحقق من المساعدين المحليين
    final localAssistants = await db.getAssistants();
    results['local_assistants_count'] = localAssistants.length;
    final assistantsSummary = localAssistants.map((a) =>
      '${a['name']} | PIN:${a['pin']} | active:${a['is_active']} | cloud_id:${a['cloud_id'] ?? 'null'} | exp:${(a['subscription_expiry'] ?? 'null').toString().substring(0, 10)}'
    ).join('\n');
    results['local_assistants'] = assistantsSummary.isEmpty ? '❌ لا يوجد مساعدون محلياً' : assistantsSummary;

    // 3. تحقق من الاتصال بـ Supabase
    try {
      final isConfigured = SyncService.instance.isConfigured;
      results['supabase_configured'] = isConfigured ? '✅ نعم' : '❌ لا';
      if (isConfigured) {
        // محاولة جلب المساعدين من Supabase
        if (pharmacyCloudId != null && pharmacyCloudId.isNotEmpty) {
          // جرّب الاتصال بـ Supabase
          await SyncService.instance.pullAssistantsFromServer().timeout(const Duration(seconds: 8));
          results['supabase_connection'] = '✅ متصل';

          // تحقق من المساعدين بعد السحب
          final afterPull = await db.getAssistants();
          results['assistants_after_pull'] = afterPull.length.toString();
        } else {
          results['supabase_connection'] = '⚠️ pharmacy_cloud_id مش موجود - تعذر الاتصال';
        }
      }
    } catch (e) {
      results['supabase_connection'] = '❌ فشل الاتصال: $e';
    }

    // 4. تحقق من الـ PIN المدخل لو موجود
    final currentPin = _pinController.text.trim();
    if (currentPin.length == 4) {
      final localMatch = await db.getAssistantByPin(currentPin);
      results['pin_in_local_db'] = localMatch != null ? '✅ موجود: ${localMatch['name']}' : '❌ غير موجود في DB المحلي';
    } else {
      results['pin_in_local_db'] = '⚠️ لم تدخل PIN بعد';
    }

    if (mounted) Navigator.pop(context); // close loading dialog

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Row(
            children: [
              Text('🔍', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('تشخيص المشكلة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: results.entries.map((e) {
                final isError = e.value.toString().startsWith('❌');
                final isWarn = e.value.toString().startsWith('⚠️');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isError
                          ? Colors.red.withValues(alpha: 0.15)
                          : isWarn
                              ? Colors.orange.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isError
                            ? Colors.red.withValues(alpha: 0.4)
                            : isWarn
                                ? Colors.orange.withValues(alpha: 0.4)
                                : Colors.green.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          style: TextStyle(
                            color: isError ? Colors.red[300] : isWarn ? Colors.orange[300] : Colors.green[300],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          e.value.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق', style: TextStyle(color: Color(0xFF10B981))),
            ),
          ],
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialErrorMessage;
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 4 || int.tryParse(pin) == null) {
      setState(() => _errorMessage = 'رمز PIN يجب أن يكون 4 أرقام');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final db = DatabaseHelper.instance;
      
      // ── خطوة 1: مزامنة المساعدين من السيرفر أولاً (لضمان أحدث بيانات) ──
      try {
        await SyncService.instance.pullAssistantsFromServer()
            .timeout(const Duration(seconds: 6));
        debugPrint('✅ تم سحب المساعدين من السيرفر قبل تسجيل الدخول');
      } catch (e) {
        debugPrint('⚠️ تعذّر سحب المساعدين من السيرفر: $e');
      }

      // ── خطوة 2: التحقق من PIN في السحابة مباشرةً ──
      Map<String, dynamic>? assistantMap;
      try {
        assistantMap = await SyncService.instance.checkAssistantLoginByPin(pin);
      } catch (e) {
        debugPrint('⚠️ Supabase login check failed: $e');
      }
      // ── خطوة 3: لو السحابة ما ردّت، ابحث محلياً ──
      assistantMap ??= await db.getAssistantByPin(pin);

      // لو فشل الاثنان، نحاول تحديث المساعدين من السحابة ثم نحاول مرة أخرى
      if (assistantMap == null) {
        try {
          await SyncService.instance.pullAssistantsFromServer();
          assistantMap = await db.getAssistantByPin(pin);
        } catch (e) {
          debugPrint('⚠️ Retry pull assistants failed: $e');
        }
      }

      if (assistantMap == null) {
        // ── خطوة 4: تشخيص أدق للخطأ ──
        // هل المساعد موجود بهذا الـ PIN لكن غير نشط؟
        final allDbRes = await (await db.database).query(
          'assistants',
          where: 'pin = ?',
          whereArgs: [pin],
        );
        String errMsg;
        if (allDbRes.isNotEmpty) {
          final a = allDbRes.first;
          if ((a['is_active'] ?? 1) == 0) {
            errMsg = 'الحساب معطل، يرجى التواصل مع صاحب الصيدلية';
          } else {
            errMsg = 'رمز PIN غير صحيح أو الحساب معطل';
          }
        } else {
          errMsg = 'رمز PIN غير صحيح أو لم تتم المزامنة بعد، تأكد من الاتصال بالإنترنت وأعد المحاولة';
        }
        setState(() {
          _loading = false;
          _errorMessage = errMsg;
          _pinController.clear();
        });
        return;
      }

      final assistant = Assistant.fromMap(assistantMap);

      // Check subscription (مع سماح 3 أيام grace period)
      if (assistant.subscriptionExpiry != null &&
          DateTime.now().isAfter(
              assistant.subscriptionExpiry!.add(const Duration(days: 3)))) {
        final expStr = '${assistant.subscriptionExpiry!.day}/${assistant.subscriptionExpiry!.month}/${assistant.subscriptionExpiry!.year}';
        setState(() {
          _loading = false;
          _errorMessage = 'انتهى اشتراكك بتاريخ $expStr، يرجى التواصل مع الصيدلية لتجديد التفعيل';
          _pinController.clear();
        });
        return;
      }

      // Generate Session Token and Expiry
      final random = Random.secure();
      final values = List<int>.generate(16, (i) => random.nextInt(256));
      final sessionToken = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      // Session lasts 30 days or until assistant subscription ends (whichever is sooner)
      DateTime sessionExpiry = DateTime.now().add(const Duration(days: 30));
      if (assistant.subscriptionExpiry != null &&
          assistant.subscriptionExpiry!.isBefore(sessionExpiry)) {
        sessionExpiry = assistant.subscriptionExpiry!;
      }

      // Store in SQLite settings
      await db.setSetting('logged_in_assistant_id', (assistant.id ?? 0).toString());
      await db.setSetting('assistant_session_token', sessionToken);
      await db.setSetting('assistant_session_expiry', sessionExpiry.toIso8601String());

      if (!mounted) return;

      // Log activity
      await db.logActivity(
        assistantId: assistant.id,
        assistantName: assistant.name,
        action: 'تسجيل دخول تلقائي/مساعد',
        details: 'تم الدخول برمز PIN للمساعد: ${assistant.name}',
        screen: 'assistant_login',
      );

      // Set user provider state
      context.read<CurrentUserProvider>().loginAsAssistant(assistant);

      // Start Sync
      SyncService.instance.startPeriodicSync();
      ScheduledSyncService.registerDevice();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'حدث خطأ غير متوقع: $e';
      });
    }
  }

  Future<void> _logoutFromPharmacy() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تسجيل الخروج من الصيدلية',
            textDirection: TextDirection.rtl,
            style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
          'هل تريد إلغاء ربط هذا الجهاز بالصيدلية تماماً؟ ستحتاج لإدخال كود الصيدلية مرة أخرى للدخول.',
          textDirection: TextDirection.rtl,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('خروج وإلغاء الربط', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loading = true);
      final db = DatabaseHelper.instance;
      await db.setSetting('is_assistant_device', '0');
      await db.setSetting('assistants_activated', '0');
      await db.clearAssistantSession();
      // Stop sync
      SyncService.instance.stopSync();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Logo
                  GestureDetector(
                    onTap: _onLogoDiagTap,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 25,
                            spreadRadius: 3,
                          )
                        ],
                      ),
                      child: const Center(
                        child: PharmacyLogo(size: 44),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'تسجيل دخول المساعد',
                    style: TextStyle(
                      color: AppColors.textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'أدخل رمز PIN الخاص بك للبدء',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // PIN Form Container
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.darkBorder),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'رمز الدخول الشخصي (PIN)',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('🔐', style: TextStyle(fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          obscureText: true,
                          textAlign: TextAlign.center,
                          autofocus: true,
                          enabled: !_loading,
                          style: const TextStyle(
                            color: AppColors.textColor,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: '• • • •',
                            hintStyle: TextStyle(
                              color: AppColors.textMuted.withValues(alpha: 0.3),
                              letterSpacing: 12,
                            ),
                            counterText: '',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: _errorMessage != null ? AppColors.danger : AppColors.darkBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2),
                            ),
                          ),
                          onChanged: (val) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            }
                            if (val.length == 4) {
                              _handleLogin();
                            }
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _errorMessage!,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'دخول المساعد',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                  // Log out / unlink device
                  TextButton.icon(
                    onPressed: _loading ? null : _logoutFromPharmacy,
                    icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 18),
                    label: const Text(
                      'إلغاء ربط الصيدلية وتسجيل الخروج',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
