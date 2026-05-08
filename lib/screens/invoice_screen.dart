import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});
  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  List<Map<String, dynamic>> _invoices = [];
  bool _loading = true;
  String _currency = 'ج.م';

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _createInvoice() async {
    final nameCtrl = TextEditingController();
    final items = <Map<String, dynamic>>[];
    double discount = 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) {
          double subtotal = items.fold(0, (s, i) => s + (i['price'] * i['qty']));
          double total = subtotal - (subtotal * discount / 100);

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
                        AppTextField(
                            hint: 'اسم العميل',
                            controller: nameCtrl),
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
                                            '${item['qty']} × ${item['price'].toStringAsFixed(2)} $_currency',
                                            style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${(item['qty'] * item['price']).toStringAsFixed(2)}',
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
                                    // Clamp discount between 0 and 100
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
                                'customer_name': nameCtrl.text.trim(),
                                'items': jsonEncode(items),
                                'subtotal': subtotal,
                                'discount': discount,
                                'total': total,
                              });
                              await _generatePDF(
                                  nameCtrl.text.trim(), items, subtotal,
                                  discount, total);
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _load();
                              if (mounted)
                                showSnack(context, 'تم حفظ الفاتورة ✅');
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

  void _addItem(
      BuildContext ctx, List<Map<String, dynamic>> items, StateSetter setBS) {
    final itemNameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('إضافة صنف',
            style: TextStyle(color: AppColors.primary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(hint: 'اسم الصنف', controller: itemNameCtrl),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: AppTextField(
                        hint: 'السعر',
                        controller: priceCtrl,
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: AppTextField(
                        hint: 'الكمية',
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('إلغاء',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = itemNameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text) ?? 0;
              // Validate and clamp quantity between 1 and 9999
              final rawQty = int.tryParse(qtyCtrl.text) ?? 1;
              final qty = rawQty.clamp(1, 9999);
              if (name.isEmpty || price <= 0) return;
              setBS(() => items.add({
                    'name': name,
                    'price': price,
                    'qty': qty,
                  }));
              Navigator.pop(dCtx);
            },
            child: const Text('إضافة'),
          ),
        ],
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
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1.5),
                  4: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey200),
                    children: ['#', 'الصنف', 'الكمية', 'السعر', 'الإجمالي']
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
                    final lineTotal = item['price'] * item['qty'];
                    return pw.TableRow(
                      children: [
                        '${i + 1}',
                        item['name'],
                        '${item['qty']}',
                        '${item['price'].toStringAsFixed(2)}',
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
                              color:
                                  AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                                child:
                                    Text('🧾', style: TextStyle(fontSize: 20))),
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
                                    DateFormat('yyyy/MM/dd HH:mm')
                                        .format(date),
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11),
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
                            ],
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.share,
                                color: AppColors.primary, size: 20),
                            onPressed: () async {
                              final items = (jsonDecode(inv['items'])
                                      as List)
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
                    );
                  },
                ),
    );
  }
}
