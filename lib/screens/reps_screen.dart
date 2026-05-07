import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'send_to_rep_screen.dart';
import 'package:provider/provider.dart';
import '../providers/app_providers.dart';

class RepsScreen extends StatefulWidget {
  const RepsScreen({super.key});

  @override
  State<RepsScreen> createState() => _RepsScreenState();
}

class _RepsScreenState extends State<RepsScreen> {
  List<Representative> _reps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReps();
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
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _reps.isEmpty
              ? EmptyState(
                  emoji: '👥',
                  title: 'لا يوجد مندوبون',
                  subtitle: 'أضف مندوبيك لإرسال النواقص وتتبع الردود',
                  buttonText: 'إضافة مندوب',
                  onButton: () => _showAddSheet(),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.darkCard,
                  onRefresh: _loadReps,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _reps.length,
                    itemBuilder: (ctx, i) => _buildRepCard(_reps[i], i),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('إضافة مندوب',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildRepCard(Representative rep, int index) {
    final medals = ['🥇', '🥈', '🥉'];
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
                final confirm = await showDeleteDialog(context, rep.name);
                if (confirm == true) {
                  await context.read<RepsProvider>().delete(rep.id!);
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
                        Text(rep.name,
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        if (rep.company != null && rep.company!.isNotEmpty)
                          Text(rep.company!,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 12)),
                        StarRating(count: rep.rating),
                      ],
                    ),
                  ),
                  if (index < 3)
                    Text(medals[index], style: const TextStyle(fontSize: 22)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _statBox('تغطية', '${rep.totalCovered} صنف', false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statBox('التقييم', '${rep.rating}/5 ⭐', false),
                  ),
                  const SizedBox(width: 8),
                  if (rep.phone != null && rep.phone!.isNotEmpty)
                    Expanded(child: _statBox('الهاتف', rep.phone!, false)),
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
