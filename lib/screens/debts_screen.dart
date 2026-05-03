import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  List<Customer> _customers = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final data = await DatabaseHelper.instance.getCustomers();
    if (mounted) {
      setState(() {
        _customers = data.map(Customer.fromMap).toList();
        _loading = false;
      });
    }
  }

  List<Customer> get _filtered => _customers.where((c) =>
      _search.isEmpty || c.name.contains(_search) || (c.phone?.contains(_search) ?? false)).toList();

  double get _totalDebt => _customers.fold(0, (sum, c) => sum + c.totalDebt);

  Future<void> _showAddCustomer({Customer? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final addressCtrl = TextEditingController(text: existing?.address);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.darkBorder, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 16),
            Text(existing == null ? '➕ إضافة عميل' : '✏️ تعديل العميل',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            AppTextField(hint: 'اسم العميل *', controller: nameCtrl),
            const SizedBox(height: 10),
            AppTextField(hint: 'رقم الهاتف', controller: phoneCtrl, keyboardType: TextInputType.phone),
            const SizedBox(height: 10),
            AppTextField(hint: 'العنوان', controller: addressCtrl),
            const SizedBox(height: 16),
            PrimaryButton(
              text: existing == null ? 'إضافة' : 'حفظ',
              onTap: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  showSnack(ctx, 'أدخل اسم العميل', isError: true);
                  return;
                }
                final Map<String, dynamic> data = {'name': name, 'phone': phoneCtrl.text.trim(), 'address': addressCtrl.text.trim()};
                if (existing == null) {
                  await DatabaseHelper.instance.insertCustomer(data);
                } else {
                  await DatabaseHelper.instance.updateCustomer(existing.id!, data);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadCustomers();
                if (mounted) showSnack(context, existing == null ? 'تم الإضافة ✅' : 'تم التعديل ✅');
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransactions(Customer customer) async {
    final transactions = await DatabaseHelper.instance.getCustomerTransactions(customer.id!);
    final txList = transactions.map(DebtTransaction.fromMap).toList();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String txType = 'debt';

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scroll) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.darkBorder, borderRadius: BorderRadius.circular(99)))),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(customer.name, style: const TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700, fontSize: 16)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: customer.totalDebt > 0 ? AppColors.danger.withValues(alpha: 0.1) : AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${customer.totalDebt.toStringAsFixed(2)} جنيه',
                              style: TextStyle(color: customer.totalDebt > 0 ? AppColors.danger : AppColors.primary, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Add Transaction
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setBS(() => txType = 'debt'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: txType == 'debt' ? AppColors.danger.withValues(alpha: 0.15) : AppColors.dark,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                                  border: Border.all(color: txType == 'debt' ? AppColors.danger : AppColors.darkBorder),
                                ),
                                child: const Center(child: Text('➕ دين', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700))),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setBS(() => txType = 'payment'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: txType == 'payment' ? AppColors.primaryLight : AppColors.dark,
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                                  border: Border.all(color: txType == 'payment' ? AppColors.primary : AppColors.darkBorder),
                                ),
                                child: const Center(child: Text('✅ سداد', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: AppTextField(hint: 'المبلغ', controller: amountCtrl, keyboardType: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(child: AppTextField(hint: 'وصف (اختياري)', controller: descCtrl)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final amount = double.tryParse(amountCtrl.text);
                            if (amount == null || amount <= 0) {
                              showSnack(ctx, 'أدخل مبلغاً صحيحاً', isError: true);
                              return;
                            }
                            await DatabaseHelper.instance.addDebtTransaction({
                              'customer_id': customer.id,
                              'amount': amount,
                              'type': txType,
                              'description': descCtrl.text.trim(),
                            });
                            amountCtrl.clear();
                            descCtrl.clear();
                            await _loadCustomers();
                            final updated = await DatabaseHelper.instance.getCustomers();
                            final updatedCustomer = updated.firstWhere((c) => c['id'] == customer.id);
                            final newTransactions = await DatabaseHelper.instance.getCustomerTransactions(customer.id!);
                            setBS(() {
                              txList.clear();
                              txList.addAll(newTransactions.map(DebtTransaction.fromMap));
                            });
                            if (ctx.mounted) showSnack(ctx, txType == 'debt' ? 'تم إضافة الدين ✅' : 'تم تسجيل السداد ✅');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: txType == 'debt' ? AppColors.danger : AppColors.primary,
                          ),
                          child: Text(txType == 'debt' ? 'إضافة دين' : 'تسجيل سداد'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('سجل المعاملات', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),

                Expanded(
                  child: txList.isEmpty
                      ? const Center(child: Text('لا توجد معاملات بعد', style: TextStyle(color: AppColors.textMuted)))
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: txList.length,
                          itemBuilder: (ctx, i) {
                            final tx = txList[i];
                            final isDebt = tx.type == 'debt';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.dark,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDebt ? AppColors.danger.withValues(alpha: 0.3) : AppColors.primary.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Text(isDebt ? '➕' : '✅', style: const TextStyle(fontSize: 18)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(tx.description ?? (isDebt ? 'دين' : 'سداد'),
                                            style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                                        Text(_formatDate(tx.transactionDate),
                                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${isDebt ? '+' : '-'}${tx.amount.toStringAsFixed(2)} جنيه',
                                    style: TextStyle(color: isDebt ? AppColors.danger : AppColors.primary, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Column(
        children: [
          // Total Debt Banner
          if (_customers.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.danger.withValues(alpha: 0.2), AppColors.darkCard],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('💰', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إجمالي الديون', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      Text('${_totalDebt.toStringAsFixed(2)} جنيه',
                          style: const TextStyle(color: AppColors.danger, fontSize: 24, fontWeight: FontWeight.w800)),
                      Text('${_customers.length} عميل', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: AppColors.textColor),
              decoration: const InputDecoration(
                hintText: 'ابحث عن عميل...',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _filtered.isEmpty
                    ? EmptyState(
                        emoji: '👤',
                        title: 'لا يوجد عملاء',
                        subtitle: 'أضف عملاءك لتتبع ديونهم ومدفوعاتهم',
                        buttonText: 'إضافة عميل',
                        onButton: () => _showAddCustomer(),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.darkCard,
                        onRefresh: _loadCustomers,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) => _buildCustomerCard(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCustomer(),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('إضافة عميل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildCustomerCard(Customer customer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _showAddCustomer(existing: customer),
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              icon: Icons.edit_rounded,
              label: 'تعديل',
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
            ),
            SlidableAction(
              onPressed: (_) async {
                final confirm = await showDeleteDialog(context, customer.name);
                if (confirm == true) {
                  await DatabaseHelper.instance.deleteCustomer(customer.id!);
                  await _loadCustomers();
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
          onTap: () => _showTransactions(customer),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: customer.totalDebt > 0 ? AppColors.danger.withValues(alpha: 0.3) : AppColors.darkBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: Center(child: Text(customer.name[0], style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 18))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.name, style: const TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700)),
                      if (customer.phone != null && customer.phone!.isNotEmpty)
                        Text(customer.phone!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${customer.totalDebt.toStringAsFixed(2)} جنيه',
                      style: TextStyle(
                        color: customer.totalDebt > 0 ? AppColors.danger : AppColors.primary,
                        fontWeight: FontWeight.w800, fontSize: 15,
                      ),
                    ),
                    Text(customer.totalDebt > 0 ? 'دين متبقي' : 'لا يوجد دين',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_left, color: AppColors.textMuted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
