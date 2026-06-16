import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import 'cloud_setup_screen.dart';


class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleActivation() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final enteredCode = _codeController.text.trim();

    try {
      // التحقق من كود التفعيل عبر رابط ملف جيت هاب
      final response = await http
          .get(Uri.parse(
              'https://raw.githubusercontent.com/mohamedelsayed1475-wq/saydali-app/main/activation_codes.txt'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final content = response.body;
        // تقسيم الملف لأسطر وتنظيفها
        final codes = content
            .split('\n')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();

        if (codes.contains(enteredCode)) {
          // الكود صحيح! حفظ التفعيل محلياً
          final db = DatabaseHelper.instance;
          await db.setSetting('is_activated', '1');
          await db.setSetting('activation_code', enteredCode);

          if (!mounted) return;

          // إظهار رسالة النجاح
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 تم تفعيل التطبيق بنجاح! جاري الانتقال للإعداد السحابي...'),
              backgroundColor: AppColors.primary,
            ),
          );

          // التوجيه إلى شاشة إعداد السحابة
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CloudSetupScreen()),
          );
        } else {
          setState(() {
            _errorMessage = 'كود التفعيل غير صالح أو تم استخدامه مسبقاً. يرجى مراجعة المطور.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'فشل جلب الأكواد من الخادم (خطأ ${response.statusCode}). يرجى المحاولة لاحقاً.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في الاتصال بالإنترنت. يرجى التأكد من اتصالك بالشبكة والمحاولة مرة أخرى.';
      });
      debugPrint('Activation error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // شعار التطبيق بتصميم جذاب
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withOpacity(0.4),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: const Icon(
                    Icons.vpn_key_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                // اسم التطبيق
                const Text(
                  'صيدلي PRO',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'نظام إدارة الصيدليات المتكامل',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 32),
                // حاوية إدخال الكود (بطاقة بتصميم فخم)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.darkBorder, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'تنشيط النسخة',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'يرجى إدخال كود التفعيل الذي حصلت عليه لتنشيط رخصتك مدى الحياة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textLight,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // حقل إدخال الكود
                        TextFormField(
                          controller: _codeController,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                          decoration: InputDecoration(
                            hintText: 'XXXX-XXXX-XXXX-XXXX',
                            hintStyle: TextStyle(
                              color: AppColors.textMuted.withOpacity(0.5),
                              fontSize: 16,
                              letterSpacing: 1.5,
                            ),
                            fillColor: AppColors.dark.withOpacity(0.5),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppColors.darkBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppColors.danger),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال كود التفعيل';
                            }
                            return null;
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: AppColors.danger,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        // زر التفعيل
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleActivation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                            disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'تفعيل التطبيق الآن',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // تذييل الصفحة للتواصل
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'ليس لديك كود؟ ',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    GestureDetector(
                      onTap: () {
                        // الانتقال لروابط الدعم أو إبراز طريقة التواصل
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.darkCard,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text(
                              'شراء نسخة وتنشيطها',
                              textAlign: TextAlign.right,
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            content: const Text(
                              'للحصول على كود تفعيل وتنشيط رخصتك مدى الحياة، يرجى التواصل مع المطور عبر تليجرام:\n\n@Mohamed07Elsayed',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(color: AppColors.textLight, height: 1.6),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('حسناً', style: TextStyle(color: AppColors.primary)),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text(
                        'تواصل مع المطور',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
