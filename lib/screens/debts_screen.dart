import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../utils/country_config.dart';
import '../widgets/common_widgets.dart';
import 'package:provider/provider.dart';
import '../providers/app_providers.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  List<Customer> _customers = [];
  bool _loading = true;
  String _search = '';
  String _currency = 'ج.م';
  String _countryCode = 'EG';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final currency = await DatabaseHelper.instance.getCurrency();
    final countryCode = await DatabaseHelper.instance.getCountryCode();
    
    if (!mounted) return;
    await context.read<CustomersProvider>().load();
    if (!mounted) return;
    setState(() {
      _customers = context.read<CustomersProvider>().customers;
      _currency = currency;
      _countryCode = countryCode;
      _loading = false;
    });
  }

  List<Customer> get _filtered => _customers
      .where((c) =>
          _search.isEmpty ||
          c.name.contains(_search) ||
          (c.phone?.contains(_search) ?? false))
      .toList();

  double get _totalDebt => _customers.fold(0, (sum, c) => sum + c.totalDebt);

  Future<void> _showAddCustomer({Customer? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final addressCtrl = TextEditingController(text: existing?.address);
    DateTime? dueDate = existing?.dueDate;

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
              Text(existing == null ? '➕ إضافة عميل' : '✏️ تعديل العميل',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              const SizedBox(height: 16),
              AppTextField(hint: 'اسم العميل *', controller: nameCtrl),
              const SizedBox(height: 10),
              AppTextField(
                  hint: 'رقم الهاتف',
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              AppTextField(hint: 'العنوان', controller: addressCtrl),
              const SizedBox(height: 10),
              // تاريخ الاستحقاق
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: dueDate ?? DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (c, child) => Theme(
                      data: Theme.of(c).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: AppColors.primary,
                          surface: AppColors.darkCard,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setBS(() => dueDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: dueDate != null
                            ? AppColors.warning.withValues(alpha: 0.5)
                            : AppColors.darkBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month,
                          color: dueDate != null ? AppColors.warning : AppColors.textMuted,
                          size: 20),
                      const SizedBox(width: 10),
                      Text(
                        dueDate != null
                            ? '📅 موعد السداد: ${dueDate!.day}/${dueDate!.month}/${dueDate!.year}'
                            : 'تحديد موعد سداد (اختياري)',
                        style: TextStyle(
                            color: dueDate != null ? AppColors.warning : AppColors.textMuted,
                            fontSize: 13),
                      ),
                      const Spacer(),
                      if (dueDate != null)
                        GestureDetector(
                          onTap: () => setBS(() => dueDate = null),
                          child: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                text: existing == null ? 'إضافة' : 'حفظ',
                onTap: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    showSnack(ctx, 'أدخل اسم العميل', isError: true);
                    return;
                  }
                  final Map<String, dynamic> data = {
                    'name': name,
                    'phone': phoneCtrl.text.trim(),
                    'address': addressCtrl.text.trim(),
                    'due_date': dueDate?.toIso8601String(),
                  };
                  if (existing == null) {
                    await context.read<CustomersProvider>().add(data);
                  } else {
                    await context.read<CustomersProvider>().update(existing.id!, data);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadCustomers();
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
    );
  }

  Future<void> _showTransactions(Customer customer) async {
    final transactions =
        await DatabaseHelper.instance.getCustomerTransactions(customer.id!);
    final txList = transactions.map(DebtTransaction.fromMap).toList();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String txType = 'debt';

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scroll) => Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(customer.name,
                              style: const TextStyle(
                                  color: AppColors.textColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: customer.totalDebt > 0
                                  ? AppColors.danger.withValues(alpha: 0.1)
                                  : AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${customer.totalDebt.toStringAsFixed(2)} $_currency',
                              style: TextStyle(
                                  color: customer.totalDebt > 0
                                      ? AppColors.danger
                                      : AppColors.primary,
                                  fontWeight: FontWeight.w800),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: txType == 'debt'
                                      ? AppColors.danger.withValues(alpha: 0.15)
                                      : AppColors.dark,
                                  borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(10)),
                                  border: Border.all(
                                      color: txType == 'debt'
                                          ? AppColors.danger
                                          : AppColors.darkBorder),
                                ),
                                child: const Center(
                                    child: Text('➕ دين',
                                        style: TextStyle(
                                            color: AppColors.danger,
                                            fontWeight: FontWeight.w700))),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setBS(() => txType = 'payment'),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: txType == 'payment'
                                      ? AppColors.primaryLight
                                      : AppColors.dark,
                                  borderRadius: const BorderRadius.horizontal(
                                      left: Radius.circular(10)),
                                  border: Border.all(
                                      color: txType == 'payment'
                                          ? AppColors.primary
                                          : AppColors.darkBorder),
                                ),
                                child: const Center(
                                    child: Text('✅ سداد',
                                        style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700))),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                              child: AppTextField(
                                  hint: 'المبلغ',
                                  controller: amountCtrl,
                                  keyboardType: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: AppTextField(
                                  hint: 'وصف (اختياري)', controller: descCtrl)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final amount = double.tryParse(amountCtrl.text);
                            if (amount == null || amount <= 0) {
                              showSnack(ctx, 'أدخل مبلغاً صحيحاً',
                                  isError: true);
                              return;
                            }
                            await context.read<CustomersProvider>().addTransaction({
                              'customer_id': customer.id,
                              'amount': amount,
                              'type': txType,
                              'description': descCtrl.text.trim(),
                            });
                            amountCtrl.clear();
                            descCtrl.clear();
                            await _loadCustomers();
                            final newTransactions = await DatabaseHelper
                                .instance
                                .getCustomerTransactions(customer.id!);
                            setBS(() {
                              txList.clear();
                              txList.addAll(
                                  newTransactions.map(DebtTransaction.fromMap));
                            });
                            if (ctx.mounted)
                              showSnack(
                                  ctx,
                                  txType == 'debt'
                                      ? 'تم إضافة الدين ✅'
                                      : 'تم تسجيل السداد ✅');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: txType == 'debt'
                                ? AppColors.danger
                                : AppColors.primary,
                          ),
                          child: Text(
                              txType == 'debt' ? 'إضافة دين' : 'تسجيل سداد'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('سجل المعاملات',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    _showStatementOptions(customer, txList),
                                icon:
                                    const Icon(Icons.picture_as_pdf, size: 14),
                                label: const Text('كشف حساب',
                                    style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.warning,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () =>
                                    _printReceipt(customer, txList),
                                icon: const Icon(Icons.receipt_long, size: 14),
                                label: const Text('إيصال',
                                    style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: txList.isEmpty
                      ? const Center(
                          child: Text('لا توجد معاملات بعد',
                              style: TextStyle(color: AppColors.textMuted)))
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
                                border: Border.all(
                                    color: isDebt
                                        ? AppColors.danger
                                            .withValues(alpha: 0.3)
                                        : AppColors.primary
                                            .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Text(isDebt ? '➕' : '✅',
                                      style: const TextStyle(fontSize: 18)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            tx.description ??
                                                (isDebt ? 'دين' : 'سداد'),
                                            style: const TextStyle(
                                                color: AppColors.textLight,
                                                fontSize: 13)),
                                        Text(_formatDate(tx.transactionDate),
                                            style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${isDebt ? '+' : '-'}${tx.amount.toStringAsFixed(2)} $_currency',
                                    style: TextStyle(
                                        color: isDebt
                                            ? AppColors.danger
                                            : AppColors.primary,
                                        fontWeight: FontWeight.w700),
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

  void _showStatementOptions(Customer customer, List<DebtTransaction> txList) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('فترة كشف الحساب',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _periodBtn(ctx, customer, txList, 'شهر', 1),
                _periodBtn(ctx, customer, txList, 'شهرين', 2),
                _periodBtn(ctx, customer, txList, '3 شهور', 3),
                _periodBtn(ctx, customer, txList, 'سنة', 12),
                _periodBtn(ctx, customer, txList, 'الكل', null),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodBtn(BuildContext ctx, Customer customer,
      List<DebtTransaction> txList, String label, int? months) {
    return ActionChip(
      label: Text(label, style: const TextStyle(color: AppColors.textColor)),
      backgroundColor: AppColors.dark,
      side: const BorderSide(color: AppColors.darkBorder),
      onPressed: () {
        Navigator.pop(ctx);
        _printAccountStatement(customer, txList, months);
      },
    );
  }

  Future<void> _printAccountStatement(
      Customer customer, List<DebtTransaction> txList, int? months) async {
    showSnack(context, 'جاري توليد كشف الحساب...');

    final filteredTx = txList.where((tx) {
      if (months == null) return true;
      final limitDate = DateTime.now().subtract(Duration(days: months * 30));
      return tx.transactionDate.isAfter(limitDate);
    }).toList();

    filteredTx.sort((a, b) => a.transactionDate.compareTo(b.transactionDate));

    final pdf = pw.Document();
    final pharmacyName =
        await DatabaseHelper.instance.getSetting('pharmacy_name') ??
            'صيدلي PRO';
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('كشف حساب عميل',
                        style: pw.TextStyle(
                            fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.Text(pharmacyName,
                        style: const pw.TextStyle(
                            fontSize: 14, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('العميل: ${customer.name}',
                        style: pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    if (customer.phone != null && customer.phone!.isNotEmpty)
                      pw.Text('هاتف: ${customer.phone}',
                          style: const pw.TextStyle(
                              fontSize: 12, color: PdfColors.grey700)),
                    pw.Text(
                        'تاريخ التقرير: ${DateFormat('yyyy/MM/dd').format(DateTime.now())}',
                        style: const pw.TextStyle(
                            fontSize: 12, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
                months == null
                    ? 'جميع المعاملات السابقة'
                    : 'المعاملات خلال آخر $months شهر',
                style:
                    const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: ['التاريخ', 'البيان', 'النوع', 'المبلغ']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(h,
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 10)),
                          ))
                      .toList(),
                ),
                ...filteredTx.map((tx) {
                  final isDebt = tx.type == 'debt';
                  return pw.TableRow(
                    children: [
                      _formatDate(tx.transactionDate),
                      tx.description ?? (isDebt ? 'دين' : 'سداد'),
                      isDebt ? 'إضافة دين' : 'سداد دين',
                      '${tx.amount.toStringAsFixed(2)} $_currency',
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
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('الرصيد النهائي المتبقي على العميل:',
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${customer.totalDebt.toStringAsFixed(2)} $_currency',
                      style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: customer.totalDebt > 0
                              ? PdfColors.red700
                              : PdfColors.green700)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Center(
              child: pw.Text('تم إنشاء هذا التقرير بواسطة تطبيق صيدلي PRO',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey500)),
            ),
          ];
        },
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'statement_${customer.name}.pdf');
  }

  Future<void> _printReceipt(
      Customer customer, List<DebtTransaction> txList) async {
    showSnack(context, 'جاري توليد الإيصال...');
    final pdf = pw.Document();
    final pharmacyName =
        await DatabaseHelper.instance.getSetting('pharmacy_name') ??
            'صيدلي PRO';

    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    final lastPayment = txList.firstWhere((t) => t.type == 'payment',
        orElse: () => DebtTransaction(
            customerId: 0,
            amount: 0,
            type: '',
            transactionDate: DateTime.now()));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(12),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(pharmacyName,
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('إيصال ديون عميل',
                  style: const pw.TextStyle(
                      fontSize: 12, color: PdfColors.grey700)),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('العميل:', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text(customer.name,
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('التاريخ:', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text(DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now()),
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 6),
              if (lastPayment.amount > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('آخر سداد:',
                        style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('${lastPayment.amount} $_currency',
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 4),
              ],
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الرصيد المتبقي:',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('${customer.totalDebt} $_currency',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text('تمت الطباعة بواسطة صيدلي PRO',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600)),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'receipt_${customer.name}.pdf');
  }

  Future<void> _launchWhatsApp(String? phone, double debt, String name) async {
    if (phone == null || phone.isEmpty) {
      showSnack(context, 'لا يوجد رقم هاتف مسجل لهذا العميل', isError: true);
      return;
    }
    String formattedPhone = CountryConfig.formatPhone(phone, _countryCode);
    final message = Uri.encodeComponent(
        'مرحباً أ. $name،\nنود تذكيركم بأن الرصيد المتبقي لكم هو ${debt.toStringAsFixed(2)} $_currency.\nشكراً لكم.');
    final url =
        Uri.parse('whatsapp://send?phone=$formattedPhone&text=$message');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      final webUrl = Uri.parse('https://wa.me/$formattedPhone?text=$message');
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) showSnack(context, 'لا يمكن فتح واتساب', isError: true);
      }
    }
  }

  Future<void> _shareDebts() async {
    if (_filtered.isEmpty) {
      showSnack(context, 'لا توجد ديون للمشاركة', isError: true);
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('💰 تقرير المديونيات (${_filtered.length} عملاء):');
    buffer
        .writeln('إجمالي الديون: ${_totalDebt.toStringAsFixed(2)} $_currency');
    buffer.writeln('-------------------');
    for (var c in _filtered) {
      if (c.totalDebt > 0) {
        buffer.writeln('👤 العميل: ${c.name}');
        if (c.phone != null && c.phone!.isNotEmpty)
          buffer.writeln('📱 الهاتف: ${c.phone}');
        buffer.writeln(
            '💵 المديونية: ${c.totalDebt.toStringAsFixed(2)} $_currency');
        buffer.writeln('-------------------');
      }
    }
    await Share.share(buffer.toString());
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null || data.text!.isEmpty) {
      showSnack(context, 'الحافظة فارغة! انسخ التقرير من واتساب أولاً',
          isError: true);
      return;
    }

    final text = data.text!;
    final nameRegex = RegExp(r'👤 العميل:\s*(.*)');
    final phoneRegex = RegExp(r'📱 الهاتف:\s*(.*)');
    final debtRegex = RegExp(r'💵 المديونية:\s*([\d.]+)');

    final blocks = text.split('-------------------');
    int count = 0;

    for (var block in blocks) {
      final nameMatch = nameRegex.firstMatch(block);
      if (nameMatch != null) {
        final name = nameMatch.group(1)?.trim() ?? '';
        if (name.isEmpty) continue;

        final phoneMatch = phoneRegex.firstMatch(block);
        final phone = phoneMatch?.group(1)?.trim() ?? '';

        final debtMatch = debtRegex.firstMatch(block);
        final debtStr = debtMatch?.group(1) ?? '0';
        final totalDebt = double.tryParse(debtStr) ?? 0.0;

        if (totalDebt <= 0) continue;

        Customer? existing;
        for (var c in _customers) {
          if (c.name == name) {
            existing = c;
            break;
          }
        }

        int customerId;
        double currentTotalDebt = 0;
        if (existing != null) {
          customerId = existing.id!;
          currentTotalDebt = existing.totalDebt;
        } else {
          customerId = await DatabaseHelper.instance.insertCustomer({
            'name': name,
            'phone': phone,
            'address': '',
          });
        }

        // Calculate difference
        final amountToUpdate = totalDebt - currentTotalDebt;

        if (amountToUpdate != 0) {
          await context.read<CustomersProvider>().addTransaction({
            'customer_id': customerId,
            'amount': amountToUpdate.abs(),
            'type': amountToUpdate > 0 ? 'debt' : 'payment',
            'description': 'استيراد/مزامنة من المساعد',
          });
        }

        count++;
      }
    }

    if (count > 0) {
      await _loadCustomers();
      if (mounted) showSnack(context, 'تم استيراد ديون $count عملاء بنجاح ✅');
    } else {
      if (mounted)
        showSnack(context, 'لم يتم العثور على ديون متوافقة في النص المنسوخ',
            isError: true);
    }
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
                  colors: [
                    AppColors.danger.withValues(alpha: 0.2),
                    AppColors.darkCard
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('💰', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إجمالي الديون',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      Text('${_totalDebt.toStringAsFixed(2)} $_currency',
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                      Text('${_customers.length} عميل',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.paste_rounded, color: Colors.white),
                    tooltip: 'إضافة من رسالة المساعد',
                    style: IconButton.styleFrom(
                        backgroundColor:
                            AppColors.warning.withValues(alpha: 0.2)),
                    onPressed: _importFromClipboard,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white),
                    tooltip: 'مشاركة التقرير مع المدير',
                    style: IconButton.styleFrom(
                        backgroundColor:
                            AppColors.accent.withValues(alpha: 0.2)),
                    onPressed: _shareDebts,
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
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
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
                          itemBuilder: (ctx, i) =>
                              _buildCustomerCard(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCustomer(),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('إضافة عميل',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo')),
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
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(14)),
            ),
            SlidableAction(
              onPressed: (_) async {
                final confirm = await showDeleteDialog(context, customer.name);
                if (confirm == true) {
                  await context.read<CustomersProvider>().delete(customer.id!);
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
              border: Border.all(
                  color: customer.totalDebt > 0
                      ? AppColors.danger.withValues(alpha: 0.3)
                      : AppColors.darkBorder),
            ),
            child: Row(
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
                      child: Text(customer.name[0],
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
                      Text(customer.name,
                          style: const TextStyle(
                              color: AppColors.textColor,
                              fontWeight: FontWeight.w700)),
                      if (customer.phone != null && customer.phone!.isNotEmpty)
                        Text(customer.phone!,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${customer.totalDebt.toStringAsFixed(2)} $_currency',
                      style: TextStyle(
                        color: customer.totalDebt > 0
                            ? AppColors.danger
                            : AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(customer.totalDebt > 0 ? 'دين متبقي' : 'لا يوجد دين',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Colors.green),
                  tooltip: 'إرسال عبر واتساب',
                  onPressed: () => _launchWhatsApp(
                      customer.phone, customer.totalDebt, customer.name),
                ),
                const Icon(Icons.chevron_left,
                    color: AppColors.textMuted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
