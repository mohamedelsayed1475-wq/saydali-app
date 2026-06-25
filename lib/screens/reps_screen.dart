import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'send_to_rep_screen.dart';
import 'package:provider/provider.dart';
import '../providers/app_providers.dart';
import '../providers/current_user_provider.dart';
import 'rep_details_screen.dart';
import 'shortages_screen.dart';

class RepsScreen extends StatefulWidget {
  const RepsScreen({super.key});

  @override
  State<RepsScreen> createState() => _RepsScreenState();
}

class _RepsScreenState extends State<RepsScreen> {
  List<Representative> _reps = [];
  bool _loading = true;
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Representative> get _filteredReps {
    if (_search.isEmpty) return _reps;
    final q = _search.toLowerCase();
    return _reps.where((r) {
      return r.name.toLowerCase().contains(q) ||
          (r.company?.toLowerCase().contains(q) ?? false) ||
          (r.phone?.contains(q) ?? false);
    }).toList();
  }

  Future<void> _loadReps() async {
    if (mounted) {
      await context.read<RepsProvider>().load();
      setState(() {
        _reps = context.read<RepsProvider>().reps;
        _loading = false;
      });
    }
  }

  Future<void> _showAddSheet({Representative? existing}) async {
    // فحص صلاحية إدارة المندوبين
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canManageReps) {
      showSnack(context, '⛔ ليس لديك صلاحية إدارة المندوبين', isError: true);
      return;
    }
    final nameCtrl = TextEditingController(text: existing?.name);
    final companyCtrl = TextEditingController(text: existing?.company);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final notesCtrl = TextEditingController(text: existing?.notes);
    int rating = existing?.rating ?? 5;

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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                Text(existing == null ? '➕ إضافة مندوب' : '✏️ تعديل المندوب',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 16),
                // ―― زر جهات الاتصال ――
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        if (await FlutterContacts.requestPermission(readonly: true)) {
                          final contact = await FlutterContacts.openExternalPick();
                          if (contact != null) {
                            final fullContact = await FlutterContacts.getContact(contact.id);
                            if (fullContact != null) {
                              setBS(() {
                                nameCtrl.text = fullContact.displayName;
                                if (fullContact.phones.isNotEmpty) {
                                  phoneCtrl.text = fullContact.phones.first.number;
                                }
                              });
                            }
                          }
                        } else {
                          showSnack(ctx, '⛔ تم رفض إذن جهات الاتصال', isError: true);
                        }
                      } catch (e) {
                        showSnack(ctx, 'تعذر فتح جهات الاتصال', isError: true);
                      }
                    },
                    icon: const Icon(Icons.contacts_rounded, size: 18),
                    label: const Text('إضافة من جهات الاتصال'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(hint: 'اسم المندوب *', controller: nameCtrl),
                const SizedBox(height: 10),
                AppTextField(hint: 'الشركة', controller: companyCtrl),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'رقم الهاتف',
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'ملاحظات', controller: notesCtrl, maxLines: 2),
                const SizedBox(height: 12),
                const Text('التقييم',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: List.generate(
                      5,
                      (i) => IconButton(
                            onPressed: () => setBS(() => rating = i + 1),
                            icon: Icon(
                              i < rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: AppColors.warning,
                              size: 30,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  text: existing == null ? 'إضافة' : 'حفظ',
                  onTap: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      showSnack(ctx, 'أدخل اسم المندوب', isError: true);
                      return;
                    }
                    final data = {
                      'name': name,
                      'company': companyCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'rating': rating,
                      'notes': notesCtrl.text.trim(),
                    };
                    if (existing == null) {
                      await context.read<RepsProvider>().add(data);
                    } else {
                      await context.read<RepsProvider>().update(existing.id!, data);
                    }
                    // تسجيل النشاط
                    await DatabaseHelper.instance.logActivity(
                      assistantId: userProvider.currentAssistantId,
                      assistantName: userProvider.currentName,
                      action: existing == null ? 'إضافة مندوب' : 'تعديل مندوب',
                      details: '${existing == null ? "تم إضافة" : "تم تعديل"} المندوب: $name',
                      screen: 'reps',
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadReps();
                    if (mounted)
                      showSnack(context,
                          existing == null ? 'تم الإضافة ✅' : 'تم التعديل ✅');
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

  Future<void> _sendShortages(Representative rep) async {
    final shortages =
        await DatabaseHelper.instance.getShortages(status: 'pending');
    if (shortages.isEmpty) {
      if (mounted)
        showSnack(context, 'لا توجد نواقص بانتظار الرد', isError: true);
      // Navigate to ShortagesScreen to allow adding shortages
      if (mounted)
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ShortagesScreen()));
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SendToRepScreen(rep: rep)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('المندوبين',
                style: TextStyle(
                    color: AppColors.textColor, fontWeight: FontWeight.w700)),
            Text('عدد المندوبين ${_reps.length}',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts_rounded,
                color: AppColors.textColor),
            tooltip: 'استيراد من جهات الاتصال',
            onPressed: () => _showAddSheet(),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                // Search Bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(color: AppColors.textColor),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن مندوب...',
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.textMuted),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: AppColors.textMuted, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                            )
                          : const Icon(Icons.tune_rounded,
                              color: AppColors.primary, size: 20),
                    ),
                  ),
                ),
                // List
                Expanded(
                  child: _reps.isEmpty
                      ? const EmptyState(
                          emoji: '👥',
                          title: 'لا يوجد مندوبون',
                          subtitle: 'أضف مندوبين لإرسال النواقص')
                      : _filteredReps.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off_rounded,
                                      color: AppColors.textMuted, size: 48),
                                  SizedBox(height: 12),
                                  Text('لا توجد نتائج',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 15)),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadReps,
                              color: AppColors.primary,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 0, 16, 80),
                                itemCount: _filteredReps.length,
                                itemBuilder: (ctx, i) =>
                                    _buildRepCard(_filteredReps[i], i),
                              ),
                            ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'reps_fab',
        onPressed: () => _showAddSheet(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('مندوب جديد',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildRepCard(Representative rep, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _showAddSheet(existing: rep),
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              icon: Icons.edit_rounded,
              label: 'تعديل',
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(14)),
            ),
            SlidableAction(
              onPressed: (_) async {
                final userProvider = context.read<CurrentUserProvider>();
                if (!userProvider.canDelete) {
                  showSnack(context, '⛔ ليس لديك صلاحية الحذف', isError: true);
                  return;
                }
                final confirm = await showDeleteDialog(context, rep.name);
                if (confirm == true) {
                  await context.read<RepsProvider>().delete(rep.id!);
                  // تسجيل النشاط
                  await DatabaseHelper.instance.logActivity(
                    assistantId: userProvider.currentAssistantId,
                    assistantName: userProvider.currentName,
                    action: 'حذف مندوب',
                    details: 'تم حذف المندوب: ${rep.name}',
                    screen: 'reps',
                  );
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
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RepDetailsScreen(rep: rep)),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border(
                top: BorderSide(
                    color: index == 0 ? AppColors.warning : AppColors.darkBorder,
                    width: index == 0 ? 2 : 1),
                bottom: BorderSide(color: AppColors.darkBorder),
                left: BorderSide(color: AppColors.darkBorder),
                right: BorderSide(color: AppColors.darkBorder),
              ),
              boxShadow: index < 3 ? [
                BoxShadow(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ] : null,
            ),
            child: Column(
              children: [
              Row(
                children: [
                  // Avatar
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark]),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Center(
                        child: Text(rep.name[0],
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 20))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(rep.name,
                                  style: const TextStyle(
                                      color: AppColors.textColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ),
                            // شارة الحالة
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle,
                                      color: AppColors.primary, size: 7),
                                  SizedBox(width: 4),
                                  Text('نشط',
                                      style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right,
                                color: AppColors.textMuted, size: 18),
                          ],
                        ),
                        StarRating(count: rep.rating),
                        if (rep.phone != null && rep.phone!.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.phone_rounded,
                                  color: AppColors.textMuted, size: 12),
                              const SizedBox(width: 4),
                              Text(rep.phone!,
                                  style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _statBox('التغطية', '${rep.totalCovered} صنف', false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statBox('الطلبات', '${rep.totalCovered * 3} طلب', false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _sendShortages(rep),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: const Text('إرسال النواقص بـ QR',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _statBox(String label, String value, bool highlight) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.darkBorder)),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: highlight ? AppColors.primary : AppColors.textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }
}
