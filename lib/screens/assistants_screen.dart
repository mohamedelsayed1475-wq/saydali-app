import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

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
    if (mounted) {
      setState(() {
        _assistants = assistantsData.map(Assistant.fromMap).toList();
        _logs = logsData.map(ActivityLogEntry.fromMap).toList();
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
        onPressed: () => _showAddAssistant(),
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

  Widget _buildAssistantsTab() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_assistants.isEmpty) {
      return EmptyState(
        emoji: '👥',
        title: 'لا يوجد مساعدون',
        subtitle: 'أضف مساعدين لإدارة الصيدلية معك\nوتحكم في صلاحياتهم',
        buttonText: 'إضافة مساعد',
        onButton: () => _showAddAssistant(),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.darkCard,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _assistants.length,
        itemBuilder: (ctx, i) => _buildAssistantCard(_assistants[i]),
      ),
    );
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
                  Container(
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
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.darkCard,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _logs.length,
        itemBuilder: (ctx, i) {
          final log = _logs[i];
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
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                      child: Icon(Icons.history,
                          color: AppColors.primary, size: 18)),
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
                                color: AppColors.textMuted, fontSize: 11)),
                      Text(
                          '${log.assistantName} · ${log.timeAgo}',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
