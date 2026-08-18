import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../services/scheduled_sync_service.dart';
import '../providers/current_user_provider.dart';
import '../main.dart'; // للوصول لـ MainScreen

class CloudSetupScreen extends StatefulWidget {
  const CloudSetupScreen({super.key});

  @override
  State<CloudSetupScreen> createState() => _CloudSetupScreenState();
}

class _CloudSetupScreenState extends State<CloudSetupScreen> {
  final _quickPasteController = TextEditingController();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _portalController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successExtractMessage;
  bool _showManualFields = false;

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    final db = DatabaseHelper.instance;
    final url = await db.getSetting('supabase_url');
    final key = await db.getSetting('supabase_key');
    final portal = await db.getSetting('web_portal_url');
    if (mounted) {
      setState(() {
        if (url != null && url.isNotEmpty) _urlController.text = url;
        if (key != null && key.isNotEmpty) _keyController.text = key;
        if (portal != null && portal.isNotEmpty) _portalController.text = portal;
        if (url != null && url.isNotEmpty) _showManualFields = true;
      });
    }
  }

  @override
  void dispose() {
    _quickPasteController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _portalController.dispose();
    super.dispose();
  }

  /// الاستخراج الذكي من أي نص أو JSON أو .env ملصوق
  void _extractConfigFromText(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return;

    String? extractedUrl;
    String? extractedKey;
    String? extractedPortal;

    // 1. محاولة قراءة JSON
    try {
      if (text.startsWith('{') && text.endsWith('}')) {
        final Map<String, dynamic> json = jsonDecode(text);
        extractedUrl = json['supabase_url'] ?? json['url'] ?? json['SUPABASE_URL'] ?? json['apiUrl'];
        extractedKey = json['supabase_key'] ?? json['anon_key'] ?? json['key'] ?? json['SUPABASE_ANON_KEY'] ?? json['apiKey'];
        extractedPortal = json['web_portal_url'] ?? json['portal_url'] ?? json['WEB_PORTAL_URL'] ?? json['portal'];
      }
    } catch (_) {}

    // 2. محاولة البحث بواسطة التعبيرات النمطية (Regex) لو لم تكن JSON
    if (extractedUrl == null) {
      final urlMatch = RegExp(r'https?://[a-zA-Z0-9.\-_]+\.supabase\.co').firstMatch(text);
      if (urlMatch != null) {
        extractedUrl = urlMatch.group(0);
      }
    }

    if (extractedKey == null) {
      // مفتاح Supabase JWT Anon Key يبدأ بـ eyJ
      final keyMatch = RegExp(r'eyJ[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+').firstMatch(text);
      if (keyMatch != null) {
        extractedKey = keyMatch.group(0);
      }
    }

    if (extractedPortal == null) {
      // البحث عن أي رابط ويب آخر لا ينتهي بـ supabase.co
      final portalMatches = RegExp(r'https?://[a-zA-Z0-9.\-_/:]+').allMatches(text);
      for (final m in portalMatches) {
        final candidate = m.group(0);
        if (candidate != null && !candidate.contains('supabase.co')) {
          extractedPortal = candidate;
          break;
        }
      }
    }

    int foundCount = 0;
    if (extractedUrl != null && extractedUrl.isNotEmpty) {
      _urlController.text = extractedUrl;
      foundCount++;
    }
    if (extractedKey != null && extractedKey.isNotEmpty) {
      _keyController.text = extractedKey;
      foundCount++;
    }
    if (extractedPortal != null && extractedPortal.isNotEmpty) {
      _portalController.text = extractedPortal;
      foundCount++;
    }

    setState(() {
      if (foundCount > 0) {
        _successExtractMessage = '✨ تم استخراج $foundCount من البيانات بنجاح!';
        _errorMessage = null;
        _showManualFields = true;
      } else {
        _errorMessage = 'لم نتمكن من التعرف على بيانات Supabase من النص الملصوق. يرجى استخدام الإدخال اليدوي.';
        _successExtractMessage = null;
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _quickPasteController.text = data.text!;
      _extractConfigFromText(data.text!);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الحافظة فارغة!')),
        );
      }
    }
  }

  /// التخطي والمتابعة المباشرة بدون سحابة
  Future<void> _skipSetup() async {
    final db = DatabaseHelper.instance;
    // التأكد من تفعيل التطبيق محلياً
    await db.setSetting('is_activated', '1');

    if (!mounted) return;
    context.read<CurrentUserProvider>().loginAsOwner();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم المتابعة محلياً. يمكنك ربط السحابة في أي وقت من الإعدادات ☁️'),
        backgroundColor: AppColors.primary,
      ),
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
  }

  Future<void> _saveConfig() async {
    if (_urlController.text.trim().isEmpty || _keyController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'يرجى لصق الإعدادات أولاً أو إدخال الرابط والمفتاح.';
        _showManualFields = true;
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successExtractMessage = null;
    });

    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    final portal = _portalController.text.trim();

    try {
      final checkUrl = url.endsWith('/') ? url : '$url/';
      final res = await http
          .get(Uri.parse('${checkUrl}rest/v1/'), headers: {
            'apikey': key,
            'Authorization': 'Bearer $key',
          })
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 || res.statusCode == 404 || res.statusCode == 400 || res.statusCode == 401) {
        final db = DatabaseHelper.instance;
        await db.setSetting('supabase_url', url);
        await db.setSetting('supabase_key', key);
        if (portal.isNotEmpty) {
          await db.setSetting('web_portal_url', portal);
        }
        await db.setSetting('is_activated', '1');

        await SupabaseService.instance.initializeDynamic();

        if (!mounted) return;
        context.read<CurrentUserProvider>().loginAsOwner();

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

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _errorMessage = 'بيانات السحابة غير صحيحة (استجابة الخادم: ${res.statusCode}). يرجى التأكد من الرابط والمفتاح.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'فشل الاتصال بـ Supabase. يرجى التأكد من الرابط والاتصال بالإنترنت.';
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

  void _showGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('💡', style: TextStyle(fontSize: 24)),
            SizedBox(width: 10),
            Text(
              'دليل إعداد السحابة المجانية',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStepItem('1', 'افتح موقع Supabase المجاني (supabase.com) وسجّل حسابك.'),
              const SizedBox(height: 10),
              _buildStepItem('2', 'اضغط "New Project" واكتب اسم صيدليتك واختر كلمة مرور قاعدة البيانات.'),
              const SizedBox(height: 10),
              _buildStepItem('3', 'من القائمة الجانبية: ادخل على Project Settings (أيقونة الترس ⚙️) ثم API.'),
              const SizedBox(height: 10),
              _buildStepItem('4', 'انسخ Project URL و anon public key.'),
              const SizedBox(height: 10),
              _buildStepItem('5', 'ارجع للتطبيق واضغط "لصق واستخراج تلقائي" وسيتم التعرف عليها فوراً!'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse('https://supabase.com');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('فتح موقع Supabase 🌐'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 42),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('فهمت، شكراً', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textColor, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _skipSetup();
      },
      child: Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          title: const Text('إعداد السحابة وبوابة الويب'),
          backgroundColor: AppColors.darkCard,
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline_rounded, color: AppColors.primary),
              tooltip: 'دليل الإعداد',
              onPressed: _showGuideDialog,
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.darkBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.cloud_sync_rounded,
                      size: 56,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ربط سحابة الصيدلية',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اربط قاعدة بياناتك للمزامنة الفورية بين الهواتف والكمبيوتر وبوابة الويب.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // زر دليل الإعداد
                    OutlinedButton.icon(
                      onPressed: _showGuideDialog,
                      icon: const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                      label: const Text('لماذا أحتاج هذا؟ / دليل الإعداد السريع 💡'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // بطاقة اللصق السريع الذكي
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.dark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.flash_on_rounded, color: AppColors.warning, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'اللصق السريع الذكي (موصى به)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'انسخ أي نص يحتوي على بيانات المشروع أو JSON أو .env والصقه هنا دفعة واحدة:',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _quickPasteController,
                            maxLines: 2,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'الصق كائن الإعداد الكامل هنا...',
                              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                              fillColor: AppColors.darkCard,
                              filled: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.all(10),
                            ),
                            onChanged: _extractConfigFromText,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _pasteFromClipboard,
                                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                                  label: const Text('لصق من الحافظة 📋', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E3A5F),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              if (_quickPasteController.text.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () => _extractConfigFromText(_quickPasteController.text),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                  ),
                                  child: const Text('استخراج 🔍', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (_successExtractMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline, color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _successExtractMessage!,
                                style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // زر إظهار/إخفاء الحقول اليدوية
                    TextButton.icon(
                      onPressed: () => setState(() => _showManualFields = !_showManualFields),
                      icon: Icon(
                        _showManualFields ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                      label: Text(
                        _showManualFields ? 'إخفاء الحقول المنفصلة' : 'خيارات متقدمة: إدخال يدوي مفصل',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),

                    if (_showManualFields) ...[
                      const SizedBox(height: 10),
                      _buildLabel('رابط Supabase URL'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _urlController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _inputDecoration('https://xxx.supabase.co'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'يرجى إدخال الرابط';
                          if (!v.startsWith('http://') && !v.startsWith('https://')) {
                            return 'يجب أن يبدأ الرابط بـ http أو https';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildLabel('مفتاح Anon Key (API Key)'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _keyController,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: _inputDecoration('أدخل مفتاح Anon Key'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'يرجى إدخال مفتاح Anon Key';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildLabel('رابط بوابة الويب (اختياري)'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _portalController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _inputDecoration('https://your-portal.vercel.app'),
                      ),
                    ],

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: AppColors.danger, fontSize: 12, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // زر الحفظ والتفعيل
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'حفظ وتفعيل السحابة 🚀',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),

                    const SizedBox(height: 12),

                    // زر التخطي والعمل محلياً
                    OutlinedButton(
                      onPressed: _isLoading ? null : _skipSetup,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        side: const BorderSide(color: AppColors.darkBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'تخطي والعمل محلياً (إعداد لاحقاً) ⏭️',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
        fontSize: 13,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      fillColor: AppColors.dark.withValues(alpha: 0.5),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}
