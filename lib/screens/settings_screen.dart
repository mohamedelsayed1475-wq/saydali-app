import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/env_config.dart';
import 'invoice_screen.dart';
import '../utils/country_config.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import '../utils/security_helper.dart';
import '../widgets/common_widgets.dart';
import 'subscription_screen.dart';
import 'dev_panel_screen.dart';
import 'pin_lock_screen.dart';
import 'assistants_screen.dart';
import 'sync_schedule_screen.dart';

import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../providers/current_user_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _pharmacistCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _notificationsEnabled = true;
  bool _pinEnabled = false;
  bool _loading = true;
  int _devTapCount = 0;
  String _selectedCountryCode = 'EG';
  bool _autoCloseEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    if (mounted) {
      setState(() {
        _nameCtrl.text = settings['pharmacy_name'] ?? 'صيدليتي';
        _pharmacistCtrl.text = settings['pharmacist_name'] ?? 'الصيدلي';
        _phoneCtrl.text = settings['pharmacy_phone'] ?? '';
        _selectedCountryCode = settings['country_code'] ?? 'EG';
        _autoCloseEnabled = (settings['auto_close_enabled'] ?? '0') == '1';
        _notificationsEnabled =
            (settings['notifications_enabled'] ?? '1') == '1';
        _loading = false;
      });
      PinLockScreen.isPinEnabled().then((v) {
        if (mounted) setState(() => _pinEnabled = v);
      });
    }
  }

  Future<void> _saveSettings() async {
    await DatabaseHelper.instance
        .setSetting('pharmacy_name', _nameCtrl.text.trim());
    await DatabaseHelper.instance
        .setSetting('pharmacist_name', _pharmacistCtrl.text.trim());
    await DatabaseHelper.instance
        .setSetting('pharmacy_phone', _phoneCtrl.text.trim());
    await DatabaseHelper.instance
        .setSetting('country_code', _selectedCountryCode);
    final country = CountryConfig.getByCode(_selectedCountryCode);
    await DatabaseHelper.instance
        .setSetting('currency_symbol', country.currency);
    await DatabaseHelper.instance.setSetting('phone_code', country.phoneCode);
    await DatabaseHelper.instance
        .setSetting('notifications_enabled', _notificationsEnabled ? '1' : '0');
    if (mounted) showSnack(context, 'تم حفظ الإعدادات ✅');
  }

  @override
  Widget build(BuildContext context) {
    // فقط المالك يمكنه الوصول للإعدادات
    final userProvider = context.watch<CurrentUserProvider>();
    if (!userProvider.isOwner) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🔒', style: TextStyle(fontSize: 50)),
            SizedBox(height: 12),
            Text('غير مصرح لك',
                style: TextStyle(
                    color: AppColors.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('الإعدادات متاحة للمالك فقط',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Country Selector
        _sectionTitle('🌍 الدولة والعملة'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedCountryCode,
            dropdownColor: AppColors.darkCard,
            style: const TextStyle(
                color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 14),
            decoration: InputDecoration(
              labelText: 'اختر دولتك',
              labelStyle: const TextStyle(color: AppColors.textMuted),
              prefixIcon: Text(
                '  ${CountryConfig.getByCode(_selectedCountryCode).flag}  ',
                style: const TextStyle(fontSize: 22),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 0),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.darkBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              filled: true,
              fillColor: AppColors.dark,
            ),
            items: CountryConfig.countries
                .map((c) => DropdownMenuItem(
                      value: c.code,
                      child: Text('${c.flag}  ${c.name}  (${c.currency})'),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedCountryCode = v);
            },
          ),
        ),
        const SizedBox(height: 16),

        // Pharmacy Info
        _sectionTitle('🏥 بيانات الصيدلية'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            children: [
              AppTextField(hint: 'اسم الصيدلية', controller: _nameCtrl),
              const SizedBox(height: 10),
              AppTextField(hint: 'اسم الصيدلي', controller: _pharmacistCtrl),
              const SizedBox(height: 10),
              AppTextField(
                  hint: 'رقم الهاتف',
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              PrimaryButton(
                  text: 'حفظ البيانات',
                  onTap: _saveSettings,
                  icon: Icons.save_rounded),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Notifications
        _sectionTitle('🔔 الإشعارات'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: SwitchListTile(
            title: const Text('تفعيل الإشعارات',
                style: TextStyle(color: AppColors.textColor)),
            subtitle: const Text('تنبيهات النواقص والديون',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            value: _notificationsEnabled,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _notificationsEnabled = v),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 16),

        // PIN Lock
        _sectionTitle('🔐 قفل التطبيق'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: SwitchListTile(
            title: const Text('قفل برقم سري',
                style: TextStyle(color: AppColors.textColor)),
            subtitle: Text(
                _pinEnabled ? 'التطبيق محمي برقم سري' : 'اضغط لتفعيل القفل',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            value: _pinEnabled,
            activeThumbColor: AppColors.primary,
            onChanged: (v) {
              if (v) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PinLockScreen(
                      isSetup: true,
                      onSuccess: () {
                        Navigator.pop(context);
                        setState(() => _pinEnabled = true);
                        showSnack(context, '🔐 تم تفعيل القفل بنجاح!');
                      },
                    ),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PinLockScreen(
                      onSuccess: () async {
                        await PinLockScreen.removePin();
                        if (mounted) {
                          Navigator.pop(context);
                          setState(() => _pinEnabled = false);
                          showSnack(context, '🔓 تم إلغاء القفل');
                        }
                      },
                    ),
                  ),
                );
              }
            },
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 16),

        // Assistants Management
        _sectionTitle('👥 المساعدون'),
        _settingsTile(
          emoji: '👥',
          title: 'إدارة المساعدين',
          subtitle: 'أضف مساعدين وتحكم في صلاحياتهم',
          onTap: () => _openAssistants(),
          trailing: const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        _settingsTile(
          emoji: '🔄',
          title: 'مواعيد المزامنة',
          subtitle: 'مزامنة تلقائية في الخلفية بين الأجهزة',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SyncScheduleScreen())),
          trailing: const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),

        // Auto Close Settings
        _sectionTitle('⚙️ إغلاق النواقص'),
        Container(
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: SwitchListTile(
            title: const Text('إغلاق النواقص القديمة تلقائياً',
                style: TextStyle(color: AppColors.textColor)),
            subtitle: const Text('بعد 24 ساعة تنتقل لـ "مستعصي"',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            value: _autoCloseEnabled,
            onChanged: (v) async {
              setState(() => _autoCloseEnabled = v);
              await DatabaseHelper.instance
                  .setSetting('auto_close_enabled', v ? '1' : '0');
            },
            activeTrackColor: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),

        // Invoices
        _sectionTitle('🧾 الفواتير'),
        _settingsTile(
          emoji: '🧾',
          title: 'الفواتير',
          subtitle: 'إنشاء وعرض فواتير البيع',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const InvoiceScreen())),
          trailing: const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),

        // Subscription
        _sectionTitle('💳 الاشتراك'),
        _settingsTile(
          emoji: '🥈',
          title: 'باقة احترافي',
          subtitle: 'اشتراكك الحالي - اضغط للتجديد أو الترقية',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
          trailing: const Icon(Icons.chevron_left, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),

        // Dictionary Upload
        _sectionTitle('📚 قاموس الأدوية (مساعد الكتابة)'),
        _settingsTile(
          emoji: '📖',
          title: 'رفع قاموس الأدوية',
          subtitle: 'ملف Excel لتسهيل الإضافة في النواقص',
          onTap: _uploadDictionary,
          trailing: const Icon(Icons.upload_file, color: AppColors.primary),
        ),
        const SizedBox(height: 10),
        // Export & Delete Dictionary
        Row(
          children: [
            Expanded(
              child: _settingsTile(
                emoji: '📤',
                title: 'تصدير القاموس',
                subtitle: 'حفظ كملف Excel',
                onTap: _exportDictionary,
                trailing: const Icon(Icons.download, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _settingsTile(
                emoji: '🗑️',
                title: 'مسح القاموس',
                subtitle: 'حذف كل الأدوية',
                onTap: _deleteDictionary,
                trailing: const Icon(Icons.delete_outline, color: AppColors.danger),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),



        // Backup and Restore
        _sectionTitle('☁️ النسخ الاحتياطي'),
        Row(
          children: [
            Expanded(
              child: _settingsTile(
                emoji: '📤',
                title: 'نسخة احتياطية',
                subtitle: 'حفظ بياناتك',
                onTap: _backupDB,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _settingsTile(
                emoji: '📥',
                title: 'استعادة',
                subtitle: 'استرجاع البيانات',
                onTap: _restoreDB,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _settingsTile(
          emoji: '🧹',
          title: 'تحسين قاعدة البيانات',
          subtitle: 'ضغط وتنظيف البيانات لتقليل الحجم',
          onTap: _optimizeDB,
          trailing: const Icon(Icons.speed, color: AppColors.warning),
        ),
        const SizedBox(height: 16),

        // App Info
        _sectionTitle('ℹ️ عن التطبيق'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  _devTapCount++;
                  if (_devTapCount >= 5) {
                    _devTapCount = 0;
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DevPanelScreen()));
                  }
                },
                child: _infoRow('الإصدار', '1.0.0'),
              ),
              const Divider(color: AppColors.darkBorder),
              _infoRow('المطور', 'د. محمد السيد'),
              const Divider(color: AppColors.darkBorder),
              _infoRow('التواصل', 'Telegram: @Mohamed07Elsayed'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Developer Panel - debug only
        if (kDebugMode) ...[
          const SizedBox(height: 8),
          _settingsTile(
            emoji: '🛠️',
            title: 'لوحة المطور',
            subtitle: 'للمطور فقط - مقيدة بكلمة مرور',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DevPanelScreen())),
            trailing: const Icon(Icons.lock_rounded,
                color: AppColors.textMuted, size: 18),
          ),
        ],
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );

  Widget _settingsTile(
      {required String emoji,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
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
            trailing ?? const SizedBox(),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );



  Future<void> _openAssistants() async {
    final activated = await DatabaseHelper.instance.getSetting('assistants_activated');
    if (activated == '1') {
      if (mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AssistantsScreen()));
      }
      return;
    }

    // عرض شاشة التفعيل
    if (!mounted) return;
    final codeCtrl = TextEditingController();
    bool isValidating = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Text('👥', style: TextStyle(fontSize: 24)),
              SizedBox(width: 8),
              Expanded(
                child: Text('إدارة المساعدين',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Premium Badge
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A0A2E), Color(0xFF16213E)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                ),
                child: const Column(
                  children: [
                    Text('⭐', style: TextStyle(fontSize: 36)),
                    SizedBox(height: 8),
                    Text('ميزة مدفوعة',
                        style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    SizedBox(height: 4),
                    Text(
                        'أضف مساعدين للصيدلية وتحكم في صلاحياتهم مع سجل نشاط كامل',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        textAlign: TextAlign.center),
                    SizedBox(height: 8),
                    Text('💰 100 ج.م فقط - تفعيل دائم',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Code Entry
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                    color: AppColors.textColor,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  hintText: 'أدخل كود التفعيل',
                  hintStyle: TextStyle(color: AppColors.textMuted, letterSpacing: 1),
                  prefixIcon: Icon(Icons.vpn_key_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),

              // Activate Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isValidating
                      ? null
                      : () async {
                          final code = codeCtrl.text.trim().toUpperCase();
                          if (code.isEmpty) {
                            showSnack(ctx, 'أدخل كود التفعيل', isError: true);
                            return;
                          }
                          setDlg(() => isValidating = true);

                          // تحقق من الكود
                          bool valid = false;

                          // 1. Admin bypass (من GitHub Secrets فقط)
                          if (EnvConfig.adminCode1.isNotEmpty && code == EnvConfig.adminCode1 ||
                              EnvConfig.adminCode2.isNotEmpty && code == EnvConfig.adminCode2) {
                            valid = true;
                          }

                          // 2. Check local DB
                          if (!valid) {
                            try {
                              final db = await DatabaseHelper.instance.database;
                              final local = await db.query('subscription_codes',
                                  where: "code = ? AND is_active = 1 AND (plan = 'assistant' OR plan = 'premium_assistants')",
                                  whereArgs: [code]);
                              if (local.isNotEmpty) {
                                final maxUses = local.first['max_uses'] as int? ?? 1;
                                final usedCount = local.first['used_count'] as int? ?? 0;
                                if (usedCount < maxUses) {
                                  valid = true;
                                  await db.update('subscription_codes',
                                      {'used_count': usedCount + 1},
                                      where: 'code = ?', whereArgs: [code]);
                                  await SupabaseService.instance
                                      .updateSubscriptionCodeUsage(code, usedCount + 1);
                                }
                              }
                            } catch (_) {}
                          }

                          // 3. Check Supabase
                          if (!valid) {
                            try {
                              final cloudData = await SupabaseService.instance
                                  .checkSubscriptionCode(code);
                              if (cloudData != null &&
                                  (cloudData['plan'] == 'assistant' ||
                                      cloudData['plan'] == 'premium' ||
                                      cloudData['plan'] == 'premium_assistants') &&
                                  (cloudData['is_active'] == true ||
                                      cloudData['is_active'] == 1)) {
                                final maxUses = cloudData['max_uses'] ?? 1;
                                final usedCount = cloudData['used_count'] ?? 0;
                                if (usedCount < maxUses) {
                                  valid = true;
                                  await SupabaseService.instance
                                      .updateSubscriptionCodeUsage(
                                          code, usedCount + 1);
                                }
                              }
                            } catch (_) {}
                          }

                          setDlg(() => isValidating = false);

                          if (valid) {
                            await DatabaseHelper.instance
                                .setSetting('assistants_activated', '1');
                            await DatabaseHelper.instance.addAssistantSlots(3);
                            // تفعيل الاشتراك أيضاً إذا كان الكود premium_assistants
                            final expiry = DateTime.now().add(const Duration(days: 30)).toIso8601String();
                            await SecurityHelper.saveSignedSetting('subscription_expiry', expiry);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              showSnack(context, '✅ تم تفعيل إدارة المساعدين بنجاح!');
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const AssistantsScreen()));
                            }
                          } else {
                            if (ctx.mounted) {
                              showSnack(ctx, '❌ كود غير صحيح أو منتهي', isError: true);
                            }
                          }
                        },
                  icon: isValidating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle, size: 18),
                  label: Text(isValidating ? 'جاري التحقق...' : 'تفعيل'),
                ),
              ),
            ],
          ),
          actions: [
            // Contact Developer
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openLink('https://t.me/Mohamed07Elsayed');
              },
              icon: const Text('✈️', style: TextStyle(fontSize: 16)),
              label: const Text('تواصل مع المطور للحصول على كود',
                  style: TextStyle(color: Color(0xFF229ED9), fontSize: 12)),
            ),
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
    } catch (_) {}
  }

  Future<void> _uploadDictionary() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
    if (result == null || result.files.single.path == null) return;

    if (!mounted) return;
    showSnack(context, 'جاري قراءة الملف...');

    try {
      final bytes = File(result.files.single.path!).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return;

      final table = excel.tables.keys.first;
      final sheet = excel.tables[table]!;
      if (sheet.maxRows == 0) return;

      final firstRow = sheet.row(0);
      final headers = <String>[];
      for (int i = 0; i < firstRow.length; i++) {
        headers.add(firstRow[i]?.value?.toString().trim() ?? 'عمود ${i + 1}');
      }

      if (!mounted) return;
      final mapping = await showDialog<Map<String, int>>(
        context: context,
        builder: (ctx) => ColumnMappingDialog(headers: headers),
      );

      if (mapping == null) return;

      List<Map<String, String>> dict = [];

      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.row(i);
        if (row.isEmpty) continue;

        String getCol(String key) {
          final idx = mapping[key];
          if (idx == null || idx < 0 || idx >= row.length) return '';
          return row[idx]?.value?.toString().trim() ?? '';
        }

        final enName = getCol('enName');
        if (enName.isEmpty) continue;

        dict.add({
          'enName': enName,
          'arName': getCol('arName'),
          'activeIngredient': getCol('activeIngredient'),
          'barcode': getCol('barcode'),
          'price': getCol('price'),
          'cost_price': getCol('cost_price'),
        });
      }

      await DatabaseHelper.instance
          .setSetting('drug_dictionary_v2', jsonEncode(dict));
      if (mounted) showSnack(context, 'تم إضافة ${dict.length} صنف للقاموس ✅');
    } catch (e) {
      if (mounted) showSnack(context, 'خطأ في قراءة الملف', isError: true);
    }
  }

  Future<void> _exportDictionary() async {
    final docs = await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (docs == null) {
      if (mounted) showSnack(context, 'القاموس فارغ', isError: true);
      return;
    }
    
    try {
      final List<dynamic> decoded = jsonDecode(docs);
      if (decoded.isEmpty) {
        if (mounted) showSnack(context, 'القاموس فارغ', isError: true);
        return;
      }
      
      var excel = Excel.createExcel();
      var sheet = excel['Sheet1'];
      
      sheet.appendRow([
        TextCellValue('English Name'),
        TextCellValue('Arabic Name'),
        TextCellValue('Active Ingredient'),
        TextCellValue('Barcode'),
        TextCellValue('Price'),
        TextCellValue('Cost Price')
      ]);
      
      for (var item in decoded) {
        sheet.appendRow([
          TextCellValue(item['enName']?.toString() ?? ''),
          TextCellValue(item['arName']?.toString() ?? ''),
          TextCellValue(item['activeIngredient']?.toString() ?? ''),
          TextCellValue(item['barcode']?.toString() ?? ''),
          TextCellValue(item['price']?.toString() ?? ''),
          TextCellValue(item['cost_price']?.toString() ?? '')
        ]);
      }
      
      final bytes = excel.encode();
      if (bytes != null) {
        final dir = await getTemporaryDirectory();
        final path = p.join(dir.path, 'drug_dictionary.xlsx');
        final file = File(path);
        await file.writeAsBytes(bytes);
        
        await Share.shareXFiles([XFile(path)], subject: 'قاموس الأدوية');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'خطأ في التصدير: $e', isError: true);
    }
  }

  Future<void> _deleteDictionary() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('مسح القاموس', style: TextStyle(color: AppColors.danger)),
        content: const Text('هل أنت متأكد من مسح جميع الأدوية؟\n⚠️ لا يمكن التراجع.', style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.setSetting('drug_dictionary_v2', '[]');
      if (mounted) showSnack(context, 'تم مسح القاموس بنجاح ✅');
    }
  }

  Future<void> _optimizeDB() async {
    try {
      final sizeBefore = await DatabaseHelper.instance.getDatabaseSizeKB();
      if (mounted) showSnack(context, 'جاري تحسين قاعدة البيانات...');
      await DatabaseHelper.instance.vacuumDatabase();
      final sizeAfter = await DatabaseHelper.instance.getDatabaseSizeKB();
      if (mounted) {
        final saved = sizeBefore - sizeAfter;
        showSnack(context,
            '✅ تم التحسين! الحجم: ${sizeAfter.toStringAsFixed(0)} KB${saved > 0 ? ' (وفّرت ${saved.toStringAsFixed(0)} KB)' : ''}');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'خطأ في التحسين: $e', isError: true);
    }
  }

  Future<void> _backupDB() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'saydali_pro.db');
      if (await File(path).exists()) {
        await Share.shareXFiles([XFile(path)],
            subject: 'نسخة احتياطية - صيدلي PRO');
      } else {
        if (mounted) showSnack(context, 'لا توجد قاعدة بيانات!', isError: true);
      }
    } catch (e) {
      if (mounted)
        showSnack(context, 'حدث خطأ أثناء النسخ الاحتياطي', isError: true);
    }
  }

  Future<void> _restoreDB() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType
            .any, // Android sometimes fails on custom db/sqlite extensions
      );
      if (result != null && result.files.single.path != null) {
        final backupPath = result.files.single.path!;
        if (!backupPath.endsWith('.db') && !backupPath.endsWith('.sqlite')) {
          if (mounted)
            showSnack(context, 'الرجاء اختيار ملف قاعدة بيانات صالح (.db)',
                isError: true);
          return;
        }
        final dbPath = await getDatabasesPath();
        final path = p.join(dbPath, 'saydali_pro.db');
        await File(backupPath).copy(path);

        if (mounted) {
          showSnack(context,
              'تم استعادة النسخة الاحتياطية بنجاح ✅ - يرجى إعادة تشغيل التطبيق لتحديث البيانات');
          // Reload settings after restore
          _loadSettings();
        }
      }
    } catch (e) {
      if (mounted) showSnack(context, 'حدث خطأ أثناء الاستعادة', isError: true);
    }
  }
}

class ColumnMappingDialog extends StatefulWidget {
  final List<String> headers;
  const ColumnMappingDialog({super.key, required this.headers});

  @override
  State<ColumnMappingDialog> createState() => _ColumnMappingDialogState();
}

class _ColumnMappingDialogState extends State<ColumnMappingDialog> {
  final Map<String, int> mapping = {
    'enName': -1,
    'arName': -1,
    'activeIngredient': -1,
    'barcode': -1,
    'price': -1,
    'cost_price': -1,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.darkCard,
      title: const Text('ربط الأعمدة', style: TextStyle(color: AppColors.primary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDropdown('الاسم الإنجليزي (مطلوب)', 'enName'),
            _buildDropdown('الاسم العربي', 'arName'),
            _buildDropdown('المادة الفعالة', 'activeIngredient'),
            _buildDropdown('الباركود', 'barcode'),
            _buildDropdown('السعر (سعر البيع)', 'price'),
            _buildDropdown('سعر الشراء (التكلفة)', 'cost_price'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () {
            if (mapping['enName'] == -1) {
              showSnack(context, 'يجب اختيار عمود الاسم الإنجليزي', isError: true);
              return;
            }
            Navigator.pop(context, mapping);
          },
          child: const Text('تأكيد'),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textColor, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: DropdownButton<int>(
              isExpanded: true,
              dropdownColor: AppColors.dark,
              underline: const SizedBox(),
              value: mapping[key],
              items: [
                const DropdownMenuItem(value: -1, child: Text('تجاهل', style: TextStyle(color: AppColors.textMuted))),
                ...widget.headers.asMap().entries.map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, style: const TextStyle(color: AppColors.textColor)),
                )),
              ],
              onChanged: (v) {
                if (v != null) setState(() => mapping[key] = v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
