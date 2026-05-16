import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/notification_service.dart';

class RepDetailsScreen extends StatefulWidget {
  final Representative rep;
  const RepDetailsScreen({super.key, required this.rep});

  @override
  State<RepDetailsScreen> createState() => _RepDetailsScreenState();
}

class _RepDetailsScreenState extends State<RepDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  String _currency = 'ج.م';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final currency = await DatabaseHelper.instance.getCurrency();
    final orders = await DatabaseHelper.instance.getRepOrders(widget.rep.name);
    final returns = await DatabaseHelper.instance.getRepReturns(widget.rep.name);
    
    if (mounted) {
      setState(() {
        _currency = currency;
        _orders = orders;
        _returns = returns;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _togglePaidStatus(Map<String, dynamic> order) async {
    final newStatus = (order['is_paid'] ?? 0) == 1 ? false : true;
    await DatabaseHelper.instance.updateRepOrderPaidStatus(order['id'] as int, newStatus);
    _loadData();
  }

  Future<void> _toggleReturnStatus(Map<String, dynamic> ret) async {
    final newStatus = (ret['is_returned'] ?? 0) == 1 ? false : true;
    await DatabaseHelper.instance.updateRepReturnStatus(ret['id'] as int, newStatus);
    _loadData();
  }

  Future<void> _deleteOrder(int id) async {
    final confirm = await showDeleteDialog(context, 'هذه الطلبية');
    if (confirm == true) {
      await DatabaseHelper.instance.deleteRepOrder(id);
      _loadData();
    }
  }

  Future<void> _deleteReturn(Map<String, dynamic> ret) async {
    final confirm = await showDeleteDialog(context, 'هذا المرتجع');
    if (confirm == true) {
      final id = ret['id'] as int;
      await NotificationService.instance.cancelReminder(id);
      await DatabaseHelper.instance.deleteRepReturn(id);
      _loadData();
    }
  }

  Future<void> _showAddReturnDialog() async {
    final itemCtrl = TextEditingController();
    String selectedReason = 'تالف';
    final reasons = ['تالف', 'اكسبير', 'سعر قديم', 'أخرى'];
    DateTime? reminderDate;
    TimeOfDay? reminderTime;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20, right: 20, top: 20
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.darkBorder, borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                const Text('🔙 إضافة مرتجع جديد', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 16),
                AppTextField(hint: 'اسم الصنف *', controller: itemCtrl),
                const SizedBox(height: 12),
                const Text('سبب المرتجع:', style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons.map((r) => ChoiceChip(
                    label: Text(r),
                    selected: selectedReason == r,
                    selectedColor: AppColors.warning,
                    backgroundColor: AppColors.dark,
                    labelStyle: TextStyle(color: selectedReason == r ? Colors.white : AppColors.textMuted),
                    onSelected: (_) => setBS(() => selectedReason = r),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                const Text('وقت التنبيه (اختياري):', style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: AppColors.warning,
                                  onPrimary: Colors.white,
                                  surface: AppColors.darkCard,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (date != null) {
                            setBS(() => reminderDate = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: Text(reminderDate == null ? 'التاريخ' : '${reminderDate!.year}/${reminderDate!.month}/${reminderDate!.day}'),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.now(),
                            builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: AppColors.warning,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (time != null) {
                            setBS(() => reminderTime = time);
                          }
                        },
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text(reminderTime == null ? 'الوقت' : reminderTime!.format(ctx)),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
                      ),
                    ),
                  ],
                ),
                if (reminderDate != null && reminderTime == null)
                   const Padding(padding: EdgeInsets.only(top: 4), child: Text('يرجى تحديد الوقت أيضاً', style: TextStyle(color: AppColors.danger, fontSize: 11))),
                const SizedBox(height: 24),
                PrimaryButton(
                  text: 'حفظ المرتجع',
                  onTap: () async {
                    if (itemCtrl.text.trim().isEmpty) {
                      showSnack(ctx, 'أدخل اسم الصنف', isError: true);
                      return;
                    }
                    
                    DateTime? scheduledDate;
                    if (reminderDate != null && reminderTime != null) {
                      scheduledDate = DateTime(
                        reminderDate!.year, reminderDate!.month, reminderDate!.day,
                        reminderTime!.hour, reminderTime!.minute,
                      );
                      if (scheduledDate.isBefore(DateTime.now())) {
                        showSnack(ctx, 'وقت التنبيه يجب أن يكون في المستقبل', isError: true);
                        return;
                      }
                    }

                    final data = {
                      'rep_name': widget.rep.name,
                      'item_name': itemCtrl.text.trim(),
                      'reason': selectedReason,
                      'reminder_time': scheduledDate?.toIso8601String(),
                      'is_returned': 0,
                    };

                    final id = await DatabaseHelper.instance.insertRepReturn(data);

                    if (scheduledDate != null) {
                      await NotificationService.instance.scheduleReturnReminder(
                        id: id,
                        repName: widget.rep.name,
                        itemName: itemCtrl.text.trim(),
                        scheduledDate: scheduledDate,
                      );
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadData();
                    if (mounted) showSnack(context, 'تم حفظ المرتجع بنجاح');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تفاصيل ${widget.rep.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text('${widget.rep.company ?? "بدون شركة"}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
          tabs: const [
            Tab(text: 'الطلبيات', icon: Icon(Icons.inventory_2_outlined)),
            Tab(text: 'المرتجعات', icon: Icon(Icons.assignment_return_outlined)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOrdersTab(),
                _buildReturnsTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddReturnDialog,
        backgroundColor: AppColors.warning,
        icon: const Icon(Icons.add, color: AppColors.dark),
        label: const Text('مرتجع', style: TextStyle(color: AppColors.dark, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildOrdersTab() {
    if (_orders.isEmpty) {
      return const EmptyState(
        emoji: '📦',
        title: 'لا توجد طلبيات',
        subtitle: 'لم يتم استلام أي طلبيات من هذا المندوب حتى الآن',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16).copyWith(bottom: 80),
      itemCount: _orders.length,
      itemBuilder: (ctx, i) {
        final order = _orders[i];
        final isPaid = (order['is_paid'] ?? 0) == 1;
        final date = DateTime.parse(order['created_at']);
        final items = jsonDecode(order['items']) as List;

        return Card(
          color: AppColors.darkCard,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPaid ? AppColors.primary.withValues(alpha: 0.1) : AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(isPaid ? Icons.check_circle : Icons.money_off,
                        color: isPaid ? AppColors.primary : AppColors.danger, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${items.length} أصناف', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('${date.day}/${date.month}/${date.year}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text('${order['total'].toStringAsFixed(2)} $_currency',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              childrenPadding: const EdgeInsets.all(16).copyWith(top: 0),
              children: [
                const Divider(color: AppColors.darkBorder),
                const SizedBox(height: 8),
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('• ${item['name']}', style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                          ),
                          Text('${item['quantity']} × ${item['finalPrice'].toStringAsFixed(2)}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => _deleteOrder(order['id']),
                      icon: const Icon(Icons.delete, color: AppColors.danger, size: 18),
                      label: const Text('حذف', style: TextStyle(color: AppColors.danger)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _togglePaidStatus(order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPaid ? AppColors.darkBorder : AppColors.primary,
                      ),
                      icon: Icon(isPaid ? Icons.close : Icons.check, size: 18),
                      label: Text(isPaid ? 'إلغاء الدفع' : 'تم الدفع'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReturnsTab() {
    if (_returns.isEmpty) {
      return const EmptyState(
        emoji: '🔙',
        title: 'لا توجد مرتجعات',
        subtitle: 'اضغط على زر (مرتجع) بالأسفل لإضافة صنف تريد إرجاعه للمندوب',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16).copyWith(bottom: 80),
      itemCount: _returns.length,
      itemBuilder: (ctx, i) {
        final ret = _returns[i];
        final isReturned = (ret['is_returned'] ?? 0) == 1;
        final date = DateTime.parse(ret['created_at']);
        final reminderTime = ret['reminder_time'] != null ? DateTime.parse(ret['reminder_time']) : null;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isReturned ? AppColors.primary.withValues(alpha: 0.3) : AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(ret['item_name'], style: TextStyle(
                      color: isReturned ? AppColors.textMuted : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      decoration: isReturned ? TextDecoration.lineThrough : null,
                    )),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isReturned ? AppColors.primary.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(ret['reason'], style: TextStyle(
                      color: isReturned ? AppColors.primary : AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    )),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text('أُضيف: ${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2,'0')}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
              if (reminderTime != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.alarm, size: 14, color: isReturned ? AppColors.textMuted : AppColors.accent),
                    const SizedBox(width: 4),
                    Text('تنبيه: ${reminderTime.day}/${reminderTime.month} ${reminderTime.hour}:${reminderTime.minute.toString().padLeft(2,'0')}',
                        style: TextStyle(color: isReturned ? AppColors.textMuted : AppColors.accent, fontSize: 11)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => _deleteReturn(ret),
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    tooltip: 'حذف',
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _toggleReturnStatus(ret),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isReturned ? AppColors.textMuted : AppColors.primary,
                      side: BorderSide(color: isReturned ? AppColors.textMuted : AppColors.primary),
                    ),
                    icon: Icon(isReturned ? Icons.undo : Icons.check_circle_outline, size: 18),
                    label: Text(isReturned ? 'تراجع' : 'تم الإرجاع'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
