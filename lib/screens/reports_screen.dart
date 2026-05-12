import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../providers/current_user_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, int> _stats = {};
  double _totalDebt = 0;
  List<int> _weeklyData = [0, 0, 0, 0];
  bool _loading = true;
  String _currency = 'ج.م';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final stats = await DatabaseHelper.instance.getShortageStats();
    final debt = await DatabaseHelper.instance.getTotalDebt();
    final currency = await DatabaseHelper.instance.getCurrency();
    final weeklyData = await DatabaseHelper.instance.getWeeklyShortages();
    if (mounted) {
      setState(() {
        _stats = stats;
        _totalDebt = debt;
        _currency = currency;
        _weeklyData = weeklyData;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // فحص صلاحية عرض التقارير
    final userProvider = context.watch<CurrentUserProvider>();
    if (!userProvider.canViewReports) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🔒', style: TextStyle(fontSize: 50)),
            SizedBox(height: 12),
            Text('غير مصرح لك',
                style: TextStyle(
                    color: AppColors.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('ليس لديك صلاحية عرض التقارير',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));

    final total = _stats['total'] ?? 0;
    final covered = _stats['covered'] ?? 0;
    final rate = total > 0 ? (covered / total * 100).toStringAsFixed(0) : '0';

    final weeks = ['الأسبوع 1', 'الأسبوع 2', 'الأسبوع 3', 'الأسبوع 4'];
    final values = _weeklyData;
    final maxVal = values.isNotEmpty ? values.reduce((a, b) => a > b ? a : b) : 0;

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.darkCard,
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Monthly Summary
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryDark, Color(0xFF004D38)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('التقرير الشهري - ${_monthName()}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Text('$total ناقص',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _summaryItem('$rate%', 'معدل التغطية'),
                    const SizedBox(width: 24),
                    _summaryItem('${_totalDebt.toStringAsFixed(0)} $_currency',
                        'إجمالي الديون'),
                    const SizedBox(width: 24),
                    _summaryItem('$covered صنف', 'تمت تغطيته'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bar Chart
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📊 النواقص الأسبوعية',
                    style: TextStyle(
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                        4,
                        (i) => Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text('${values[i]}',
                                        style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11)),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: maxVal > 0
                                          ? (values[i] / maxVal * 80)
                                          : 10,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            AppColors.primary,
                                            AppColors.primaryDark
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(6)),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(weeks[i],
                                        style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 10),
                                        textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            )),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Status breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📦 توزيع الحالات',
                    style: TextStyle(
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final entry in [
                  ('تمت التغطية', _stats['covered'] ?? 0, AppColors.primary),
                  ('عروض موصولة', _stats['offered'] ?? 0, Color(0xFF2563EB)),
                  ('بانتظار رد', _stats['pending'] ?? 0, AppColors.warning),
                  ('مستعصية', _stats['stubborn'] ?? 0, AppColors.danger),
                ]) ...[
                  Row(
                    children: [
                      SizedBox(
                          width: 100,
                          child: Text(entry.$1,
                              style: const TextStyle(
                                  color: AppColors.textLight, fontSize: 13))),
                      Expanded(
                        child: GradientProgressBar(
                            value: total > 0 ? entry.$2 / total : 0),
                      ),
                      const SizedBox(width: 8),
                      Text('${entry.$2}',
                          style: TextStyle(
                              color: entry.$3, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Export buttons
          const Text('📤 تصدير التقارير',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _exportPDF,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger.withValues(alpha: 0.8)),
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                  label: const Text('تصدير PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _exportExcel,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF217346)),
                  icon: const Icon(Icons.table_chart, color: Colors.white),
                  label: const Text('تصدير Excel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      );

  Future<void> _exportPDF() async {
    showSnack(context, 'جاري تجهيز PDF...');
    final pdf = pw.Document();
    final shortages = await DatabaseHelper.instance.getShortages();
    final pharmacyName =
        await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدليتي';

    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
      textDirection: pw.TextDirection.rtl,
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('التقرير الشهري',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(pharmacyName,
                      style: const pw.TextStyle(
                          fontSize: 14, color: PdfColors.grey700)),
                ],
              ),
              pw.Text('التاريخ: ${_formatDate(DateTime.now())}',
                  style: const pw.TextStyle(
                      fontSize: 12, color: PdfColors.grey700)),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text('إحصائيات الشهر',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('إجمالي النواقص: ${_stats['total'] ?? 0}'),
          pw.Text('تمت التغطية: ${_stats['covered'] ?? 0}'),
          pw.Text('إجمالي الديون: $_totalDebt $_currency'),
          pw.SizedBox(height: 20),
          pw.Text('سجل النواقص',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: ['الصنف', 'الشركة', 'الكمية', 'الحالة']
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(h,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 10)),
                        ))
                    .toList(),
              ),
              ...shortages.take(50).map((item) => pw.TableRow(
                    children: [
                      item['name'].toString(),
                      item['company'].toString(),
                      item['quantity'].toString(),
                      item['status'].toString(),
                    ]
                        .map((t) => pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(t,
                                  style: const pw.TextStyle(fontSize: 10)),
                            ))
                        .toList(),
                  )),
            ],
          ),
        ],
      ),
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _exportExcel() async {
    showSnack(context, 'جاري تجهيز Excel...');
    try {
      var excel = Excel.createExcel();

      // Sheet 1: النواقص
      var shortagesSheet = excel['النواقص'];
      excel.setDefaultSheet('النواقص');
      shortagesSheet.appendRow([
        TextCellValue('ID'),
        TextCellValue('الصنف'),
        TextCellValue('الشركة'),
        TextCellValue('الكمية'),
        TextCellValue('الحالة'),
        TextCellValue('التاريخ')
      ]);

      final shortages = await DatabaseHelper.instance.getShortages();
      for (var s in shortages) {
        shortagesSheet.appendRow([
          TextCellValue(s['id'].toString()),
          TextCellValue(s['name'].toString()),
          TextCellValue(s['company'].toString()),
          TextCellValue(s['quantity'].toString()),
          TextCellValue(s['status'].toString()),
          TextCellValue(s['created_at'].toString()),
        ]);
      }

      // Sheet 2: الديون
      var debtsSheet = excel['الديون'];
      debtsSheet.appendRow([
        TextCellValue('ID'),
        TextCellValue('العميل'),
        TextCellValue('رقم الهاتف'),
        TextCellValue('العنوان'),
        TextCellValue('إجمالي الدين')
      ]);

      final customers = await DatabaseHelper.instance.getCustomers();
      for (var c in customers) {
        debtsSheet.appendRow([
          TextCellValue(c['id'].toString()),
          TextCellValue(c['name'].toString()),
          TextCellValue(c['phone']?.toString() ?? ''),
          TextCellValue(c['address']?.toString() ?? ''),
          TextCellValue(c['total_debt'].toString()),
        ]);
      }

      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/saydali_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(path);
      await file.writeAsBytes(excel.save()!);

      await Share.shareXFiles([XFile(path)], text: 'تقرير صيدلي PRO');
    } catch (e) {
      if (mounted) showSnack(context, 'حدث خطأ أثناء التصدير: $e');
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  String _monthName() {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    return '${months[DateTime.now().month - 1]} ${DateTime.now().year}';
  }
}
