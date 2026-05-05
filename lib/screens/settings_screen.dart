import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../widgets/common_widgets.dart';
import 'subscription_screen.dart';
import 'dev_panel_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

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
  bool _loading = true;
  int _devTapCount = 0;

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
        _notificationsEnabled =
            (settings['notifications_enabled'] ?? '1') == '1';
        _loading = false;
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
        .setSetting('notifications_enabled', _notificationsEnabled ? '1' : '0');
    if (mounted) showSnack(context, 'تم حفظ الإعدادات ✅');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        });
      }

      await DatabaseHelper.instance
          .setSetting('drug_dictionary_v2', jsonEncode(dict));
      if (mounted) showSnack(context, 'تم إضافة ${dict.length} صنف للقاموس ✅');
    } catch (e) {
      if (mounted) showSnack(context, 'خطأ في قراءة الملف', isError: true);
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
