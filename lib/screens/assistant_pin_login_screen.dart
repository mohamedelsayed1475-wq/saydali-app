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
      
      // محاولة التحقق من تسجيل الدخول مباشرة من Supabase أولاً
      Map<String, dynamic>? assistantMap;
      try {
        assistantMap = await SyncService.instance.checkAssistantLoginByPin(pin);
      } catch (e) {
        debugPrint('⚠️ Supabase login check failed: $e');
      }

      // إذا لم ينجح التحقق من السحابة (مثلاً لعدم وجود إنترنت)، نلجأ لقاعدة البيانات المحلية
      assistantMap ??= await db.getAssistantByPin(pin);

      if (assistantMap == null) {
        setState(() {
          _loading = false;
          _errorMessage = 'رمز PIN غير صحيح أو الحساب معطل';
          _pinController.clear();
        });
        return;
      }

      final assistant = Assistant.fromMap(assistantMap);

      // Check subscription
      if (assistant.isSubscriptionExpired) {
        setState(() {
          _loading = false;
          _errorMessage = 'انتهى اشتراكك، يرجى التواصل مع الصيدلية لتجديد التفعيل';
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
      await db.setSetting('logged_in_assistant_id', assistant.id.toString());
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
                  Container(
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
                      child: Text('💊', style: TextStyle(fontSize: 44)),
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
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 15,
                          spreadRadius: 1,
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
