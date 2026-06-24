import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../utils/country_config.dart';
import '../widgets/common_widgets.dart';
import 'package:provider/provider.dart';
import '../providers/app_providers.dart';
import '../providers/current_user_provider.dart';

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
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    // تحديث تلقائي كل 30 ثانية
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadCustomers();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
    // فحص صلاحية إضافة/تعديل الديون
    final userProvider = context.read<CurrentUserProvider>();
    if (existing == null && !userProvider.canAddDebt) {
      showSnack(context, '⛔ ليس لديك صلاحية إضافة عملاء', isError: true);
      return;
    }
    if (existing != null && !userProvider.canEditDebt) {
      showSnack(context, '⛔ ليس لديك صلاحية تعديل العملاء', isError: true);
      return;
    }
    final nameCtrl = TextEditingController(text: existing?.name);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final addressCtrl = TextEditingController(text: existing?.address);
    DateTime? dueDate = existing?.dueDate;
    String? photoPath = existing?.photoUrl;
    bool isUploading = false;

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
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (picked != null) {
                      setBS(() => photoPath = picked.path);
                    }
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.dark,
                    backgroundImage: photoPath != null && !photoPath!.startsWith('http') 
                        ? FileImage(File(photoPath!)) as ImageProvider
                        : (photoPath != null ? NetworkImage(photoPath!) : null),
                    child: photoPath == null 
                        ? const Icon(Icons.camera_alt, color: AppColors.textMuted, size: 30) 
                        : null,
                  ),
                ),
              ),
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
                            ? AppColors.warning.withOpacity(0.5)
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
              isUploading
                  ? const Center(child: CircularProgressIndicator())
                  : PrimaryButton(
                      text: existing == null ? 'إضافة' : 'حفظ',
                      onTap: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          showSnack(ctx, 'أدخل اسم العميل', isError: true);
                          return;
                        }
                        
                        setBS(() => isUploading = true);
                        
                        final Map<String, dynamic> data = {
                          'name': name,
                          'phone': phoneCtrl.text.trim(),
                          'address': addressCtrl.text.trim(),
                          'due_date': dueDate?.toIso8601String(),
                          'photo_url': photoPath,
                        };
                        if (existing == null) {
                          await context.read<CustomersProvider>().add(data);
                        } else {
                          await context.read<CustomersProvider>().update(existing.id!, data);
                        }
                        // تسجيل النشاط
                        await DatabaseHelper.instance.logActivity(
                          assistantId: userProvider.currentAssistantId,
                          assistantName: userProvider.currentName,
                          action: existing == null ? 'إضافة عميل' : 'تعديل عميل',
                          details: '${existing == null ? "تم إضافة" : "تم تعديل"} العميل: $name',
                          screen: 'debts',
                        );
                        
                        if (ctx.mounted) {
                          setBS(() => isUploading = false);
                          Navigator.pop(ctx);
                        }
                        
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
    String? receiptPath;
    bool isUploading = false;

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
                                  ? AppColors.danger.withOpacity(0.1)
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
                                      ? AppColors.danger.withOpacity(0.15)
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
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                                if (picked != null) {
                                  setBS(() => receiptPath = picked.path);
                                }
                              },
                              icon: Icon(receiptPath == null ? Icons.add_photo_alternate : Icons.check_circle, 
                                  color: receiptPath == null ? AppColors.textLight : Colors.green, size: 18),
                              label: Text(receiptPath == null ? 'إرفاق إيصال' : 'تم الإرفاق', 
                                  style: TextStyle(color: receiptPath == null ? AppColors.textLight : Colors.green)),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: receiptPath == null ? AppColors.darkBorder : Colors.green),
                              ),
                            ),
                          ),
                          if (receiptPath != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => setBS(() => receiptPath = null),
                              icon: const Icon(Icons.delete, color: AppColors.danger),
                              tooltip: 'حذف الإيصال',
                            ),
                          ]
                        ],
                      ),
                      const SizedBox(height: 10),
                      isUploading
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final userProvider = context.read<CurrentUserProvider>();
                            final amount = double.tryParse(amountCtrl.text);
                            if (amount == null || amount <= 0) {
                              showSnack(ctx, 'أدخل مبلغاً صحيحاً',
                                  isError: true);
                              return;
                            }
                            // فحص صلاحية إضافة دين
                            if (txType == 'debt' && !userProvider.canAddDebt) {
                              showSnack(ctx, '⛔ ليس لديك صلاحية إضافة ديون', isError: true);
                              return;
                            }
                            
                            setBS(() => isUploading = true);
                            
                            await context.read<CustomersProvider>().addTransaction({
                              'customer_id': customer.id,
                              'amount': amount,
                              'type': txType,
                              'description': descCtrl.text.trim(),
                              'receipt_url': receiptPath,
                            });
                            // تسجيل النشاط
                            await DatabaseHelper.instance.logActivity(
                              assistantId: userProvider.currentAssistantId,
                              assistantName: userProvider.currentName,
                              action: txType == 'debt' ? 'إضافة دين' : 'تسجيل سداد',
                              details: '${txType == 'debt' ? 'دين' : 'سداد'}: $amount - العميل: ${customer.name}',
                              screen: 'debts',
                            );
                            amountCtrl.clear();
                            descCtrl.clear();
                            await _loadCustomers();
                            final newTransactions = await DatabaseHelper
                                .instance
                                .getCustomerTransactions(customer.id!);
                            setBS(() {
                              isUploading = false;
                              receiptPath = null;
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
                                            .withOpacity(0.3)
                                        : AppColors.primary
                                            .withOpacity(0.3)),
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
                                        if (tx.createdBy != null && tx.createdBy!.isNotEmpty)
                                          Row(
                                            children: [
                                              const Icon(Icons.person_outline_rounded,
                                                  color: AppColors.accent, size: 11),
                                              const SizedBox(width: 2),
                                              Text('سجّله: ${tx.createdBy}',
                                                  style: const TextStyle(
                                                      color: AppColors.accent,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600)),
                                            ],
                                          ),
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

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('خيارات إيصال الديون 🧾', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: const Text(
          'اختر طريقة تصدير أو طباعة إيصال الديون:',
          style: TextStyle(color: AppColors.textLight, fontFamily: 'Cairo', fontSize: 13),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowButtonSpacing: 8,
        actions: [
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await Printing.layoutPdf(
                  onLayout: (format) async => pdf.save(),
                  name: 'receipt_${customer.name}.pdf');
            },
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('طباعة حرارية 🖨️', style: TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              minimumSize: const Size(200, 42),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await Printing.sharePdf(
                  bytes: await pdf.save(), filename: 'receipt_${customer.name}.pdf');
            },
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('مشاركة الإيصال 📄', style: TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(200, 42),
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

  Future<void> _launchWhatsApp(String? phone, double debt, String name) async {
    if (phone == null || phone.isEmpty) {
      showSnack(context, 'لا يوجد رقم هاتف مسجل لهذا العميل', isError: true);
      return;
    }
    String formattedPhone = CountryConfig.formatPhone(phone, _countryCode);
    final message = Uri.encodeComponent(
        'مرحباً أ. $name،\nنود تذكيركم بأن الرصيد المتبقي عليكم هو ${debt.toStringAsFixed(2)} $_currency.\nشكراً لكم.');
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
    // حساب المتأخرات (ديون تجاوز تاريخ سدادها)
    final now = DateTime.now();
    final overdueDebt = _customers
        .where((c) => c.totalDebt > 0 && c.dueDate != null && c.dueDate!.isBefore(now))
        .fold(0.0, (sum, c) => sum + c.totalDebt);

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Column(
        children: [
          // Top Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Badges / Status pills (Left side under RTL)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24), // Gold
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'المالك',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'احترافي',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Logo and Title (Right side under RTL)
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.primary, width: 1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'صيدلي',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Cairo'),
                              ),
                            ],
                          ),
                          const Text(
                            'ديون العملاء',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 1.5),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.eco_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Combined Stats Bar
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Row(
              children: [
                // 1. العملاء
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_customers.length}',
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800),
                          ),
                          const Text(
                            'العملاء',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 14),
                      ),
                    ],
                  ),
                ),
                // Divider
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.darkBorder,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                ),

                // 2. إجمالي الديون
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _totalDebt.toStringAsFixed(2),
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800),
                          ),
                          const Text(
                            'إجمالي الديون',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.accent, size: 14),
                      ),
                    ],
                  ),
                ),
                // Divider
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.darkBorder,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                ),

                // 3. المتأخرات
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            overdueDebt.toStringAsFixed(2),
                            style: TextStyle(
                                color: overdueDebt > 0 ? AppColors.warning : AppColors.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800),
                          ),
                          const Text(
                            'المتأخرات',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.access_time_rounded, color: AppColors.warning, size: 14),
                      ),
                    ],
                  ),
                ),
                // Divider
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.darkBorder,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                ),

                // 4. أزرار البحث والفلترة
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.darkCard,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: const Text('بحث', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo')),
                            content: TextField(
                              autofocus: true,
                              onChanged: (v) => setState(() => _search = v),
                              style: const TextStyle(color: AppColors.textColor),
                              decoration: const InputDecoration(
                                hintText: 'ابحث عن عميل...',
                                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
                              ),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('إغلاق', style: TextStyle(color: AppColors.primary, fontFamily: 'Cairo'))),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.dark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: const Icon(Icons.search, color: AppColors.textMuted, size: 15),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.dark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 15),
                        color: AppColors.darkCard,
                        tooltip: 'خيارات',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'share',
                              child: Row(children: [
                                Icon(Icons.share_rounded, color: AppColors.primary, size: 16),
                                SizedBox(width: 8),
                                Text('مشاركة التقرير', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 13)),
                              ])),
                          const PopupMenuItem(
                              value: 'import',
                              child: Row(children: [
                                Icon(Icons.paste_rounded, color: AppColors.warning, size: 16),
                                SizedBox(width: 8),
                                Text('استيراد من الحافظة', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 13)),
                              ])),
                        ],
                        onSelected: (v) {
                          if (v == 'share') _shareDebts();
                          if (v == 'import') _importFromClipboard();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // قسم إضافة عميل جديد
          _AddCustomerInlineSection(onAdd: _showAddCustomer),

          const SizedBox(height: 8),

          // عملاء سريعة + قائمة العملاء
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : Column(
                    children: [
                      // عملاء سريعة
                      if (_customers.isNotEmpty)
                        _QuickCustomersRow(
                          customers: _customers,
                          onTap: (c) => _showTransactions(c),
                          onAdd: () => _showAddCustomer(),
                        ),

                      // رأس قائمة العملاء
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.swap_vert_rounded, color: AppColors.textMuted, size: 16),
                                const SizedBox(width: 4),
                                const Text('الأحدث', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text('قائمة العملاء',
                                    style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text('${_filtered.length}',
                                      style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // قائمة العملاء
                      Expanded(
                        child: _filtered.isEmpty
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
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                                  itemCount: _filtered.length,
                                  itemBuilder: (ctx, i) => _buildCustomerCard(_filtered[i]),
                                ),
                              ),
                      ),

                      // زر إضافة عميل بسرعة في الأسفل
                      GestureDetector(
                        onTap: () => _showAddCustomer(),
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.darkCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add, color: AppColors.primary, size: 18),
                              SizedBox(width: 6),
                              Text('إضافة عميل بسرعة',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo')),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(Customer customer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) {
                final userProvider = context.read<CurrentUserProvider>();
                if (!userProvider.canEditDebt) {
                  showSnack(context, '⛔ ليس لديك صلاحية التعديل', isError: true);
                  return;
                }
                _showAddCustomer(existing: customer);
              },
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              icon: Icons.edit_rounded,
              label: 'تعديل',
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
            ),
            SlidableAction(
              onPressed: (_) async {
                final userProvider = context.read<CurrentUserProvider>();
                if (!userProvider.canDelete) {
                  showSnack(context, '⛔ ليس لديك صلاحية الحذف', isError: true);
                  return;
                }
                final confirm = await showDeleteDialog(context, customer.name);
                if (confirm == true) {
                  await context.read<CustomersProvider>().delete(customer.id!);
                  await DatabaseHelper.instance.logActivity(
                    assistantId: userProvider.currentAssistantId,
                    assistantName: userProvider.currentName,
                    action: 'حذف عميل',
                    details: 'تم حذف العميل: ${customer.name}',
                    screen: 'debts',
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: customer.totalDebt > 0
                    ? AppColors.danger.withOpacity(0.25)
                    : AppColors.darkBorder),
          ),
          child: Row(
            children: [
              // أيقونة العميل
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  image: customer.photoUrl != null && customer.photoUrl!.isNotEmpty
                      ? DecorationImage(
                          image: customer.photoUrl!.startsWith('http')
                              ? NetworkImage(customer.photoUrl!) as ImageProvider
                              : FileImage(File(customer.photoUrl!)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: customer.photoUrl == null || customer.photoUrl!.isEmpty
                    ? Center(
                        child: Text(
                          customer.name[0],
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              fontFamily: 'Cairo'),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),

              // معلومات العميل
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name,
                        style: const TextStyle(
                            color: AppColors.textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    if (customer.address != null && customer.address!.isNotEmpty)
                      Text(customer.address!,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    if (customer.phone != null && customer.phone!.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined, color: AppColors.textMuted, size: 11),
                          const SizedBox(width: 2),
                          Text(customer.phone!,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // زر +
              _ActionBtn(
                icon: Icons.add,
                color: AppColors.primary,
                onTap: () async {
                  final userProvider = context.read<CurrentUserProvider>();
                  if (!userProvider.canAddDebt) {
                    showSnack(context, '⛔ ليس لديك صلاحية إضافة ديون', isError: true);
                    return;
                  }
                  final ctrl = TextEditingController();
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.darkCard,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text('إضافة دين - ${customer.name}',
                          style: const TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 14)),
                      content: AppTextField(hint: 'المبلغ', controller: ctrl, keyboardType: TextInputType.number),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo'))),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                          child: const Text('إضافة', style: TextStyle(fontFamily: 'Cairo')),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final amount = double.tryParse(ctrl.text);
                    if (amount != null && amount > 0) {
                      await context.read<CustomersProvider>().addTransaction({
                        'customer_id': customer.id,
                        'amount': amount,
                        'type': 'debt',
                        'description': 'إضافة دين',
                      });
                      await DatabaseHelper.instance.logActivity(
                        assistantId: userProvider.currentAssistantId,
                        assistantName: userProvider.currentName,
                        action: 'إضافة دين',
                        details: 'دين: $amount - العميل: ${customer.name}',
                        screen: 'debts',
                      );
                      await _loadCustomers();
                      if (mounted) showSnack(context, 'تم إضافة الدين ✅');
                    }
                  }
                },
              ),
              const SizedBox(width: 8),

              // المبلغ
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    customer.totalDebt.toStringAsFixed(2),
                    style: TextStyle(
                      color: customer.totalDebt > 0 ? AppColors.danger : AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(_currency,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
              const SizedBox(width: 8),

              // زر -
              _ActionBtn(
                icon: Icons.remove,
                color: AppColors.textMuted,
                onTap: () => _showTransactions(customer),
              ),
              const SizedBox(width: 8),

              // زر دفع
              GestureDetector(
                onTap: () async {
                  final ctrl = TextEditingController();
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.darkCard,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text('تسجيل دفع - ${customer.name}',
                          style: const TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 14)),
                      content: AppTextField(
                          hint: 'المبلغ المدفوع', controller: ctrl, keyboardType: TextInputType.number),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo'))),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('تسجيل', style: TextStyle(fontFamily: 'Cairo')),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final amount = double.tryParse(ctrl.text);
                    final userProvider = context.read<CurrentUserProvider>();
                    if (amount != null && amount > 0) {
                      await context.read<CustomersProvider>().addTransaction({
                        'customer_id': customer.id,
                        'amount': amount,
                        'type': 'payment',
                        'description': 'سداد',
                      });
                      await DatabaseHelper.instance.logActivity(
                        assistantId: userProvider.currentAssistantId,
                        assistantName: userProvider.currentName,
                        action: 'تسجيل سداد',
                        details: 'سداد: $amount - العميل: ${customer.name}',
                        screen: 'debts',
                      );
                      await _loadCustomers();
                      if (mounted) showSnack(context, 'تم تسجيل السداد ✅');
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                  ),
                  child: const Text('دفع',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo')),
                ),
              ),
              const SizedBox(width: 4),

              // زر ⋮
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 18),
                color: AppColors.darkCard,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.zero,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'details',
                      child: Row(children: [
                        Icon(Icons.receipt_long, color: AppColors.primary, size: 16),
                        SizedBox(width: 8),
                        Text('التفاصيل', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo')),
                      ])),
                  const PopupMenuItem(
                      value: 'whatsapp',
                      child: Row(children: [
                        Icon(Icons.chat_bubble_outline_rounded, color: Colors.green, size: 16),
                        SizedBox(width: 8),
                        Text('واتساب', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo')),
                      ])),
                  const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_rounded, color: AppColors.accent, size: 16),
                        SizedBox(width: 8),
                        Text('تعديل', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo')),
                      ])),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_rounded, color: AppColors.danger, size: 16),
                        SizedBox(width: 8),
                        Text('حذف', style: TextStyle(color: AppColors.danger, fontFamily: 'Cairo')),
                      ])),
                ],
                onSelected: (v) async {
                  final userProvider = context.read<CurrentUserProvider>();
                  if (v == 'details') {
                    _showTransactions(customer);
                  } else if (v == 'whatsapp') {
                    _launchWhatsApp(customer.phone, customer.totalDebt, customer.name);
                  } else if (v == 'edit') {
                    if (!userProvider.canEditDebt) {
                      showSnack(context, '⛔ ليس لديك صلاحية التعديل', isError: true);
                      return;
                    }
                    _showAddCustomer(existing: customer);
                  } else if (v == 'delete') {
                    if (!userProvider.canDelete) {
                      showSnack(context, '⛔ ليس لديك صلاحية الحذف', isError: true);
                      return;
                    }
                    final confirm = await showDeleteDialog(context, customer.name);
                    if (confirm == true) {
                      await context.read<CustomersProvider>().delete(customer.id!);
                      await DatabaseHelper.instance.logActivity(
                        assistantId: userProvider.currentAssistantId,
                        assistantName: userProvider.currentName,
                        action: 'حذف عميل',
                        details: 'تم حذف العميل: ${customer.name}',
                        screen: 'debts',
                      );
                      if (mounted) showSnack(context, 'تم الحذف');
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget: قسم إضافة عميل جديد inline ──────────────────────────────────────
class _AddCustomerInlineSection extends StatefulWidget {
  final Future<void> Function({Customer? existing}) onAdd;
  const _AddCustomerInlineSection({required this.onAdd});

  @override
  State<_AddCustomerInlineSection> createState() => _AddCustomerInlineSectionState();
}

class _AddCustomerInlineSectionState extends State<_AddCustomerInlineSection> {
  int _step = 1;
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String get _currentHint {
    if (_step == 1) return 'اكتب اسم العميل...';
    if (_step == 2) return 'اكتب العنوان...';
    return 'اكتب رقم الهاتف...';
  }

  TextEditingController get _currentCtrl {
    if (_step == 1) return _nameCtrl;
    if (_step == 2) return _addressCtrl;
    return _phoneCtrl;
  }

  TextInputType get _currentKeyboard {
    if (_step == 3) return TextInputType.phone;
    return TextInputType.text;
  }

  void _nextStep() {
    if (_step == 1 && _nameCtrl.text.trim().isEmpty) return;
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    await widget.onAdd();
    setState(() {
      _step = 1;
      _nameCtrl.clear();
      _addressCtrl.clear();
      _phoneCtrl.clear();
    });
  }

  Widget _buildStepItem(int step, String label) {
    final isActive = _step == step;
    final isDone = _step > step;
    final color = isActive || isDone ? AppColors.primary : AppColors.textMuted;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color,
              width: 1,
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, color: AppColors.primary, size: 10)
                : Text(
                    '$step',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: isActive || isDone ? FontWeight.w700 : FontWeight.normal,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

  IconData get _currentIcon {
    if (_step == 1) return Icons.person_rounded;
    if (_step == 2) return Icons.location_on_rounded;
    return Icons.phone_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // خطوات
              Expanded(
                child: Row(
                  children: [
                    _buildStepItem(1, 'اسم العميل'),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: CustomPaint(
                          size: const Size(double.infinity, 1),
                          painter: _DashedLinePainter(
                            color: _step > 1 ? AppColors.primary.withOpacity(0.5) : AppColors.darkBorder,
                          ),
                        ),
                      ),
                    ),
                    _buildStepItem(2, 'العنوان'),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: CustomPaint(
                          size: const Size(double.infinity, 1),
                          painter: _DashedLinePainter(
                            color: _step > 2 ? AppColors.primary.withOpacity(0.5) : AppColors.darkBorder,
                          ),
                        ),
                      ),
                    ),
                    _buildStepItem(3, 'رقم الهاتف'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // عنوان
              Row(
                children: [
                  const Text('إضافة عميل جديد',
                      style: TextStyle(
                          color: AppColors.textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: AppColors.primary, size: 16),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _currentCtrl,
            keyboardType: _currentKeyboard,
            textDirection: ui.TextDirection.rtl,
            style: const TextStyle(color: AppColors.textColor, fontFamily: 'Cairo'),
            onSubmitted: (_) => _nextStep(),
            decoration: InputDecoration(
              hintText: _currentHint,
              hintStyle: const TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo'),
              filled: true,
              fillColor: AppColors.dark,
              suffixIcon: Icon(_currentIcon, color: AppColors.primary, size: 20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.darkBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.darkBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'اضغط Enter من الكيبورد للمتابعة',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget: عملاء سريعة ──────────────────────────────────────────────────────
class _QuickCustomersRow extends StatelessWidget {
  final List<Customer> customers;
  final void Function(Customer) onTap;
  final VoidCallback onAdd;

  const _QuickCustomersRow({
    required this.customers,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final recent = customers.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.flash_on_rounded, color: AppColors.warning, size: 14),
              const SizedBox(width: 4),
              const Text('عملاء سريعة',
                  style: TextStyle(
                      color: AppColors.textColor, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: AppColors.primary, size: 14),
                        SizedBox(width: 3),
                        Text('إضافة',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ),
                ...recent.map((c) => GestureDetector(
                      onTap: () => onTap(c),
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.dark,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: Text(c.name.split(' ').first,
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontSize: 12,
                                fontFamily: 'Cairo')),
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ── Widget: زر إجراء صغير ────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    const double dashWidth = 3;
    const double dashSpace = 2;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, size.height / 2), Offset(startX + dashWidth, size.height / 2), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

