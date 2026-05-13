import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'subscription_screen.dart';

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
    if (mounted) {
      setState(() {
        _assistants = assistantsData.map(Assistant.fromMap).toList();
        _logs = logsData.map(ActivityLogEntry.fromMap).toList();
        _pharmacyCode = code!;
        _maxSlots = slots;
        _currentCount = count;
        _loading = false;
      });
    }
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
                      'is_active': 1,
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('👥 باقة المساعدين',
            style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🔐', style: TextStyle(fontSize: 50)),
            SizedBox(height: 12),
            Text('لإضافة مساعدين تحتاج تفعيل باقة المساعدين',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textLight, fontSize: 14)),
            SizedBox(height: 8),
            Text('💰 100 ج.م = 3 مساعدين',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('لاحقاً', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
            },
            child: const Text('اشترك الآن'),
          ),
        ],
      ),
    );
  }

  void _showSlotLimitReached() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚠️ وصلت للحد الأقصى',
            style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📊', style: TextStyle(fontSize: 50)),
            const SizedBox(height: 12),
            Text('لديك $_currentCount/$_maxSlots مساعد',
                style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
            const SizedBox(height: 8),
            const Text('اشترك بكود مساعدين جديد لإضافة 3 أماكن إضافية',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            const Text('💰 100 ج.م = 3 مساعدين إضافيين',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 15)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
            },
            child: const Text('اشترك الآن'),
          ),
        ],
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
            '⚠️ المساعد يحتاج هذا الكود + رمز PIN الخاص به للدخول',
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
      await DatabaseHelper.instance.logActivity(
        assistantName: 'المالك',
        action: 'تجديد كود الصيدلية',
        details: 'تم تغيير كود الصيدلية',
        screen: 'assistants',
      );
      setState(() => _pharmacyCode = newCode);
      if (mounted) showSnack(context, 'تم تجديد الكود بنجاح ✅');
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleActive(Assistant assistant) async {
    if (assistant.id == null) return;
    final newState = assistant.isActive ? 0 : 1;
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
