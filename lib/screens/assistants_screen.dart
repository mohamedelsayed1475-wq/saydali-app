import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../utils/env_config.dart';
import '../widgets/common_widgets.dart';
import 'subscription_screen.dart';
import '../services/sync_service.dart';
import '../services/supabase_service.dart';
import '../utils/security_helper.dart';

class AssistantsScreen extends StatefulWidget {
  const AssistantsScreen({super.key});

  @override
  State<AssistantsScreen> createState() => _AssistantsScreenState();
}

class _AssistantsScreenState extends State<AssistantsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Assistant> _assistants = [];
  List<ActivityLogEntry> _logs = [];
  bool _loading = true;
  String _pharmacyCode = '';
  int _maxSlots = 0;
  int _currentCount = 0;
  int _extraSlots = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final assistantsData = await DatabaseHelper.instance.getAssistants();
    final logsData = await DatabaseHelper.instance.getActivityLog(limit: 100);
    final slots = await DatabaseHelper.instance.getAssistantSlots();
    final count = await DatabaseHelper.instance.getActiveAssistantCount();
    // تحميل أو إنشاء كود الصيدلية
    var code = await DatabaseHelper.instance.getSetting('pharmacy_code');
    if (code == null || code.isEmpty) {
      code = _generatePharmacyCode();
      await DatabaseHelper.instance.setSetting('pharmacy_code', code);
    }
    final extras = await DatabaseHelper.instance.getExtraAssistantSlots();
    if (mounted) {
      setState(() {
        _assistants = assistantsData.map(Assistant.fromMap).toList();
        _logs = logsData.map(ActivityLogEntry.fromMap).toList();
        _pharmacyCode = code!;
        _maxSlots = slots;
        _currentCount = count;
        _extraSlots = extras;
        _loading = false;
      });
    }
    // رفع كود الصيدلية للسحابة تلقائياً عند فتح الشاشة
    SyncService.instance.registerPharmacy();
  }

  Future<void> _showAddAssistant({Assistant? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final pinCtrl = TextEditingController(text: existing?.pin);
    bool canAddDebt = existing?.canAddDebt ?? true;
    bool canEditDebt = existing?.canEditDebt ?? false;
    bool canDelete = existing?.canDelete ?? false;
    bool canViewReports = existing?.canViewReports ?? false;
    bool canManageInvoices = existing?.canManageInvoices ?? true;
    bool canManageShortages = existing?.canManageShortages ?? true;
    bool canManageReps = existing?.canManageReps ?? false;
    bool isActive = existing?.isActive ?? true;

    final expiryStr = await SecurityHelper.readSignedSetting('subscription_expiry');
    final pharmacyExpiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
    final limitDate = (pharmacyExpiry != null && pharmacyExpiry.isAfter(DateTime.now()))
        ? pharmacyExpiry
        : DateTime.now().add(const Duration(days: 3650));
    final pharmacyRemainingDays = limitDate.difference(DateTime.now()).inDays;

    int subscriptionDurationDays = existing?.subscriptionDurationDays ?? 30;
    DateTime subscriptionExpiry = existing?.subscriptionExpiry ??
        DateTime.now().add(Duration(days: subscriptionDurationDays));

    if (subscriptionExpiry.isAfter(limitDate)) {
      subscriptionExpiry = limitDate;
      subscriptionDurationDays = limitDate.difference(DateTime.now()).inDays;
      if (subscriptionDurationDays < 0) {
        subscriptionDurationDays = 0;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                Text(
                    existing == null
                        ? '👤 إضافة مساعد جديد'
                        : '✏️ تعديل المساعد',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 16),
                AppTextField(hint: 'اسم المساعد *', controller: nameCtrl),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'رقم الهاتف',
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 10),
                AppTextField(
                  hint: 'رمز PIN (4 أرقام) *',
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                ),
                const SizedBox(height: 16),

                // ── الاشتراك والصلاحية ──
                const Text('📅 صلاحية الاشتراك والنشاط',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('تاريخ انتهاء الصلاحية:',
                              style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                          Text(
                            _formatDate(subscriptionExpiry),
                            style: TextStyle(
                              color: subscriptionExpiry.isBefore(DateTime.now())
                                  ? AppColors.danger
                                  : AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _durationBtn(30, '٣٠ يوم', subscriptionDurationDays, pharmacyRemainingDays >= 30, (val) {
                            setBS(() {
                              subscriptionDurationDays = val;
                              subscriptionExpiry = DateTime.now().add(Duration(days: val));
                            });
                          }),
                          _durationBtn(90, '٩٠ يوم', subscriptionDurationDays, pharmacyRemainingDays >= 90, (val) {
                            setBS(() {
                              subscriptionDurationDays = val;
                              subscriptionExpiry = DateTime.now().add(Duration(days: val));
                            });
                          }),
                          _durationBtn(365, 'سنة', subscriptionDurationDays, pharmacyRemainingDays >= 365, (val) {
                            setBS(() {
                              subscriptionDurationDays = val;
                              subscriptionExpiry = DateTime.now().add(Duration(days: val));
                            });
                          }),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: subscriptionExpiry.isBefore(DateTime.now().subtract(const Duration(days: 365)))
                                        ? DateTime.now()
                                        : (subscriptionExpiry.isAfter(limitDate) ? limitDate : subscriptionExpiry),
                                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                    lastDate: limitDate,
                                    builder: (context, child) {
                                      return Theme(
                                        data: Theme.of(context).copyWith(
                                          colorScheme: const ColorScheme.dark(
                                            primary: AppColors.primary,
                                            onPrimary: Colors.white,
                                            surface: AppColors.darkCard,
                                            onSurface: AppColors.textColor,
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    setBS(() {
                                      subscriptionExpiry = picked;
                                      subscriptionDurationDays = picked.difference(DateTime.now()).inDays;
                                      if (subscriptionDurationDays < 0) {
                                        subscriptionDurationDays = 0;
                                      }
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: (subscriptionDurationDays != 30 &&
                                            subscriptionDurationDays != 90 &&
                                            subscriptionDurationDays != 365)
                                        ? AppColors.primary.withValues(alpha: 0.15)
                                        : AppColors.darkCard,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: (subscriptionDurationDays != 30 &&
                                              subscriptionDurationDays != 90 &&
                                              subscriptionDurationDays != 365)
                                          ? AppColors.primary
                                          : AppColors.darkBorder,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'تاريخ مخصص',
                                      style: TextStyle(
                                          color: AppColors.textColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (existing != null && subscriptionExpiry.isBefore(DateTime.now())) ...[
                        const SizedBox(height: 12),
                        const Divider(color: AppColors.darkBorder),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setBS(() {
                                var targetExpiry = DateTime.now().add(Duration(days: subscriptionDurationDays));
                                if (targetExpiry.isAfter(limitDate)) {
                                  targetExpiry = limitDate;
                                  subscriptionDurationDays = limitDate.difference(DateTime.now()).inDays;
                                  if (subscriptionDurationDays < 0) subscriptionDurationDays = 0;
                                  showSnack(ctx, '⚠️ تم التمديد للحد الأقصى المتاح (انتهاء اشتراك الصيدلية)');
                                } else {
                                  showSnack(ctx, 'تم تمديد صلاحية المساعد 📅');
                                }
                                subscriptionExpiry = targetExpiry;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.autorenew_rounded, color: Colors.white, size: 18),
                            label: const Text(
                              'تجديد الاشتراك والتفعيل',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── الصلاحيات ──
                const Text('🔐 الصلاحيات',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _permissionTile(
                  icon: Icons.add_circle,
                  title: 'إضافة ديون',
                  value: canAddDebt,
                  onChanged: (v) => setBS(() => canAddDebt = v),
                ),
                _permissionTile(
                  icon: Icons.edit,
                  title: 'تعديل ديون',
                  value: canEditDebt,
                  onChanged: (v) => setBS(() => canEditDebt = v),
                ),
                _permissionTile(
                  icon: Icons.delete,
                  title: 'حذف بيانات',
                  value: canDelete,
                  onChanged: (v) => setBS(() => canDelete = v),
                  isDanger: true,
                ),
                _permissionTile(
                  icon: Icons.bar_chart,
                  title: 'عرض التقارير',
                  value: canViewReports,
                  onChanged: (v) => setBS(() => canViewReports = v),
                ),
                _permissionTile(
                  icon: Icons.receipt_long,
                  title: 'إدارة الفواتير',
                  value: canManageInvoices,
                  onChanged: (v) => setBS(() => canManageInvoices = v),
                ),
                _permissionTile(
                  icon: Icons.medication_rounded,
                  title: 'إدارة النواقص',
                  value: canManageShortages,
                  onChanged: (v) => setBS(() => canManageShortages = v),
                ),
                _permissionTile(
                  icon: Icons.people_rounded,
                  title: 'إدارة المندوبين',
                  value: canManageReps,
                  onChanged: (v) => setBS(() => canManageReps = v),
                ),
                if (existing != null) ...[
                  const SizedBox(height: 10),
                  const Divider(color: AppColors.darkBorder),
                  _permissionTile(
                    icon: isActive ? Icons.check_circle_rounded : Icons.block_rounded,
                    title: 'حساب نشط (يمكنه تسجيل الدخول)',
                    value: isActive,
                    onChanged: (v) {
                      if (v) {
                        bool isReactivated = !existing.isActive;
                        if (isReactivated && _currentCount >= _maxSlots) {
                          showSnack(ctx, '⚠️ لقد تجاوزت الحد الأقصى للمساعدين النشطين ($_maxSlots). يرجى ترقية الاشتراك أو تعطيل مساعد آخر أولاً.', isError: true);
                          return;
                        }
                      }
                      setBS(() => isActive = v);
                    },
                    isDanger: !isActive,
                  ),
                ],
                const SizedBox(height: 16),

                PrimaryButton(
                  text: existing == null ? 'إضافة المساعد' : 'حفظ التعديلات',
                  onTap: () async {
                    final name = nameCtrl.text.trim();
                    final pin = pinCtrl.text.trim();
                    if (name.isEmpty) {
                      showSnack(ctx, 'أدخل اسم المساعد', isError: true);
                      return;
                    }
                    if (pin.length != 4 || int.tryParse(pin) == null) {
                      showSnack(ctx, 'رمز PIN يجب أن يكون 4 أرقام',
                          isError: true);
                      return;
                    }

                    // فحص تكرار PIN
                    final isDuplicate = await DatabaseHelper.instance
                        .isPinDuplicate(pin, excludeId: existing?.id);
                    if (isDuplicate) {
                      if (ctx.mounted) {
                        showSnack(ctx, '⚠️ رمز PIN مستخدم بالفعل لمساعد آخر',
                            isError: true);
                      }
                      return;
                    }

                    // فحص الحد الأقصى للمساعدين النشطين عند التفعيل أو الإضافة كنشط
                    if (isActive) {
                      bool isNewAndActive = (existing == null);
                      bool isReactivated = (existing != null && !existing.isActive);
                      if (isNewAndActive || isReactivated) {
                        if (_currentCount >= _maxSlots) {
                          showSnack(ctx, '⚠️ لقد تجاوزت الحد الأقصى للمساعدين النشطين ($_maxSlots). يرجى ترقية الاشتراك أو تعطيل مساعد آخر أولاً.', isError: true);
                          return;
                        }
                      }
                    }

                    final data = {
                      'name': name,
                      'phone': phoneCtrl.text.trim(),
                      'pin': pin,
                      'role': 'assistant',
                      'can_add_debt': canAddDebt ? 1 : 0,
                      'can_edit_debt': canEditDebt ? 1 : 0,
                      'can_delete': canDelete ? 1 : 0,
                      'can_view_reports': canViewReports ? 1 : 0,
                      'can_manage_invoices': canManageInvoices ? 1 : 0,
                      'can_manage_shortages': canManageShortages ? 1 : 0,
                      'can_manage_reps': canManageReps ? 1 : 0,
                      'is_active': isActive ? 1 : 0,
                      'subscription_expiry': subscriptionExpiry.toIso8601String(),
                      'subscription_duration_days': subscriptionDurationDays,
                    };

                    if (existing == null) {
                      await DatabaseHelper.instance.insertAssistant(data);
                      await DatabaseHelper.instance.logActivity(
                        assistantName: 'المالك',
                        action: 'إضافة مساعد',
                        details: 'تم إضافة المساعد: $name',
                        screen: 'assistants',
                      );
                    } else {
                      await DatabaseHelper.instance
                          .updateAssistant(existing.id!, data);
                      await DatabaseHelper.instance.logActivity(
                        assistantName: 'المالك',
                        action: 'تعديل مساعد',
                        details: 'تم تعديل بيانات: $name',
                        screen: 'assistants',
                      );
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                    if (mounted) {
                      showSnack(context,
                          existing == null ? 'تم إضافة المساعد ✅' : 'تم التعديل ✅');
                    }
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isDanger = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: value
                ? (isDanger
                    ? AppColors.danger.withValues(alpha: 0.4)
                    : AppColors.primary.withValues(alpha: 0.3))
                : AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: isDanger ? AppColors.danger : AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: AppColors.textColor, fontSize: 13)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: isDanger ? AppColors.danger : AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _durationBtn(int val, String label, int currentVal, bool enabled, ValueChanged<int> onTap) {
    final active = currentVal == val && enabled;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: enabled ? () => onTap(val) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : (enabled ? AppColors.darkCard : AppColors.darkCard.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? AppColors.primary
                    : (enabled ? AppColors.darkBorder : AppColors.darkBorder.withValues(alpha: 0.2)),
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: active
                      ? AppColors.primary
                      : (enabled ? AppColors.textColor : AppColors.textMuted.withValues(alpha: 0.4)),
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  Widget _buildAssistantSubscriptionBanner(Assistant assistant) {
    if (assistant.subscriptionExpiry == null) {
      return const SizedBox.shrink();
    }

    final expiry = assistant.subscriptionExpiry!;
    final isExpired = assistant.isSubscriptionExpired;
    final dateStr = _formatDate(expiry);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isExpired
            ? AppColors.danger.withValues(alpha: 0.1)
            : AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isExpired
              ? AppColors.danger.withValues(alpha: 0.3)
              : AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isExpired ? Icons.warning_amber_rounded : Icons.timer_outlined,
            size: 14,
            color: isExpired ? AppColors.danger : AppColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isExpired
                  ? '⚠️ انتهى الاشتراك في: $dateStr'
                  : '📅 ينتهي الاشتراك في: $dateStr',
              style: TextStyle(
                color: isExpired ? AppColors.danger : AppColors.textColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('👥 إدارة المساعدين',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync_rounded, color: AppColors.primary),
            tooltip: 'مزامنة سحابية',
            onPressed: () async {
              showSnack(context, 'جاري المزامنة السحابية...', isError: false);
              await SyncService.instance.syncAll();
              if (mounted) {
                showSnack(context, '✅ تمت المزامنة بنجاح!');
                _load(); // إعادة تحميل القائمة في حال جاءت تعديلات من السحابة
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: '👤 المساعدون', icon: Icon(Icons.people, size: 18)),
            Tab(text: '📋 سجل النشاط', icon: Icon(Icons.history, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildAssistantsTab(),
          _buildActivityLogTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'assistants_fab',
        onPressed: () => _tryAddAssistant(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('مساعد جديد',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo')),
      ),
    );
  }

  /// توليد كود صيدلية فريد (6 أحرف وأرقام)
  String _generatePharmacyCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// التحقق من الحد الأقصى قبل إضافة مساعد
  Future<void> _tryAddAssistant() async {
    if (_maxSlots <= 0) {
      // لم يشترك في باقة المساعدين أصلاً
      _showSubscriptionRequired();
      return;
    }
    if (_currentCount >= _maxSlots) {
      // وصل للحد الأقصى
      _showSlotLimitReached();
      return;
    }
    _showAddAssistant();
  }

  void _showSubscriptionRequired() {
    final codeCtrl = TextEditingController();
    String error = '';
    bool isValidating = false;
    int selectedPlan = 0; // 0 = 3 مساعدين, 1 = 1 إضافي

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                    child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                const Center(child: Text('🔐', style: TextStyle(fontSize: 40))),
                const SizedBox(height: 8),
                const Center(
                  child: Text('تفعيل باقة المساعدين',
                      style: TextStyle(color: AppColors.primary,
                          fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text('اختر الباقة وأدخل كود التفعيل',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ),
                const SizedBox(height: 20),

                // ── اختيار الباقة ──
                const Text('📦 اختر الباقة',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),

                // باقة 3 مساعدين
                InkWell(
                  onTap: () => setBS(() => selectedPlan = 0),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selectedPlan == 0
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.dark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedPlan == 0
                            ? AppColors.primary
                            : AppColors.darkBorder,
                        width: selectedPlan == 0 ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(child: Text('👥', style: TextStyle(fontSize: 22))),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('باقة المساعدين',
                                  style: TextStyle(color: AppColors.textColor,
                                      fontWeight: FontWeight.w700, fontSize: 14)),
                              Text('3 مساعدين + صلاحيات + تتبع النشاط',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            const Text('99', style: TextStyle(
                                color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 20)),
                            Text(_pharmacyCode.isEmpty ? 'ج.م' : 'ج.م/شهر',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // باقة 1 إضافي
                InkWell(
                  onTap: () => setBS(() => selectedPlan = 1),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selectedPlan == 1
                          ? Colors.teal.withValues(alpha: 0.1)
                          : AppColors.dark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedPlan == 1
                            ? Colors.teal
                            : AppColors.darkBorder,
                        width: selectedPlan == 1 ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(child: Text('👤', style: TextStyle(fontSize: 22))),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('مساعد إضافي',
                                  style: TextStyle(color: AppColors.textColor,
                                      fontWeight: FontWeight.w700, fontSize: 14)),
                              Text('مكان واحد إضافي فوق العدد الأساسي',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            Text('${DatabaseHelper.getNextExtraPrice(_extraSlots)}',
                                style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.w900, fontSize: 20)),
                            const Text('ج.م/شهر',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                            Text('(${_extraSlots}/3)',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── إدخال الكود ──
                const Text('🎟️ كود التفعيل',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4),
                  decoration: InputDecoration(
                    hintText: 'أدخل كود التفعيل هنا',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14, letterSpacing: 0),
                    counterText: '',
                    prefixIcon: const Icon(Icons.vpn_key_rounded, color: AppColors.primary),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: error.isNotEmpty ? AppColors.danger : AppColors.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (_) {
                    if (error.isNotEmpty) setBS(() => error = '');
                  },
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 16),

                // ── زر التفعيل ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isValidating ? null : () async {
                      final code = codeCtrl.text.trim().toUpperCase();
                      if (code.isEmpty) {
                        setBS(() => error = 'أدخل كود التفعيل');
                        return;
                      }
                      setBS(() { isValidating = true; error = ''; });

                      // التحقق من الكود
                      final db = DatabaseHelper.instance;
                      final result = await _validateAssistantCode(code, selectedPlan == 0 ? 3 : 1);
                      
                      setBS(() => isValidating = false);
                      
                      if (result == true) {
                        final totalSlots = await db.getAssistantSlots();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSnack(context, selectedPlan == 0
                              ? '✅ تم تفعيل 3 أماكن مساعدين! (الإجمالي: $totalSlots)'
                              : '✅ تم تفعيل مكان إضافي! (الإجمالي: $totalSlots)');
                          _load();
                        }
                      } else {
                        setBS(() => error = 'كود غير صحيح أو تم استخدامه');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedPlan == 0 ? AppColors.primary : Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: isValidating
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle, size: 20),
                    label: Text(
                      isValidating ? 'جاري التحقق...' : 'تفعيل الباقة',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // رابط شاشة الاشتراك الكاملة
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                    },
                    child: const Text('عرض كل الباقات والخصومات ←',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// التحقق من كود التفعيل وإضافة الأماكن
  Future<bool> _validateAssistantCode(String code, int slotsToAdd) async {
    final db = DatabaseHelper.instance;

    // التحقق من حد الأماكن الإضافية (assistant_1 = 1 مكان بحد أقصى 3)
    if (slotsToAdd == 1) {
      final extras = await db.getExtraAssistantSlots();
      if (extras >= DatabaseHelper.maxExtraAssistantSlots) {
        return false; // وصل للحد الأقصى
      }
    }

    // Admin bypass (من GitHub Secrets فقط)
    if (EnvConfig.adminCode1.isNotEmpty && code == EnvConfig.adminCode1 ||
        EnvConfig.adminCode2.isNotEmpty && code == EnvConfig.adminCode2) {
      await db.addAssistantSlots(slotsToAdd);
      await db.setSetting('assistants_activated', '1');
      return true;
    }

    final localDb = await db.database;

    // مزامنة أكواد من السحابة
    try {
      final cloudCodes = await SupabaseService.instance.fetchSubscriptionCodes()
          .timeout(const Duration(seconds: 4), onTimeout: () => []);
      if (cloudCodes.isNotEmpty) {
        await db.syncCodesFromCloud(cloudCodes);
      }
    } catch (_) {}

    // البحث في الأكواد المحلية
    List<Map<String, dynamic>> localCodes = [];
    try {
      localCodes = await localDb.query('subscription_codes', where: 'code = ?', whereArgs: [code]);
    } catch (_) {}

    Map<String, dynamic>? data;
    bool isLocal = false;

    if (localCodes.isNotEmpty) {
      data = localCodes.first;
      isLocal = true;
    } else {
      try {
        data = await SupabaseService.instance.checkSubscriptionCode(code)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
      } catch (_) {}
    }

    if (data == null) return false;

    final rawActive = data['is_active'];
    final bool isActive = rawActive == true || rawActive == 1 || rawActive == '1' || rawActive == 'true';
    if (!isActive) return false;

    final maxUses = (data['max_uses'] is int) ? data['max_uses'] : int.tryParse(data['max_uses']?.toString() ?? '1') ?? 1;
    final usedCount = (data['used_count'] is int) ? data['used_count'] : int.tryParse(data['used_count']?.toString() ?? '0') ?? 0;
    if (usedCount >= maxUses) return false;

    // تحديث الاستخدام
    if (isLocal) {
      await localDb.update('subscription_codes', {'used_count': usedCount + 1},
          where: 'code = ?', whereArgs: [code]);
    }
    SupabaseService.instance.updateSubscriptionCodeUsage(code, usedCount + 1);

    // إضافة الأماكن
    await db.addAssistantSlots(slotsToAdd);
    await db.setSetting('assistants_activated', '1');
    return true;
  }

  void _showSlotLimitReached() {
    final codeCtrl = TextEditingController();
    String error = '';
    bool isValidating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                    child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                const Center(child: Text('⚠️', style: TextStyle(fontSize: 40))),
                const SizedBox(height: 8),
                const Center(
                  child: Text('وصلت للحد الأقصى',
                      style: TextStyle(color: AppColors.warning,
                          fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text('لديك $_currentCount/$_maxSlots مساعد نشط',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ),
                const SizedBox(height: 20),

                // خيار إضافة مكان إضافي
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Text('👤', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('أضف مكان إضافي',
                                style: TextStyle(color: AppColors.textColor,
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            Text('أدخل كود تفعيل مساعد إضافي (${DatabaseHelper.getNextExtraPrice(_extraSlots)} ج.م - ${_extraSlots}/3 مفعّل)',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── إدخال الكود ──
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.teal,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4),
                  decoration: InputDecoration(
                    hintText: 'أدخل كود المكان الإضافي',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14, letterSpacing: 0),
                    counterText: '',
                    prefixIcon: const Icon(Icons.vpn_key_rounded, color: Colors.teal),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: error.isNotEmpty ? AppColors.danger : AppColors.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.teal),
                    ),
                  ),
                  onChanged: (_) {
                    if (error.isNotEmpty) setBS(() => error = '');
                  },
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 14),

                // ── زر التفعيل ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isValidating ? null : () async {
                      final code = codeCtrl.text.trim().toUpperCase();
                      if (code.isEmpty) {
                        setBS(() => error = 'أدخل كود التفعيل');
                        return;
                      }
                      setBS(() { isValidating = true; error = ''; });

                      final db = DatabaseHelper.instance;
                      final result = await _validateAssistantCode(code, 1);

                      setBS(() => isValidating = false);

                      if (result == true) {
                        final totalSlots = await db.getAssistantSlots();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSnack(context, '✅ تم تفعيل مكان إضافي! (الإجمالي: $totalSlots)');
                          _load();
                        }
                      } else {
                        setBS(() => error = 'كود غير صحيح أو تم استخدامه');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: isValidating
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.add_circle, size: 20),
                    label: Text(
                      isValidating ? 'جاري التحقق...' : 'تفعيل مكان إضافي',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // رابط شاشة الاشتراك
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                    },
                    child: const Text('عرض كل الباقات ←',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// بانر يعرض عدد الأماكن المستخدمة والمتاحة
  Widget _buildSlotsBanner() {
    if (_maxSlots <= 0) return const SizedBox.shrink();
    final remaining = _maxSlots - _currentCount;
    final isNearLimit = remaining <= 1;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNearLimit
            ? AppColors.warning.withValues(alpha: 0.08)
            : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isNearLimit
                ? AppColors.warning.withValues(alpha: 0.3)
                : AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Text(isNearLimit ? '⚠️' : '👥', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_currentCount / $_maxSlots مساعد',
                    style: TextStyle(
                        color: isNearLimit ? AppColors.warning : AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(
                    remaining > 0 ? 'متبقي $remaining أماكن' : 'لا توجد أماكن متاحة',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          if (remaining <= 0)
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('+ أماكن',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAssistantsTab() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_assistants.isEmpty) {
      return Column(
        children: [
          if (_pharmacyCode.isNotEmpty) _buildPharmacyCodeBanner(),
          _buildSlotsBanner(),
          Expanded(
            child: EmptyState(
              emoji: '👥',
              title: 'لا يوجد مساعدون',
              subtitle: _maxSlots > 0
                  ? 'أضف مساعدين لإدارة الصيدلية معك\nلديك $_maxSlots أماكن متاحة'
                  : 'اشترك في باقة المساعدين لإضافتهم\n💰 100 ج.م = 3 مساعدين',
              buttonText: _maxSlots > 0 ? 'إضافة مساعد' : 'اشترك الآن',
              onButton: () => _maxSlots > 0
                  ? _showAddAssistant()
                  : Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.darkCard,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          // بانر كود الصيدلية
          if (_pharmacyCode.isNotEmpty) _buildPharmacyCodeBanner(),
          const SizedBox(height: 12),
          _buildSlotsBanner(),
          // قائمة المساعدين
          ..._assistants.map(_buildAssistantCard),
        ],
      ),
    );
  }

  Widget _buildPharmacyCodeBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A0A2E).withValues(alpha: 0.9),
            const Color(0xFF16213E),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.08),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                    child: Text('🔑', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('كود الصيدلية',
                        style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Text('شاركه مع مساعديك للدخول',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ],
                ),
              ),
              // زر إعادة التوليد
              GestureDetector(
                onTap: _regenerateCode,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: AppColors.textMuted, size: 14),
                      SizedBox(width: 4),
                      Text('تجديد',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // الكود نفسه
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _pharmacyCode));
              showSnack(context, 'تم نسخ كود الصيدلية 📋');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _pharmacyCode,
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.copy_rounded,
                      color: Color(0xFFFFD700), size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '⚠️ يجب على المساعد تحميل التطبيق واختيار "دخول كمساعد صيدلي" واستخدام هذا الكود.',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerateCode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('⚠️ تجديد كود الصيدلية',
            style: TextStyle(
                color: AppColors.textColor,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        content: const Text(
          'سيتم إنشاء كود جديد وسيحتاج جميع المساعدين للكود الجديد للدخول.\n\nهل أنت متأكد؟',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child:
                const Text('تجديد', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final newCode = _generatePharmacyCode();
      await DatabaseHelper.instance.setSetting('pharmacy_code', newCode);
      // مسح الـ cloud_id القديم حتى يتم التسجيل بالكود الجديد
      await DatabaseHelper.instance.setSetting('pharmacy_cloud_id', '');
      await DatabaseHelper.instance.logActivity(
        assistantName: 'المالك',
        action: 'تجديد كود الصيدلية',
        details: 'تم تغيير كود الصيدلية',
        screen: 'assistants',
      );
      setState(() => _pharmacyCode = newCode);
      // رفع الكود الجديد للسحابة فوراً
      final registered = await SyncService.instance.registerPharmacy();
      if (mounted) {
        showSnack(context, registered
            ? 'تم تجديد الكود ورفعه للسحابة ✅'
            : 'تم تجديد الكود محلياً ⚠️ (تحقق من الإنترنت)');
      }
    }
  }

  Widget _buildAssistantCard(Assistant assistant) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _showAddAssistant(existing: assistant),
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              icon: Icons.edit_rounded,
              label: 'تعديل',
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(14)),
            ),
            SlidableAction(
              onPressed: (_) async {
                final confirm =
                    await showDeleteDialog(context, assistant.name);
                if (confirm == true && assistant.id != null) {
                  await DatabaseHelper.instance
                      .deleteAssistant(assistant.id!);
                  await DatabaseHelper.instance.logActivity(
                    assistantName: 'المالك',
                    action: 'حذف مساعد',
                    details: 'تم حذف المساعد: ${assistant.name}',
                    screen: 'assistants',
                  );
                  await _load();
                  if (mounted) showSnack(context, 'تم الحذف');
                }
              },
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              icon: Icons.delete_rounded,
              label: 'حذف',
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: assistant.isActive
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                        child: Text(assistant.name[0],
                            style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 18))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(assistant.name,
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        Text(assistant.roleLabel,
                            style: const TextStyle(
                                color: AppColors.primary, fontSize: 12)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _toggleActive(assistant),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: assistant.isActive
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        assistant.isActive ? 'نشط ✅' : 'معطل ❌',
                        style: TextStyle(
                            color: assistant.isActive
                                ? AppColors.primary
                                : AppColors.danger,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // صلاحيات
              Text('🔐 ${assistant.permissionsSummary}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
              if (assistant.phone != null && assistant.phone!.isNotEmpty)
                Text('📱 ${assistant.phone}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              _buildAssistantSubscriptionBanner(assistant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleActive(Assistant assistant) async {
    if (assistant.id == null) return;
    final newState = assistant.isActive ? 0 : 1;
    if (newState == 1) {
      if (_currentCount >= _maxSlots) {
        showSnack(context, '⚠️ لا توجد أماكن متاحة لتفعيل هذا المساعد. الحد الأقصى: $_maxSlots. يرجى ترقية الاشتراك أو تعطيل مساعد آخر أولاً.', isError: true);
        return;
      }
    }
    await DatabaseHelper.instance
        .updateAssistant(assistant.id!, {'is_active': newState});
    await DatabaseHelper.instance.logActivity(
      assistantName: 'المالك',
      action: newState == 1 ? 'تفعيل مساعد' : 'تعطيل مساعد',
      details:
          '${newState == 1 ? "تم تفعيل" : "تم تعطيل"} المساعد: ${assistant.name}',
      screen: 'assistants',
    );
    await _load();
    if (mounted) {
      showSnack(context,
          newState == 1 ? 'تم تفعيل ${assistant.name} ✅' : 'تم تعطيل ${assistant.name} ❌');
    }
  }

  String _logFilter = 'all'; // فلتر سجل النشاط

  Widget _buildActivityLogTab() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_logs.isEmpty) {
      return const EmptyState(
        emoji: '📋',
        title: 'لا توجد أنشطة',
        subtitle: 'سيظهر هنا سجل بكل حركات المساعدين',
      );
    }

    // فلترة الأنشطة
    final filteredLogs = _logFilter == 'all'
        ? _logs
        : _logs.where((l) => l.assistantName == _logFilter).toList();

    // الأسماء الفريدة للفلتر
    final names = _logs.map((l) => l.assistantName).toSet().toList();

    return Column(
      children: [
        // شريط الفلتر
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _filterChip('الكل', 'all'),
              const SizedBox(width: 6),
              ...names.map((n) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _filterChip(n, n),
                  )),
            ],
          ),
        ),
        // القائمة
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.darkCard,
            onRefresh: _load,
            child: filteredLogs.isEmpty
                ? const Center(
                    child: Text('لا توجد أنشطة لهذا الفلتر',
                        style: TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredLogs.length,
                    itemBuilder: (ctx, i) {
                      final log = filteredLogs[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _getActionColor(log.action)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                  child: Icon(_getActionIcon(log.action),
                                      color: _getActionColor(log.action),
                                      size: 18)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(log.action,
                                      style: const TextStyle(
                                          color: AppColors.textColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  if (log.details != null)
                                    Text(log.details!,
                                        style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11)),
                                  Text(
                                      '${log.assistantName} · ${log.timeAgo}',
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final isActive = _logFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _logFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isActive ? AppColors.primary : AppColors.darkBorder),
        ),
        child: Text(label,
            style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textMuted,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }

  IconData _getActionIcon(String action) {
    if (action.contains('دخول')) return Icons.login_rounded;
    if (action.contains('إضافة')) return Icons.add_circle_outline;
    if (action.contains('تعديل')) return Icons.edit_rounded;
    if (action.contains('حذف')) return Icons.delete_outline;
    if (action.contains('سداد')) return Icons.payments_rounded;
    if (action.contains('تفعيل')) return Icons.check_circle_outline;
    if (action.contains('تعطيل')) return Icons.block_rounded;
    if (action.contains('فاتورة')) return Icons.receipt_long_rounded;
    return Icons.history;
  }

  Color _getActionColor(String action) {
    if (action.contains('دخول')) return AppColors.accent;
    if (action.contains('إضافة')) return AppColors.primary;
    if (action.contains('تعديل')) return const Color(0xFF2563EB);
    if (action.contains('حذف')) return AppColors.danger;
    if (action.contains('سداد')) return AppColors.primary;
    if (action.contains('تفعيل')) return AppColors.primary;
    if (action.contains('تعطيل')) return AppColors.danger;
    if (action.contains('فاتورة')) return AppColors.warning;
    return AppColors.textMuted;
  }
}
