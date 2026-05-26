import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../providers/current_user_provider.dart';
import '../providers/app_providers.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../utils/fuzzy_search.dart';
import '../services/sync_service.dart';
import 'scanner_screen.dart';

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});
  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  List<Map<String, dynamic>> _invoices = [];
  bool _loading = true;
  String _currency = 'ج.م';
  
  // ▌ اقتراحات الأصناف
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSuggestions();
    // تحديث تلقائي كل 4 ثواني
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _load();
    });
  }

  Future<void> _load() async {
    final invoices = await DatabaseHelper.instance.getInvoices();
    final currency = await DatabaseHelper.instance.getCurrency();
    if (mounted) {
      setState(() {
        _invoices = invoices;
        _currency = currency;
        _loading = false;
      });
    }
  }



  Future<void> _loadSuggestions() async {
    final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        if (mounted) setState(() => _suggestions = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      } catch (_) {}
    } else {
      final oldDictStr = await DatabaseHelper.instance.getSetting('drug_dictionary');
      if (oldDictStr != null) {
        try {
          final List<dynamic> decoded = jsonDecode(oldDictStr);
          if (mounted) setState(() => _suggestions = decoded.map((s) => {'enName': s.toString()}).toList());
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _createInvoice() async {
    // فحص صلاحية إدارة الفواتير
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canManageInvoices) {
      showSnack(context, '⛔ ليس لديك صلاحية إدارة الفواتير', isError: true);
      return;
    }
    final nameCtrl = TextEditingController(text: 'بيع نقدي');
    final paidCtrl = TextEditingController(text: '0');
    final items = <Map<String, dynamic>>[];
    double discount = 0;
    Customer? selectedCustomer;
    double paidAmount = 0.0;
    String debtOption = 'cash'; // 'cash' | 'full_debt' | 'partial_debt'
    double partialDebtAmount = 0.0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) {
          final customers = context.read<CustomersProvider>().customers;
          double subtotal = items.fold(0, (s, i) => s + (i['line_total'] ?? (i['price'] * i['qty'])));
          double total = subtotal - (subtotal * discount / 100);
          double remaining = total - paidAmount;
          if (remaining < 0) remaining = 0.0;

          return DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scroll) => Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
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
                        const Text('🧾 إنشاء فاتورة جديدة',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        const SizedBox(height: 12),
                        // ── اسم العميل ──
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                hint: 'اسم العميل',
                                controller: nameCtrl,
                                onChanged: (val) {
                                  setBS(() {
                                    if (selectedCustomer != null && selectedCustomer!.name != val) {
                                      selectedCustomer = null;
                                      debtOption = 'cash';
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            // زر البحث في العملاء
                            InkWell(
                              onTap: () {
                                setBS(() {
                                  nameCtrl.clear();
                                  selectedCustomer = null;
                                  debtOption = 'cash';
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.person_search_rounded, color: AppColors.primary, size: 22),
                              ),
                            ),
                          ],
                        ),
                        
                        // قائمة اقتراحات أسماء العملاء
                        if (nameCtrl.text.isNotEmpty && nameCtrl.text != 'بيع نقدي' && selectedCustomer == null) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 4, bottom: 8),
                            constraints: const BoxConstraints(maxHeight: 150),
                            decoration: BoxDecoration(
                              color: AppColors.darkCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.darkBorder),
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              children: customers
                                  .where((c) => c.name.toLowerCase().contains(nameCtrl.text.toLowerCase()))
                                  .map((c) => ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.person, color: AppColors.primary, size: 18),
                                        title: Text(c.name, style: const TextStyle(color: AppColors.textColor)),
                                        subtitle: c.totalDebt > 0
                                            ? Text('عليه: ${c.totalDebt.toStringAsFixed(2)} $_currency', 
                                                style: const TextStyle(color: AppColors.danger, fontSize: 11))
                                            : const Text('لا مديونية', style: TextStyle(color: AppColors.primary, fontSize: 11)),
                                        onTap: () {
                                          setBS(() {
                                            selectedCustomer = c;
                                            nameCtrl.text = c.name;
                                            debtOption = 'cash';
                                          });
                                        },
                                      ))
                                  .toList(),
                            ),
                          ),
                        ] else if (selectedCustomer != null) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 4, bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'عميل مسجل: ${selectedCustomer!.name}',
                                        style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setBS(() {
                                          selectedCustomer = null;
                                          nameCtrl.text = 'بيع نقدي';
                                          debtOption = 'cash';
                                        });
                                      },
                                      child: const Icon(Icons.close_rounded, color: AppColors.danger, size: 18),
                                    ),
                                  ],
                                ),
                                if (selectedCustomer!.totalDebt > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'المديونية الحالية: ${selectedCustomer!.totalDebt.toStringAsFixed(2)} $_currency',
                                    style: const TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 10),
                        // زر إضافة صنف
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _addItem(ctx, items, setBS),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('إضافة صنف'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // قائمة الأصناف
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('أضف أصناف للفاتورة',
                                style: TextStyle(color: AppColors.textMuted)))
                        : ListView.builder(
                            controller: scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: items.length,
                            itemBuilder: (ctx, i) {
                              final item = items[i];
                              final hasDiscount = item['item_discount'] != null && item['item_discount'] > 0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.dark,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AppColors.darkBorder),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item['name'],
                                              style: const TextStyle(
                                                  color: AppColors.textColor,
                                                  fontWeight: FontWeight.w600)),
                                          Text(
                                            '${item['qty_text'] ?? item['qty']} × ${item['price'].toStringAsFixed(2)} $_currency' +
                                                (hasDiscount ? ' (خصم ${item['item_discount']}%)' : ''),
                                            style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 12),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'التكلفة: ${((item['boxes'] ?? 0) * (item['cost_price'] ?? 0) + (item['strips'] ?? 0) * (item['strip_cost_price'] ?? 0)).toStringAsFixed(2)} $_currency',
                                            style: const TextStyle(
                                                color: AppColors.warning,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${(item['line_total'] ?? (item['qty'] * item['price'])).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () =>
                                          setBS(() => items.removeAt(i)),
                                      child: const Icon(Icons.close,
                                          color: AppColors.danger, size: 18),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  // ملخص الفاتورة
                  if (items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.dark,
                        border: Border(
                            top: BorderSide(color: AppColors.darkBorder)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المجموع',
                                  style: TextStyle(color: AppColors.textMuted)),
                              Text('${subtotal.toStringAsFixed(2)} $_currency',
                                  style: const TextStyle(
                                      color: AppColors.textLight)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Text('خصم %  ',
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12)),
                              SizedBox(
                                width: 60,
                                height: 32,
                                child: TextField(
                                  onChanged: (v) {
                                    final parsed = double.tryParse(v);
                                    final clamped = parsed == null ? 0.0 : parsed.clamp(0.0, 100.0);
                                    setBS(() => discount = clamped);
                                  },
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                      color: AppColors.warning, fontSize: 14),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text('الإجمالي: ',
                                  style: const TextStyle(
                                      color: AppColors.textColor,
                                      fontWeight: FontWeight.w700)),
                              Text('${total.toStringAsFixed(2)} $_currency',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المبلغ المدفوع',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                              SizedBox(
                                width: 100,
                                height: 32,
                                child: TextField(
                                  controller: paidCtrl,
                                  onChanged: (v) {
                                    final parsed = double.tryParse(v) ?? 0.0;
                                    setBS(() {
                                      paidAmount = parsed;
                                    });
                                  },
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                      color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 0),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // ── حساب الباقي / الفكة / المديونية ──
                          if (selectedCustomer == null) ...[
                            // === بيع نقدي (لغير العملاء) ===
                            if (paidAmount > total && total > 0) ...[
                              // الفكة (الباقي للعميل)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.keyboard_return_rounded, color: AppColors.primary, size: 18),
                                        SizedBox(width: 6),
                                        Text('الباقي (الفكة)',
                                            style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                    Text('${(paidAmount - total).toStringAsFixed(2)} $_currency',
                                        style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ),
                            ] else if (remaining > 0) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('المتبقي',
                                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                  Text('${remaining.toStringAsFixed(2)} $_currency',
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ],
                          ] else ...[
                            // === عميل مسجل (من المديونية) ===
                            if (paidAmount > total && total > 0) ...[
                              // الفكة
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.keyboard_return_rounded, color: AppColors.primary, size: 18),
                                        SizedBox(width: 6),
                                        Text('الباقي (الفكة)',
                                            style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                    Text('${(paidAmount - total).toStringAsFixed(2)} $_currency',
                                        style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ),
                            ] else if (remaining > 0) ...[
                              // المتبقي على العميل
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('المتبقي على العميل',
                                            style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w700)),
                                        Text('${remaining.toStringAsFixed(2)} $_currency',
                                            style: const TextStyle(
                                                color: AppColors.danger,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('تنزيل من الحساب؟',
                                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                    const SizedBox(height: 6),
                                    // خيارات الدفع
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        _debtChip('💰 كاش', 'cash', debtOption, (v) => setBS(() => debtOption = v)),
                                        _debtChip('📥 المبلغ كامل', 'full_debt', debtOption, (v) => setBS(() => debtOption = v)),
                                        _debtChip('📝 جزء منه', 'partial_debt', debtOption, (v) => setBS(() => debtOption = v)),
                                      ],
                                    ),
                                    if (debtOption == 'partial_debt') ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 36,
                                        child: TextField(
                                          onChanged: (v) {
                                            setBS(() => partialDebtAmount = double.tryParse(v) ?? 0);
                                          },
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(color: AppColors.warning, fontSize: 14),
                                          decoration: InputDecoration(
                                            hintText: 'المبلغ المراد تنزيله من الحساب',
                                            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: AppColors.warning.withValues(alpha: 0.4)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (debtOption == 'full_debt') ...[
                                      const SizedBox(height: 4),
                                      Text('سيتم إضافة ${remaining.toStringAsFixed(2)} $_currency على حساب العميل',
                                          style: const TextStyle(color: AppColors.danger, fontSize: 11)),
                                    ] else if (debtOption == 'cash') ...[
                                      const SizedBox(height: 4),
                                      const Text('العميل سيدفع المتبقي كاش - لن يُضاف للمديونية',
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 12),
                          PrimaryButton(
                            text: '🧾 حفظ ومشاركة الفاتورة',
                            onTap: () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                showSnack(ctx, 'أدخل اسم العميل',
                                    isError: true);
                                return;
                              }
                              if (items.isEmpty) return;
                              await DatabaseHelper.instance.insertInvoice({
                                'customer_id': selectedCustomer?.id,
                                'customer_name': nameCtrl.text.trim(),
                                'items': jsonEncode(items),
                                'subtotal': subtotal,
                                'discount': discount,
                                'total': total,
                                'paid_amount': paidAmount,
                                'remaining': remaining,
                              });
                              SyncService.instance.syncAll(); // مزامنة فورية للفاتورة في الخلفية
                              
                              // تحويل المتبقي للمديونية حسب اختيار المستخدم
                              if (selectedCustomer != null && remaining > 0) {
                                final userProvider = context.read<CurrentUserProvider>();
                                
                                // إنشاء وصف تفصيلي للأصناف والكميات
                                final itemsList = items.map((item) {
                                  final qtyVal = item['qty'] ?? 1;
                                  final qtyText = item['qty_text'] ?? '$qtyVal علبة';
                                  return '• ${item['name']} ($qtyText)';
                                }).join('\n');

                                double debtAmount = 0;
                                if (debtOption == 'full_debt') {
                                  debtAmount = remaining;
                                } else if (debtOption == 'partial_debt') {
                                  debtAmount = partialDebtAmount.clamp(0, remaining);
                                }
                                // debtOption == 'cash' → لا يُضاف شيء للمديونية

                                if (debtAmount > 0) {
                                  final description = 'متبقي فاتورة أصناف:\n$itemsList';
                                  await DatabaseHelper.instance.addDebtTransaction({
                                    'customer_id': selectedCustomer!.id,
                                    'amount': debtAmount,
                                    'type': 'debt',
                                    'description': description,
                                    'created_by': userProvider.currentName,
                                  });
                                  // تحديث مزود بيانات العملاء فوراً
                                  await context.read<CustomersProvider>().load();
                                }
                              }

                              // تسجيل النشاط
                              final userProvider = context.read<CurrentUserProvider>();
                              await DatabaseHelper.instance.logActivity(
                                assistantId: userProvider.currentAssistantId,
                                assistantName: userProvider.currentName,
                                action: 'إنشاء فاتورة',
                                details: 'تم إنشاء فاتورة للعميل: ${nameCtrl.text.trim()} - الإجمالي: ${total.toStringAsFixed(2)} - المدفوع: ${paidAmount.toStringAsFixed(2)} - المتبقي: ${remaining.toStringAsFixed(2)}',
                                screen: 'invoices',
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _load();
                              if (mounted) {
                                showSnack(context, 'تم حفظ الفاتورة ✅');
                                _showPrintOptionsDialog(
                                  customerName: nameCtrl.text.trim(),
                                  items: items,
                                  subtotal: subtotal,
                                  discount: discount,
                                  total: total,
                                  paidAmount: paidAmount,
                                  remaining: remaining,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _debtChip(String label, String value, String current, ValueChanged<String> onSelect) {
    final isSelected = current == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.warning.withValues(alpha: 0.2) : AppColors.dark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.warning : AppColors.darkBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: isSelected ? AppColors.warning : AppColors.textMuted,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }

  void _addItem(BuildContext ctx, List<Map<String, dynamic>> items, StateSetter setBS) {
    _showAddItemDialog(ctx, (newItem) {
      setBS(() => items.add(newItem));
    });
  }

  void _addItemToExisting(BuildContext ctx, List<Map<String, dynamic>> items, StateSetter setBS) {
    _showAddItemDialog(ctx, (newItem) {
      setBS(() => items.add(newItem));
    });
  }

  void _showAddItemDialog(BuildContext ctx, Function(Map<String, dynamic>) onAdd, {String? initialName}) {
    final itemNameCtrl = TextEditingController(text: initialName ?? '');

    final priceCtrl = TextEditingController(); // Box Price
    final stripPriceCtrl = TextEditingController(); // Strip Price
    final costPriceCtrl = TextEditingController(); // Box Cost Price
    final stripCostPriceCtrl = TextEditingController(); // Strip Cost Price
    final boxesCtrl = TextEditingController(text: '1');
    final stripsCtrl = TextEditingController(text: '0');
    final discountCtrl = TextEditingController(text: '0'); // Item discount

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDBS) => AlertDialog(
          backgroundColor: AppColors.darkCard,
          title: Row(
            children: [
              const Text('إضافة صنف', style: TextStyle(color: AppColors.primary, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                tooltip: 'مسح QR/باركود',
                onPressed: () async {
                  Navigator.pop(dCtx);
                  final code = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(builder: (_) => const ScannerScreen()),
                  );
                  if (code != null) {
                    _showAddItemDialog(ctx, onAdd, initialName: code);
                  }
                },
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Autocomplete for items
                Row(
                  children: [
                    Expanded(
                      child: Autocomplete<Map<String, dynamic>>(
                        optionsBuilder: (v) {
                          if (v.text.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                          final query = v.text;
                          
                          // تقييم وتصفية العناصر
                          final matches = _suggestions.map((s) {
                            final en = s['enName']?.toString() ?? '';
                            final ar = s['arName']?.toString() ?? '';
                            final act = s['activeIngredient']?.toString() ?? '';
                            final bar = s['barcode']?.toString() ?? '';

                            // نجيب أعلى تقييم بين الحقول المختلفة
                            final scoreEn = FuzzySearch.getScore(query, en);
                            final scoreAr = FuzzySearch.getScore(query, ar);
                            final scoreAct = FuzzySearch.getScore(query, act);
                            final scoreBar = bar.contains(query.trim()) ? 1000 : 0; // الباركود لازم يتطابق

                            final maxScore = [scoreEn, scoreAr, scoreAct, scoreBar].reduce((a, b) => a > b ? a : b);

                            return {'item': s, 'score': maxScore};
                          }).where((element) => (element['score'] as int) > 0).toList();

                          // الترتيب حسب الأعلى تقييماً (الأكثر صلة)
                          matches.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

                          return matches.map((e) => e['item'] as Map<String, dynamic>).take(15);
                        },
                        displayStringForOption: (option) => option['enName']?.toString() ?? '',
                        onSelected: (s) {
                          itemNameCtrl.text = s['enName']?.toString() ?? '';
                          if (s['price'] != null && s['price'].toString().isNotEmpty && s['price'].toString() != '0') {
                            priceCtrl.text = s['price'].toString();
                          }
                          if (s['cost_price'] != null && s['cost_price'].toString().isNotEmpty && s['cost_price'].toString() != '0') {
                            costPriceCtrl.text = s['cost_price'].toString();
                          }
                        },
                        fieldViewBuilder: (ctx, ctrl, fn, onSubmit) {

                          return AppTextField(
                            hint: 'اسم الصنف',
                            controller: ctrl,
                            focusNode: fn,
                            onSubmitted: (_) => onSubmit(),
                            onChanged: (val) => itemNameCtrl.text = val,
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              color: AppColors.darkCard,
                              elevation: 4.0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: AppColors.darkBorder),
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250, maxWidth: 280),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final option = options.elementAt(index);
                                    final en = option['enName']?.toString() ?? '';
                                    final ar = option['arName']?.toString() ?? '';
                                    final price = option['price']?.toString() ?? '';
                                    return InkWell(
                                      onTap: () => onSelected(option),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(en, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                            if (ar.isNotEmpty) Text(ar, style: const TextStyle(color: AppColors.primary, fontSize: 11)),
                                            if (price.isNotEmpty && price != '0') Text('$price $_currency', style: const TextStyle(color: AppColors.warning, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(hint: 'سعر بيع العلبة', controller: priceCtrl, keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: AppTextField(hint: 'عدد العلب', controller: boxesCtrl, keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(hint: 'سعر بيع الشريط', controller: stripPriceCtrl, keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: AppTextField(hint: 'عدد الشرايط', controller: stripsCtrl, keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(hint: 'سعر شراء العلبة (التكلفة)', controller: costPriceCtrl, keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: AppTextField(hint: 'سعر شراء الشريط (التكلفة)', controller: stripCostPriceCtrl, keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 10),
                AppTextField(hint: 'خصم الصنف % (اختياري)', controller: discountCtrl, keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                final name = itemNameCtrl.text.trim();
                final boxPrice = double.tryParse(priceCtrl.text) ?? 0;
                final stripPrice = double.tryParse(stripPriceCtrl.text) ?? 0;
                final boxCost = double.tryParse(costPriceCtrl.text) ?? 0;
                final stripCost = double.tryParse(stripCostPriceCtrl.text) ?? 0;
                final boxes = int.tryParse(boxesCtrl.text) ?? 0;
                final strips = int.tryParse(stripsCtrl.text) ?? 0;
                final itemDiscount = double.tryParse(discountCtrl.text) ?? 0;

                if (name.isEmpty) {
                  showSnack(dCtx, 'أدخل اسم الصنف', isError: true);
                  return;
                }
                if (boxPrice <= 0 && stripPrice <= 0) {
                  showSnack(dCtx, 'أدخل السعر', isError: true);
                  return;
                }
                if (boxes == 0 && strips == 0) {
                  showSnack(dCtx, 'أدخل الكمية', isError: true);
                  return;
                }

                final baseLineTotal = (boxes * boxPrice) + (strips * stripPrice);
                final lineTotal = baseLineTotal - (baseLineTotal * itemDiscount / 100);
                final mainPrice = boxPrice > 0 ? boxPrice : stripPrice;

                String qtyText = '';
                if (boxes > 0) qtyText += '$boxes علبة';
                if (strips > 0) qtyText += (qtyText.isEmpty ? '' : ' و ') + '$strips شريط';

                onAdd({
                  'name': name,
                  'price': mainPrice,
                  'cost_price': boxCost,
                  'strip_cost_price': stripCost,
                  'qty': 1,
                  'qty_text': qtyText,
                  'item_discount': itemDiscount,
                  'line_total': lineTotal,
                  'boxes': boxes,
                  'strips': strips,
                });
                Navigator.pop(dCtx);
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePDF(String customerName,
      List<Map<String, dynamic>> items, double subtotal, double discount,
      double total) async {
    final pdf = pw.Document();
    final pharmacyName =
        await DatabaseHelper.instance.getSetting('pharmacy_name') ??
            'صيدلي PRO';
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('فاتورة بيع',
                          style: pw.TextStyle(
                              fontSize: 22, fontWeight: pw.FontWeight.bold)),
                      pw.Text(pharmacyName,
                          style: const pw.TextStyle(
                              fontSize: 14, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('العميل: $customerName',
                          style: pw.TextStyle(
                              fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                          style: const pw.TextStyle(
                              fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.5),
                  1: const pw.FlexColumnWidth(2.5),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                  5: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey200),
                    children: ['#', 'الصنف', 'الكمية', 'السعر', 'خصم%', 'الإجمالي']
                        .map((h) => pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(h,
                                  style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 11)),
                            ))
                        .toList(),
                  ),
                  ...items.asMap().entries.map((e) {
                    final i = e.key;
                    final item = e.value;
                    final lineTotal = item['line_total'] ?? (item['price'] * item['qty']);
                    final itemDiscount = item['item_discount'] ?? 0;
                    return pw.TableRow(
                      children: [
                        '${i + 1}',
                        item['name'],
                        '${item['qty_text'] ?? item['qty']}',
                        '${item['price'].toStringAsFixed(2)}',
                        itemDiscount > 0 ? '$itemDiscount%' : '-',
                        '${lineTotal.toStringAsFixed(2)}',
                      ]
                          .map((t) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(t,
                                    style: const pw.TextStyle(fontSize: 10)),
                              ))
                          .toList(),
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('المجموع الفرعي:'),
                        pw.Text('${subtotal.toStringAsFixed(2)} $_currency'),
                      ],
                    ),
                    if (discount > 0) ...[
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('الخصم (${discount.toStringAsFixed(0)}%):'),
                          pw.Text(
                              '-${(subtotal * discount / 100).toStringAsFixed(2)} $_currency'),
                        ],
                      ),
                    ],
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('الإجمالي:',
                            style: pw.TextStyle(
                                fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text('${total.toStringAsFixed(2)} $_currency',
                            style: pw.TextStyle(
                                fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),
              pw.Center(
                child: pw.Text(
                    'تم إنشاء هذه الفاتورة بواسطة تطبيق صيدلي PRO',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey500)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'invoice_$customerName.pdf');
  }

  Future<void> _generateThermalPDF(String customerName,
      List<Map<String, dynamic>> items, double subtotal, double discount,
      double total, {double paidAmount = 0.0, double remaining = 0.0}) async {
    final pdf = pw.Document();
    final pharmacyName =
        await DatabaseHelper.instance.getSetting('pharmacy_name') ??
            'صيدلي PRO';
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 5 * PdfPageFormat.mm),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(pharmacyName,
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Center(
                child: pw.Text('فاتورة بيع مبسطة',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 4),
              pw.Text('العميل: $customerName', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 4),
              
              // قائمة الأصناف بشكل مدمج
              ...items.asMap().entries.map((e) {
                final item = e.value;
                final qtyVal = item['qty'] ?? 1;
                final qtyText = item['qty_text'] ?? '$qtyVal علبة';
                final lineTotal = item['line_total'] ?? (item['price'] * qtyVal);
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(item['name'], style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Text('${lineTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('$qtyText × ${item['price'].toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                          if (item['item_discount'] != null && item['item_discount'] > 0)
                            pw.Text('خصم ${item['item_discount']}%', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 4),
              
              // ملخص الحساب
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('المجموع الفرعي:', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('${subtotal.toStringAsFixed(2)} $_currency', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              if (discount > 0) ...[
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الخصم (${discount.toStringAsFixed(0)}%):', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('-${(subtotal * discount / 100).toStringAsFixed(2)} $_currency', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('الإجمالي:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${total.toStringAsFixed(2)} $_currency', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('المدفوع:', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('${paidAmount.toStringAsFixed(2)} $_currency', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              if (remaining > 0) ...[
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('المتبقي (آجل):', style: pw.TextStyle(fontSize: 9, color: PdfColors.red700)),
                    pw.Text('${remaining.toStringAsFixed(2)} $_currency', style: pw.TextStyle(fontSize: 9, color: PdfColors.red700)),
                  ],
                ),
              ],
              
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text('شكرًا لتعاملكم معنا 💖', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Center(
                child: pw.Text('تم إنشاء الإيصال بواسطة صيدلي PRO', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'receipt_$customerName.pdf');
  }

  Future<void> _showPrintOptionsDialog({
    required String customerName,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double total,
    double paidAmount = 0.0,
    double remaining = 0.0,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('خيارات الفاتورة 📄', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: const Text(
          'تم حفظ الفاتورة بنجاح! اختر كيفية تصدير أو طباعة الفاتورة:',
          style: TextStyle(color: AppColors.textLight, fontFamily: 'Cairo', fontSize: 13),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowButtonSpacing: 8,
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _generateThermalPDF(customerName, items, subtotal, discount, total, paidAmount: paidAmount, remaining: remaining);
            },
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('طباعة إيصال حراري (80 مم) 🖨️', style: TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              minimumSize: const Size(220, 42),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _generatePDF(customerName, items, subtotal, discount, total);
            },
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('مشاركة ملف PDF قياسي (A4) 📄', style: TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(220, 42),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  // ▌ تعديل فاتورة
  Future<void> _editInvoice(Map<String, dynamic> invoice) async {
    final invoiceId = invoice['id'] as int;
    final nameCtrl = TextEditingController(text: invoice['customer_name'] ?? '');
    final items = (jsonDecode(invoice['items'] as String) as List)
        .cast<Map<String, dynamic>>();
    double discount = (invoice['discount'] as num).toDouble();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) {
          double subtotal = items.fold(0, (s, i) => s + (i['line_total'] ?? (i['price'] * i['qty'])));
          double total = subtotal - (subtotal * discount / 100);

          return DraggableScrollableSheet(
            initialChildSize: 0.9,
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
                        Center(
                          child: Container(
                            width: 40, height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.darkBorder,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('✏️ تعديل الفاتورة',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 12),
                        AppTextField(hint: 'اسم العميل', controller: nameCtrl),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _addItemToExisting(ctx, items, setBS),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('إضافة صنف'),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('لا توجد أصناف', style: TextStyle(color: AppColors.textMuted)))
                        : ListView.builder(
                            controller: scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: items.length,
                            itemBuilder: (ctx, i) {
                              final item = items[i];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.dark,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.darkBorder),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item['name'], style: const TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w600)),
                                          Text('${item['qty_text'] ?? item['qty']} × ${item['price'].toStringAsFixed(2)} $_currency' +
                                                ((item['item_discount'] != null && item['item_discount'] > 0) ? ' (خصم ${item['item_discount']}%)' : ''),
                                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    Text('${(item['line_total'] ?? (item['qty'] * item['price'])).toStringAsFixed(2)}',
                                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => setBS(() => items.removeAt(i)),
                                      child: const Icon(Icons.close, color: AppColors.danger, size: 18),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  if (items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.dark,
                        border: Border(top: BorderSide(color: AppColors.darkBorder)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المجموع', style: TextStyle(color: AppColors.textMuted)),
                              Text('${subtotal.toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textLight)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Text('خصم %  ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              SizedBox(
                                width: 60, height: 32,
                                child: TextField(
                                  controller: TextEditingController(text: discount.toStringAsFixed(0)),
                                  onChanged: (v) {
                                    final parsed = double.tryParse(v);
                                    setBS(() => discount = parsed == null ? 0.0 : parsed.clamp(0.0, 100.0));
                                  },
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: AppColors.warning, fontSize: 14),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const Text('الإجمالي: ', style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700)),
                              Text('${total.toStringAsFixed(2)} $_currency',
                                  style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          PrimaryButton(
                            text: '💾 حفظ التعديلات',
                            onTap: () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                showSnack(ctx, 'أدخل اسم العميل', isError: true);
                                return;
                              }
                              if (items.isEmpty) {
                                showSnack(ctx, 'أضف أصناف', isError: true);
                                return;
                              }
                              await DatabaseHelper.instance.updateInvoice(invoiceId, {
                                'customer_name': nameCtrl.text.trim(),
                                'items': jsonEncode(items),
                                'subtotal': subtotal,
                                'discount': discount,
                                'total': total,
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _load();
                              if (mounted) showSnack(context, 'تم تعديل الفاتورة ✅');
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }



  // ▌ عرض تفاصيل فاتورة
  void _viewInvoiceDetails(Map<String, dynamic> invoice) {
    final items = (jsonDecode(invoice['items'] as String) as List).cast<Map<String, dynamic>>();
    final date = DateTime.tryParse(invoice['created_at'] ?? '');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.darkBorder, borderRadius: BorderRadius.circular(99))),
            ),
            const SizedBox(height: 16),
            Text('🧾 الفاتورة - ${invoice['customer_name']}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            if (date != null)
              Text(DateFormat('yyyy/MM/dd HH:mm').format(date), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            const Divider(color: AppColors.darkBorder),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${item['name']} × ${item['qty_text'] ?? item['qty']}', style: const TextStyle(color: AppColors.textColor)),
                  Text('${(item['line_total'] ?? (item['price'] * item['qty'])).toStringAsFixed(2)}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            )),
            const Divider(color: AppColors.darkBorder),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الإجمالي', style: TextStyle(color: AppColors.textMuted)),
                Text('${(invoice['total'] as num).toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 8),
            // المبلغ المدفوع والمتبقي
            () {
              final paid = (invoice['paid_amount'] as num?)?.toDouble() ?? 0;
              final rem = (invoice['remaining'] as num?)?.toDouble() ?? 0;
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('💵 المدفوع', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      Text('${paid.toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(rem > 0 ? '⚠️ المتبقي (محوّل للمديونية)' : '✅ الحالة', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      Text(
                        rem > 0 ? '${rem.toStringAsFixed(2)} $_currency' : 'مدفوع بالكامل',
                        style: TextStyle(
                          color: rem > 0 ? AppColors.danger : AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _generatePDF(invoice['customer_name'], items, (invoice['subtotal'] as num).toDouble(),
                          (invoice['discount'] as num).toDouble(), (invoice['total'] as num).toDouble());
                    },
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('مشاركة A4 📄', style: TextStyle(fontSize: 12, fontFamily: 'Cairo')),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _generateThermalPDF(
                        invoice['customer_name'],
                        items,
                        (invoice['subtotal'] as num).toDouble(),
                        (invoice['discount'] as num).toDouble(),
                        (invoice['total'] as num).toDouble(),
                        paidAmount: (invoice['paid_amount'] as num?)?.toDouble() ?? 0.0,
                        remaining: (invoice['remaining'] as num?)?.toDouble() ?? 0.0,
                      );
                    },
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text('طباعة حرارية 🖨️', style: TextStyle(fontSize: 12, fontFamily: 'Cairo')),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ▌ حذف فاتورة
  Future<void> _deleteInvoice(Map<String, dynamic> invoice) async {
    // فحص صلاحية الحذف
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canDelete) {
      showSnack(context, '⛔ ليس لديك صلاحية الحذف', isError: true);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('حذف الفاتورة', style: TextStyle(color: AppColors.danger)),
        content: Text('هل تريد حذف فاتورة "${invoice['customer_name']}"؟\n⚠️ لا يمكن التراجع عن هذا الإجراء.',
            style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteInvoice(invoice['id'] as int);
      // تسجيل النشاط
      await DatabaseHelper.instance.logActivity(
        assistantId: userProvider.currentAssistantId,
        assistantName: userProvider.currentName,
        action: 'حذف فاتورة',
        details: 'تم حذف فاتورة: ${invoice['customer_name']}',
        screen: 'invoices',
      );
      await _load();
      if (mounted) showSnack(context, 'تم حذف الفاتورة ✅');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('🧾 الفواتير',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'invoice_fab',
        onPressed: _createInvoice,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('فاتورة جديدة',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _invoices.isEmpty
              ? const Center(
                  child: EmptyState(
                    emoji: '🧾',
                    title: 'لا توجد فواتير',
                    subtitle: 'أنشئ فاتورة بيع جديدة للعملاء',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _invoices.length,
                  itemBuilder: (ctx, i) {
                    final inv = _invoices[i];
                    final date = DateTime.tryParse(inv['created_at'] ?? '');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Slidable(
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          children: [
                            // ▌ زر التعديل
                            SlidableAction(
                              onPressed: (_) => _editInvoice(inv),
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              icon: Icons.edit_rounded,
                              label: 'تعديل',
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                            ),
                            // ▌ زر الحذف
                            SlidableAction(
                              onPressed: (_) => _deleteInvoice(inv),
                              backgroundColor: AppColors.danger,
                              foregroundColor: Colors.white,
                              icon: Icons.delete_rounded,
                              label: 'حذف',
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: () => _viewInvoiceDetails(inv),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.darkCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.darkBorder),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(
                                    child: Text('🧾', style: TextStyle(fontSize: 20)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(inv['customer_name'] ?? '',
                                          style: const TextStyle(
                                              color: AppColors.textColor,
                                              fontWeight: FontWeight.w700)),
                                      if (date != null)
                                        Text(
                                          DateFormat('yyyy/MM/dd HH:mm').format(date),
                                          style: const TextStyle(
                                              color: AppColors.textMuted, fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${(inv['total'] as num).toStringAsFixed(2)} $_currency',
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15),
                                    ),
                                    if ((inv['discount'] as num) > 0)
                                      Text(
                                        'خصم ${(inv['discount'] as num).toStringAsFixed(0)}%',
                                        style: const TextStyle(
                                            color: AppColors.warning, fontSize: 11),
                                      ),
                                    // حالة الدفع
                                    () {
                                      final paid = (inv['paid_amount'] as num?)?.toDouble() ?? 0;
                                      final rem = (inv['remaining'] as num?)?.toDouble() ?? 0;
                                      final total = (inv['total'] as num).toDouble();
                                      if (rem > 0) {
                                        return Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.danger.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'متبقي: ${rem.toStringAsFixed(0)}',
                                            style: const TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w700),
                                          ),
                                        );
                                      } else if (paid > 0 || total == 0) {
                                        return Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'مدفوع بالكامل ✅',
                                            style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700),
                                          ),
                                        );
                                      } else {
                                        return const SizedBox.shrink();
                                      }
                                    }(),
                                  ],
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.share, color: AppColors.primary, size: 20),
                                  onPressed: () async {
                                    final items = (jsonDecode(inv['items']) as List)
                                        .cast<Map<String, dynamic>>();
                                    await _generatePDF(
                                      inv['customer_name'],
                                      items,
                                      (inv['subtotal'] as num).toDouble(),
                                      (inv['discount'] as num).toDouble(),
                                      (inv['total'] as num).toDouble(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
