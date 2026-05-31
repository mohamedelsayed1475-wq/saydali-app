import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/env_config.dart';
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

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
  final _pharmacistCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _notificationsEnabled = true;
  bool _pinEnabled = false;
  bool _loading = true;
  int _devTapCount = 0;
  String _selectedCountryCode = 'EG';
  bool _autoCloseEnabled = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _loadSettings();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose();
    _pharmacistCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
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
      _animCtrl.forward();
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
    final userProvider = context.watch<CurrentUserProvider>();
    if (!userProvider.isOwner) {
      return _buildAccessDenied();
    }
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ─── Header ───────────────────────────────────────────
          _buildHeader(),
          const SizedBox(height: 24),

          // ─── Country & Currency ───────────────────────────────
          _sectionLabel('🌍 الدولة والعملة'),
          _buildCountryCard(),
          const SizedBox(height: 20),

          // ─── Pharmacy Info ────────────────────────────────────
          _sectionLabel('🏥 بيانات الصيدلية'),
          _buildPharmacyInfoCard(),
          const SizedBox(height: 20),

          // ─── Notifications & PIN ──────────────────────────────
          _sectionLabel('🔔 الإشعارات والحماية'),
          _buildToggleGroup([
            _ToggleItem(
              icon: Icons.notifications_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'الإشعارات',
              subtitle: 'تنبيهات النواقص والديون',
              value: _notificationsEnabled,
              onChanged: (v) => setState(() => _notificationsEnabled = v),
            ),
            _ToggleItem(
              icon: Icons.lock_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'قفل برقم سري',
              subtitle: _pinEnabled ? 'التطبيق محمي برقم سري' : 'اضغط لتفعيل القفل',
              value: _pinEnabled,
              onChanged: _handlePinToggle,
            ),
          ]),
          const SizedBox(height: 20),

          // ─── Auto Close ───────────────────────────────────────
          _sectionLabel('⚙️ إغلاق النواقص تلقائياً'),
          _buildToggleGroup([
            _ToggleItem(
              icon: Icons.timer_rounded,
              iconColor: const Color(0xFF06B6D4),
              title: 'الإغلاق التلقائي',
              subtitle: 'بعد 24 ساعة تنتقل لـ "مستعصي"',
              value: _autoCloseEnabled,
              onChanged: (v) async {
                setState(() => _autoCloseEnabled = v);
                await DatabaseHelper.instance
                    .setSetting('auto_close_enabled', v ? '1' : '0');
              },
            ),
          ]),
          const SizedBox(height: 20),

          // ─── Assistants & Sync ────────────────────────────────
          _sectionLabel('👥 المساعدون والمزامنة'),
          _buildNavTilesGroup([
            _NavTile(
              icon: Icons.people_alt_rounded,
              iconBg: const Color(0xFF10B981),
              title: 'إدارة المساعدين',
              subtitle: 'أضف مساعدين وتحكم في صلاحياتهم',
              onTap: _openAssistants,
            ),
            _NavTile(
              icon: Icons.sync_rounded,
              iconBg: const Color(0xFF3B82F6),
              title: 'مواعيد المزامنة',
              subtitle: 'مزامنة تلقائية في الخلفية بين الأجهزة',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SyncScheduleScreen())),
            ),
          ]),
          const SizedBox(height: 20),

          // ─── Subscription ─────────────────────────────────────
          _buildSubscriptionCard(),
          const SizedBox(height: 20),

          // ─── Dictionary ───────────────────────────────────────
          _sectionLabel('📚 قاموس الأدوية'),
          _buildNavTilesGroup([
            _NavTile(
              icon: Icons.upload_file_rounded,
              iconBg: const Color(0xFF6366F1),
              title: 'رفع قاموس الأدوية',
              subtitle: 'ملف Excel لتسهيل الإضافة في النواقص',
              onTap: _uploadDictionary,
            ),
            _NavTile(
              icon: Icons.download_rounded,
              iconBg: const Color(0xFF0EA5E9),
              title: 'تصدير القاموس',
              subtitle: 'حفظ كملف Excel',
              onTap: _exportDictionary,
            ),
            _NavTile(
              icon: Icons.delete_sweep_rounded,
              iconBg: const Color(0xFFEF4444),
              title: 'مسح القاموس',
              subtitle: 'حذف جميع الأدوية من القاموس',
              onTap: _deleteDictionary,
              isDanger: true,
            ),
          ]),
          const SizedBox(height: 20),

          // ─── Backup & Restore ─────────────────────────────────
          _sectionLabel('☁️ النسخ الاحتياطي وقاعدة البيانات'),
          _buildNavTilesGroup([
            _NavTile(
              icon: Icons.backup_rounded,
              iconBg: const Color(0xFF059669),
              title: 'نسخة احتياطية',
              subtitle: 'تصدير وحفظ بياناتك',
              onTap: _backupDB,
            ),
            _NavTile(
              icon: Icons.restore_rounded,
              iconBg: const Color(0xFF7C3AED),
              title: 'استعادة النسخة',
              subtitle: 'استرجاع بيانات من ملف سابق',
              onTap: _restoreDB,
            ),
            _NavTile(
              icon: Icons.speed_rounded,
              iconBg: const Color(0xFFF59E0B),
              title: 'تحسين قاعدة البيانات',
              subtitle: 'ضغط وتنظيف البيانات لتقليل الحجم',
              onTap: _optimizeDB,
            ),
          ]),
          const SizedBox(height: 20),

          // ─── About ────────────────────────────────────────────
          _sectionLabel('ℹ️ عن التطبيق'),
          _buildAboutCard(),
          const SizedBox(height: 20),

          // ─── Dev Panel (debug only) ───────────────────────────
          if (kDebugMode) ...[
            _buildNavTilesGroup([
              _NavTile(
                icon: Icons.developer_mode_rounded,
                iconBg: const Color(0xFF6B7280),
                title: 'لوحة المطور',
                subtitle: 'للمطور فقط - مقيدة بكلمة مرور',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DevPanelScreen())),
              ),
            ]),
            const SizedBox(height: 20),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─────────────── Widgets ───────────────────────────────────────────────────

  Widget _buildAccessDenied() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                AppColors.danger.withValues(alpha: 0.2),
                AppColors.danger.withValues(alpha: 0.04),
              ]),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🔒', style: TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('غير مصرح لك',
              style: TextStyle(
                  color: AppColors.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('الإعدادات متاحة للمالك فقط',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.primary.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.settings_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الإعدادات',
                    style: TextStyle(
                        color: AppColors.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                Text('تخصيص الصيدلية والحساب',
                    style: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.8),
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10, right: 4),
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _buildCountryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(Icons.public_rounded, const Color(0xFF10B981)),
              const SizedBox(width: 12),
              const Text('اختر دولتك',
                  style: TextStyle(
                      color: AppColors.textColor, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                dropdownColor: AppColors.darkCard,
                value: _selectedCountryCode,
                style: const TextStyle(
                    color: AppColors.textColor,
                    fontFamily: 'Cairo',
                    fontSize: 14),
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
          ),
        ],
      ),
    );
  }

  Widget _buildPharmacyInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _inputRow(
              icon: Icons.local_pharmacy_rounded,
              iconColor: AppColors.primary,
              hint: 'اسم الصيدلية',
              ctrl: _nameCtrl),
          const SizedBox(height: 12),
          _inputRow(
              icon: Icons.person_rounded,
              iconColor: const Color(0xFF8B5CF6),
              hint: 'اسم الصيدلي',
              ctrl: _pharmacistCtrl),
          const SizedBox(height: 12),
          _inputRow(
              icon: Icons.phone_rounded,
              iconColor: const Color(0xFF0EA5E9),
              hint: 'رقم الهاتف',
              ctrl: _phoneCtrl,
              keyboard: TextInputType.phone),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('حفظ البيانات',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputRow({
    required IconData icon,
    required Color iconColor,
    required String hint,
    required TextEditingController ctrl,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: ctrl,
            keyboardType: keyboard,
            style: const TextStyle(
                color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(color: AppColors.textMuted, fontSize: 13),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: AppColors.dark,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.darkBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.darkBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleGroup(List<_ToggleItem> items) {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: items.asMap().entries.map((e) {
          final item = e.value;
          final isLast = e.key == items.length - 1;
          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _iconBox(item.icon, item.iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                              style: const TextStyle(
                                  color: AppColors.textColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                          Text(item.subtitle,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: item.value,
                        onChanged: item.onChanged,
                        activeThumbColor: item.iconColor,
                        activeTrackColor:
                            item.iconColor.withValues(alpha: 0.25),
                        inactiveThumbColor: AppColors.textMuted,
                        inactiveTrackColor:
                            AppColors.textMuted.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(
                    color: AppColors.darkBorder, height: 1, indent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNavTilesGroup(List<_NavTile> tiles) {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: tiles.asMap().entries.map((e) {
          final tile = e.value;
          final isLast = e.key == tiles.length - 1;
          return Column(
            children: [
              InkWell(
                onTap: tile.onTap,
                borderRadius: BorderRadius.vertical(
                  top: e.key == 0
                      ? const Radius.circular(16)
                      : Radius.zero,
                  bottom: isLast
                      ? const Radius.circular(16)
                      : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tile.iconBg.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: tile.iconBg.withValues(alpha: 0.3)),
                        ),
                        child: Icon(tile.icon,
                            color: tile.isDanger
                                ? AppColors.danger
                                : tile.iconBg,
                            size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tile.title,
                                style: TextStyle(
                                    color: tile.isDanger
                                        ? AppColors.danger
                                        : AppColors.textColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            Text(tile.subtitle,
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_left_rounded,
                        color: AppColors.textMuted.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                const Divider(
                    color: AppColors.darkBorder, height: 1, indent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    return InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1040), Color(0xFF0F1E35)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.08),
                blurRadius: 16)
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
              ),
              child: const Center(
                  child:
                      Text('🥈', style: TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('باقة احترافي',
                      style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  SizedBox(height: 2),
                  Text('اشتراكك الحالي — اضغط للتجديد أو الترقية',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded,
                color: Color(0xFFFFD700), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              _devTapCount++;
              if (_devTapCount >= 5) {
                _devTapCount = 0;
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DevPanelScreen()));
              }
            },
            child: _aboutRow(
                icon: Icons.tag_rounded,
                iconColor: AppColors.primary,
                label: 'الإصدار',
                value: '1.0.0'),
          ),
          const Divider(color: AppColors.darkBorder, height: 1, indent: 16),
          _aboutRow(
              icon: Icons.person_pin_rounded,
              iconColor: const Color(0xFF8B5CF6),
              label: 'المطور',
              value: 'د. محمد السيد'),
          const Divider(color: AppColors.darkBorder, height: 1, indent: 16),
          InkWell(
            onTap: () => _openLink('https://t.me/Mohamed07Elsayed'),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: _aboutRow(
                icon: Icons.telegram_rounded,
                iconColor: const Color(0xFF229ED9),
                label: 'Telegram',
                value: '@Mohamed07Elsayed',
                valueColor: const Color(0xFF229ED9)),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _iconBox(icon, iconColor, size: 36),
          const SizedBox(width: 12),
          Text(label,
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? AppColors.textLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color, {double size = 38}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 12,
          ),
        ],
      );

  // ─────────────── Logic ────────────────────────────────────────────────────

  void _handlePinToggle(bool v) {
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
  }

  Future<void> _openAssistants() async {
    final activated =
        await DatabaseHelper.instance.getSetting('assistants_activated');
    if (activated == '1') {
      if (mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AssistantsScreen()));
      }
      return;
    }

    if (!mounted) return;
    final codeCtrl = TextEditingController();
    bool isValidating = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.darkCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12),
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
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                    color: AppColors.textColor,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  hintText: 'أدخل كود التفعيل',
                  hintStyle: TextStyle(
                      color: AppColors.textMuted, letterSpacing: 1),
                  prefixIcon:
                      Icon(Icons.vpn_key_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isValidating
                      ? null
                      : () async {
                          final code =
                              codeCtrl.text.trim().toUpperCase();
                          if (code.isEmpty) {
                            showSnack(ctx, 'أدخل كود التفعيل',
                                isError: true);
                            return;
                          }
                          setDlg(() => isValidating = true);

                          bool valid = false;

                          if (EnvConfig.adminCode1.isNotEmpty &&
                                  code == EnvConfig.adminCode1 ||
                              EnvConfig.adminCode2.isNotEmpty &&
                                  code == EnvConfig.adminCode2) {
                            valid = true;
                          }

                          if (!valid) {
                            try {
                              final db = await DatabaseHelper
                                  .instance.database;
                              final local = await db.query(
                                  'subscription_codes',
                                  where:
                                      "code = ? AND is_active = 1 AND (plan = 'assistant' OR plan = 'premium_assistants')",
                                  whereArgs: [code]);
                              if (local.isNotEmpty) {
                                final maxUses =
                                    local.first['max_uses'] as int? ?? 1;
                                final usedCount =
                                    local.first['used_count'] as int? ?? 0;
                                if (usedCount < maxUses) {
                                  valid = true;
                                  await db.update(
                                      'subscription_codes',
                                      {'used_count': usedCount + 1},
                                      where: 'code = ?',
                                      whereArgs: [code]);
                                  await SupabaseService.instance
                                      .updateSubscriptionCodeUsage(
                                          code, usedCount + 1);
                                }
                              }
                            } catch (_) {}
                          }

                          if (!valid) {
                            try {
                              final cloudData = await SupabaseService
                                  .instance
                                  .checkSubscriptionCode(code);
                              if (cloudData != null &&
                                  (cloudData['plan'] == 'assistant' ||
                                      cloudData['plan'] == 'premium' ||
                                      cloudData['plan'] ==
                                          'premium_assistants') &&
                                  (cloudData['is_active'] == true ||
                                      cloudData['is_active'] == 1)) {
                                final maxUses = cloudData['max_uses'] ?? 1;
                                final usedCount =
                                    cloudData['used_count'] ?? 0;
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
                            await DatabaseHelper.instance
                                .addAssistantSlots(3);
                            final expiry = DateTime.now()
                                .add(const Duration(days: 30))
                                .toIso8601String();
                            await SecurityHelper.saveSignedSetting(
                                'subscription_expiry', expiry);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              showSnack(context,
                                  '✅ تم تفعيل إدارة المساعدين بنجاح!');
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const AssistantsScreen()));
                            }
                          } else {
                            if (ctx.mounted) {
                              showSnack(ctx, '❌ كود غير صحيح أو منتهي',
                                  isError: true);
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
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openLink('https://t.me/Mohamed07Elsayed');
              },
              icon: const Text('✈️', style: TextStyle(fontSize: 16)),
              label: const Text('تواصل مع المطور للحصول على كود',
                  style:
                      TextStyle(color: Color(0xFF229ED9), fontSize: 12)),
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
      if (mounted)
        showSnack(context, 'تم إضافة ${dict.length} صنف للقاموس ✅');
    } catch (e) {
      if (mounted) showSnack(context, 'خطأ في قراءة الملف', isError: true);
    }
  }

  Future<void> _exportDictionary() async {
    final docs =
        await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
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
        title: const Text('مسح القاموس',
            style: TextStyle(color: AppColors.danger)),
        content: const Text(
            'هل أنت متأكد من مسح جميع الأدوية؟\n⚠️ لا يمكن التراجع.',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
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
      if (mounted)
        showSnack(context, 'خطأ في التحسين: $e', isError: true);
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
        if (mounted)
          showSnack(context, 'لا توجد قاعدة بيانات!', isError: true);
      }
    } catch (e) {
      if (mounted)
        showSnack(context, 'حدث خطأ أثناء النسخ الاحتياطي', isError: true);
    }
  }

  Future<void> _restoreDB() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result != null && result.files.single.path != null) {
        final backupPath = result.files.single.path!;
        if (!backupPath.endsWith('.db') &&
            !backupPath.endsWith('.sqlite')) {
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
          _loadSettings();
        }
      }
    } catch (e) {
      if (mounted)
        showSnack(context, 'حدث خطأ أثناء الاستعادة', isError: true);
    }
  }
}

// ─── Helper Models ────────────────────────────────────────────────────────────

class _ToggleItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
}

class _NavTile {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDanger;

  const _NavTile({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDanger = false,
  });
}

// ─── Column Mapping Dialog ────────────────────────────────────────────────────

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
      title: const Text('ربط الأعمدة',
          style: TextStyle(color: AppColors.primary)),
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        ElevatedButton(
          style:
              ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () {
            if (mapping['enName'] == -1) {
              showSnack(context, 'يجب اختيار عمود الاسم الإنجليزي',
                  isError: true);
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
          Text(label,
              style: const TextStyle(
                  color: AppColors.textColor, fontSize: 12)),
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
                const DropdownMenuItem(
                    value: -1,
                    child: Text('تجاهل',
                        style: TextStyle(color: AppColors.textMuted))),
                ...widget.headers.asMap().entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          style:
                              const TextStyle(color: AppColors.textColor)),
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
