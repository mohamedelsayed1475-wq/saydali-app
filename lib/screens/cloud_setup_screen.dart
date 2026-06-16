import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../services/scheduled_sync_service.dart';
import '../providers/current_user_provider.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // للوصول لـ MainScreen

class CloudSetupScreen extends StatefulWidget {
  const CloudSetupScreen({super.key});

  @override
  State<CloudSetupScreen> createState() => _CloudSetupScreenState();
}

class _CloudSetupScreenState extends State<CloudSetupScreen> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _portalController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _portalController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    final portal = _portalController.text.trim();

    try {
      // التحقق الأساسي من اتصال الـ Supabase عن طريق استعلام خفيف
      final checkUrl = url.endsWith('/') ? url : '$url/';
      final res = await http
          .get(Uri.parse('${checkUrl}rest/v1/'), headers: {
            'apikey': key,
            'Authorization': 'Bearer $key',
          })
          .timeout(const Duration(seconds: 12));

      // إذا كان الرد 200 أو حتى 404/400، فمعناه أن الرابط استجاب والمفاتيح متصلة بالخادم
      if (res.statusCode == 200 || res.statusCode == 404 || res.statusCode == 400 || res.statusCode == 401) {
        final db = DatabaseHelper.instance;

        // حفظ الإعدادات في قاعدة البيانات المحلية
        await db.setSetting('supabase_url', url);
        await db.setSetting('supabase_key', key);
        await db.setSetting('web_portal_url', portal);

        // توليد معرف سحابي فريد للصيدلية إذا لم يكن موجوداً
        var pharmacyCloudId = await db.getSetting('pharmacy_cloud_id');
        if (pharmacyCloudId == null || pharmacyCloudId.isEmpty) {
          pharmacyCloudId = 'pharmacy_${DateTime.now().millisecondsSinceEpoch}_${url.hashCode.abs()}';
          await db.setSetting('pharmacy_cloud_id', pharmacyCloudId);
        }

        // تحديث تهيئة خدمات Supabase و Sync ديناميكياً
        await SupabaseService.instance.initializeDynamic();

        if (!mounted) return;

        // تفعيل حساب المستخدم كمالك
        context.read<CurrentUserProvider>().loginAsOwner();

        // بدء خدمات المزامنة التلقائية والجدولة
        await SyncService.instance.registerPharmacy();
        SyncService.instance.startPeriodicSync();
        await ScheduledSyncService.registerDevice();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚀 تم حفظ الإعدادات وربط السحابة بنجاح!'),
            backgroundColor: AppColors.primary,
          ),
        );

        // التوجيه إلى الشاشة الرئيسية للتطبيق
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _errorMessage = 'بيانات السحابة غير صحيحة (استجابة الخادم: ${res.statusCode}). يرجى التحقق من المفتاح والرابط.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'فشل الاتصال برابط Supabase. يرجى التأكد من كتابة الرابط بشكل صحيح ومن وجود اتصال نشط بالإنترنت.';
      });
      debugPrint('Cloud connection check failed: $e');
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
      appBar: AppBar(
        title: const Text('إعداد السحابة وبوابة الويب'),
        backgroundColor: AppColors.darkCard,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.darkBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.cloud_sync_rounded,
                      size: 64,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ربط سحابة الصيدلية',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'أدخل بيانات خادم Supabase الخاص بك، بالإضافة إلى رابط بوابة الويب ليتمكن المساعدون من مزامنة وتصفح البيانات.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textLight,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // حقل رابط Supabase
                    _buildLabel('رابط Supabase URL'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('https://xxx.supabase.co'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'يرجى إدخال الرابط';
                        if (!v.startsWith('http://') && !v.startsWith('https://')) {
                          return 'يجب أن يبدأ الرابط بـ http أو https';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // حقل Anon Key
                    _buildLabel('مفتاح Anon Key (API Key)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _keyController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('أدخل مفتاح Anon Key الطويل الخاص بـ Supabase'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'يرجى إدخال مفتاح Anon Key';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // حقل رابط بوابة الويب
                    _buildLabel('رابط بوابة الويب (Web Portal URL)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _portalController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('https://your-portal.vercel.app'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'يرجى إدخال رابط البوابة';
                        if (!v.startsWith('http://') && !v.startsWith('https://')) {
                          return 'يجب أن يبدأ الرابط بـ http أو https';
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
                    // زر الحفظ والتفعيل
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveConfig,
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
                              'حفظ وتفعيل السحابة 🚀',
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
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.bold,
        fontSize: 14,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      fillColor: AppColors.dark.withOpacity(0.5),
      filled: true,
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
    );
  }
}
