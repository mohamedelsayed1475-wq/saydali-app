import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/supabase_service.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class RepResponseScreen extends StatefulWidget {
  const RepResponseScreen({super.key});

  @override
  State<RepResponseScreen> createState() => _RepResponseScreenState();
}

class _RepResponseScreenState extends State<RepResponseScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  RepResponse? _response;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchResponse() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length != 8) {
      setState(() => _error = 'الكود يجب أن يكون 8 أحرف');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final response = await SupabaseService.instance.fetchResponseByCode(code);

    if (mounted) {
      setState(() {
        _loading = false;
        if (response != null) {
          _response = response;
        } else {
          _error = 'كود غير صحيح أو منتهي الصلاحية';
        }
      });
    }
  }

  Future<void> _finishDay() async {
    if (_response == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تأكيد إنهاء اليوم', style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700)),
        content: Text(
          'سيتم:\n✅ تغطية ${_response!.availableItems.length} صنف متاح\n⚠️ تحويل ${_response!.unavailableItems.length} صنف لمستعصي',
          style: const TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirm != true) return;

    final db = DatabaseHelper.instance;

    // الأصناف المتاحة → covered (بالبحث بالاسم)
    for (final item in _response!.availableItems) {
      final shortages = await db.getShortages();
      for (final s in shortages) {
        final name = (s['name'] as String).trim().toLowerCase();
        final itemName = item.drugName.trim().toLowerCase();
        if (name == itemName) {
          await db.updateShortage(s['id'] as int, {'status': 'covered'});
        }
      }
    }

    // الأصناف غير المتاحة → stubborn
    for (final item in _response!.unavailableItems) {
      final shortages = await db.getShortages();
      for (final s in shortages) {
        final name = (s['name'] as String).trim().toLowerCase();
        final itemName = item.drugName.trim().toLowerCase();
        if (name == itemName) {
          await db.updateShortage(s['id'] as int, {'status': 'stubborn'});
        }
      }
    }

    // حذف الجلسة فوراً من السحابة بعد استقبالها
    await SupabaseService.instance.deleteSession(_response!.sessionId);

    if (mounted) {
      showSnack(context, 'تم إنهاء اليوم ✅');
      Navigator.pop(context);
    }
  }

  Future<void> _exportPDF() async {
    if (_response == null) return;

    final pdf = pw.Document();
    final pharmacyName = await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدليتي';

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
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('صيدلي PRO', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(pharmacyName, style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('رد المندوب: ${_response!.repName}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('التاريخ: ${_formatDate(_response!.respondedAt)}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // Available Items
          if (_response!.availableItems.isNotEmpty) ...[
            pw.Text('✅ الأصناف المتاحة (${_response!.availableItems.length})',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: ['الصنف', 'الشركة', 'الكمية', 'الخصم%', 'السعر النهائي']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ))
                      .toList(),
                ),
                ..._response!.availableItems.map((item) => pw.TableRow(
                  children: [
                    item.drugName, item.company,
                    '${item.quantity}',
                    '${item.discount.toStringAsFixed(0)}%',
                    '${item.finalPrice.toStringAsFixed(2)} جنيه',
                  ]
                      .map((t) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(t, style: const pw.TextStyle(fontSize: 10)),
                          ))
                      .toList(),
                )),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                'إجمالي: ${_response!.availableItems.fold(0.0, (s, i) => s + i.totalPrice).toStringAsFixed(2)} جنيه',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.green700),
              ),
            ),
            pw.SizedBox(height: 16),
          ],

          // Unavailable Items
          if (_response!.unavailableItems.isNotEmpty) ...[
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text('❌ الأصناف غير المتاحة (${_response!.unavailableItems.length})',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
            pw.SizedBox(height: 8),
            ..._response!.unavailableItems.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text('• ${item.drugName} (${item.company}) - ${item.quantity} علبة',
                  style: const pw.TextStyle(fontSize: 11)),
            )),
          ],

          pw.Spacer(),
          pw.Divider(),
          pw.Center(
            child: pw.Text('تم إنشاء هذا التقرير بواسطة تطبيق صيدلي PRO',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          ),
        ],
      ),
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('استقبال رد المندوب', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_response != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: AppColors.danger),
              tooltip: 'تصدير PDF',
              onPressed: _exportPDF,
            ),
        ],
      ),
      body: _response == null ? _buildCodeEntry() : _buildResponse(),
      bottomNavigationBar: _response == null ? null : Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: AppColors.darkCard,
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportPDF,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('تصدير PDF', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _finishDay,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('تم إنهاء اليوم'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeEntry() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📲', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text('أدخل كود الرد', style: TextStyle(color: AppColors.textColor, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('أدخل الكود المكوّن من 8 أحرف الذي أرسله المندوب',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 32),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
            maxLength: 8,
            decoration: InputDecoration(
              hintText: '--------',
              hintStyle: const TextStyle(color: AppColors.darkBorder, letterSpacing: 8, fontSize: 28),
              errorText: _error,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onSubmitted: (_) => _fetchResponse(),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            text: 'جلب الرد',
            isLoading: _loading,
            icon: Icons.search_rounded,
            onTap: _fetchResponse,
          ),
        ],
      ),
    );
  }

  Widget _buildResponse() {
    final r = _response!;
    final total = r.availableItems.fold(0.0, (s, i) => s + i.totalPrice);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Rep Info
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0D2E1C), Color(0xFF0A3525)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryDark),
          ),
          child: Row(
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Center(child: Text(r.repName[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.repName, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('رد في ${_formatDate(r.respondedAt)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(20)),
                child: Text('${r.availableItems.length + r.unavailableItems.length} صنف', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Available
        if (r.availableItems.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('✅ متاح (${r.availableItems.length})', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              Text('${total.toStringAsFixed(2)} جنيه', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ...r.availableItems.map((item) => _buildAvailableCard(item)),
          const SizedBox(height: 12),
        ],

        // Unavailable - لديها فرصة
        if (r.unavailableItems.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('⏳', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text('لديها فرصة (${r.unavailableItems.length})', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('هذه الأصناف غير متاحة من هذا المندوب - يمكن إرسالها لمندوب آخر',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...r.unavailableItems.map((item) => _buildUnavailableCard(item)),
        ],
      ],
    );
  }

  Widget _buildAvailableCard(ResponseItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.drugName, style: const TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700)),
                    Text('${item.company} · ${item.quantity} علبة', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${item.finalPrice.toStringAsFixed(2)} جنيه', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                  if (item.discount > 0)
                    Text('خصم ${item.discount.toStringAsFixed(0)}%', style: const TextStyle(color: AppColors.warning, fontSize: 11)),
                ],
              ),
            ],
          ),
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.notes!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildUnavailableCard(ResponseItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.drugName, style: const TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                Text('${item.company} · ${item.quantity} علبة', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: const Text('⏳ لديها فرصة', style: TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
