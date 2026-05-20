import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../services/supabase_service.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class RepResponseScreen extends StatefulWidget {
  final String? initialCode;
  const RepResponseScreen({super.key, this.initialCode});

  @override
  State<RepResponseScreen> createState() => _RepResponseScreenState();
}

class _RepResponseScreenState extends State<RepResponseScreen> {
  late final TextEditingController _codeCtrl;
  bool _loading = false;
  String? _error;
  RepResponse? _response;
  String _searchQuery = '';
  bool _showSearch = false;
  String _currency = 'ج.م';

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.initialCode ?? '');
    _loadCurrency();
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchResponse();
      });
    }
  }

  Future<void> _loadCurrency() async {
    final c = await DatabaseHelper.instance.getCurrency();
    if (mounted) setState(() => _currency = c);
  }

  Future<void> _searchGoogleImages(String query) async {
    if (query.trim().isEmpty) {
      showSnack(context, 'الرجاء إدخال اسم الدواء للبحث', isError: true);
      return;
    }
    final url = Uri.parse(
        'https://www.google.com/search?tbm=isch&q=${Uri.encodeComponent(query)}+دواء');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showSnack(context, 'تعذر فتح المتصفح', isError: true);
    }
  }

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

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await SupabaseService.instance.fetchResponseByCode(code);

    if (mounted) {
      setState(() {
        _loading = false;
        if (result.response != null) {
          _response = result.response;
        } else if (result.error != null) {
          _error = result.error;
        } else {
          _error = 'كود غير صحيح أو منتهي الصلاحية';
        }
      });

      // حذف البيانات من Supabase فوراً بعد استلام الرد (توفير التكلفة)
      if (result.response != null) {
        SupabaseService.instance.deleteSession(result.response!.sessionId);
      }
    }
  }

  Future<void> _processResponse(bool endDay) async {
    if (_response == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(endDay ? 'تأكيد إنهاء اليوم' : 'تأكيد الرد',
            style: const TextStyle(
                color: AppColors.textColor, fontWeight: FontWeight.w700)),
        content: Text(
          endDay
              ? 'سيتم:\n✅ تغطية ${_response!.availableItems.length} صنف متاح\n⚠️ تحويل ${_response!.unavailableItems.length} صنف لمستعصي'
              : 'سيتم:\n✅ تغطية ${_response!.availableItems.length} صنف متاح\n⏳ بقاء ${_response!.unavailableItems.length} صنف في قائمة الانتظار',
          style: const TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirm != true) return;

    final db = DatabaseHelper.instance;
    final shortagesData = await db.getShortages();

    final Map<String, List<int>> shortageMap = {};
    for (var s in shortagesData) {
      final key = s['name'].toString().trim().toLowerCase();
      shortageMap.putIfAbsent(key, () => []).add(s['id'] as int);
    }

    // ▌ تحديث أسعار الأدوية في القاموس إذا زاد السعر
    final dictStr = await db.getSetting('drug_dictionary_v2');
    bool dictUpdated = false;
    List<Map<String, dynamic>> dictionary = [];

    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        dictionary = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }

    for (final item in _response!.availableItems) {
      final key = item.drugName.trim().toLowerCase();
      
      // تحديث حالة النواقص
      if (shortageMap.containsKey(key)) {
        // الكمية التي وفرها المندوب لهذا الصنف
        int remainingQty = item.quantity;

        for (final id in shortageMap[key]!) {
          if (remainingQty <= 0) break; // تم استهلاك كل الكمية اللي وفرها المندوب

          final shortage = shortagesData.firstWhere((s) => s['id'] == id);
          final reqQty = (shortage['quantity'] as num?)?.toInt() ?? 1;

          if (remainingQty >= reqQty) {
            // تغطية كاملة لهذا الناقص
            await db.updateShortage(id, {'status': 'covered'});
            remainingQty -= reqQty;
          } else {
            // تغطية جزئية: الكمية المتبقية مع المندوب أقل من المطلوبة هنا
            await db.updateShortage(id, {
              'status': 'covered',
              'quantity': remainingQty
            });

            // إنشاء ناقص جديد بالكمية المتبقية
            await db.insertShortage({
              'name': shortage['name'],
              'company': shortage['company'],
              'quantity': reqQty - remainingQty,
              'status': 'pending',
              'is_urgent': shortage['is_urgent'],
              'notes': 'متبقي من طلبية سابقة (${_response!.repName})',
            });

            remainingQty = 0;
          }
        }
      }

      // تحديث السعر في القاموس
      if (item.price > 0 && dictionary.isNotEmpty) {
        for (int i = 0; i < dictionary.length; i++) {
          final dictName = dictionary[i]['enName']?.toString().toLowerCase().trim() ?? '';
          if (dictName == key) {
            final currentPrice = double.tryParse(dictionary[i]['price']?.toString() ?? '0') ?? 0;
            if (item.price > currentPrice) {
              dictionary[i]['price'] = item.price;
              dictUpdated = true;
              debugPrint('✅ تم تحديث سعر ${item.drugName} من $currentPrice إلى ${item.price}');
            }
            break;
          }
        }
      }
    }

    if (dictUpdated) {
      await db.setSetting('drug_dictionary_v2', jsonEncode(dictionary));
    }

    for (final item in _response!.unavailableItems) {
      final key = item.drugName.trim().toLowerCase();
      if (shortageMap.containsKey(key)) {
        for (final id in shortageMap[key]!) {
          await db.updateShortage(id, {'status': endDay ? 'stubborn' : 'pending'});
        }
      }
    }

    // ▌ تسجيل الطلبية في سجل المندوبين
    if (_response!.availableItems.isNotEmpty) {
      final orderItems = _response!.availableItems.map((item) => {
        'name': item.drugName,
        'company': item.company,
        'quantity': item.quantity,
        'price': item.price,
        'discount': item.discount,
        'finalPrice': item.finalPrice,
        'totalPrice': item.totalPrice,
      }).toList();

      final total = _response!.availableItems.fold(0.0, (s, i) => s + i.totalPrice);

      await db.insertRepOrder({
        'rep_name': _response!.repName,
        'items': jsonEncode(orderItems),
        'total': total,
        'is_paid': 0, // افتراضياً غير مدفوع
      });
    }

    if (mounted) {
      showSnack(context, endDay ? 'تم إنهاء اليوم ✅' : 'تم قبول الرد بنجاح ✅');

      // ▌ مقارنة ذكية للأسعار مع المندوبين السابقين
      if (_response!.availableItems.isNotEmpty) {
        await _comparePricesWithOtherReps();
      }

      if (mounted) Navigator.pop(context);
    }
  }

  // ▌ مقارنة الأسعار والخصومات بين المندوبين
  Future<void> _comparePricesWithOtherReps() async {
    if (_response == null) return;
    final db = DatabaseHelper.instance;

    // قراءة فترة المقارنة من الإعدادات (افتراضي 30 يوم)
    final daysStr = await db.getSetting('comparison_days') ?? '30';
    final comparisonDays = int.tryParse(daysStr) ?? 30;

    final allOrders = await db.getAllRepOrders(withinDays: comparisonDays);

    // بناء خريطة: اسم الدواء → [ {repName, finalPrice, discount, price, date} ]
    final Map<String, List<Map<String, dynamic>>> priceMap = {};

    for (var order in allOrders) {
      final repName = order['rep_name'] as String;
      final orderDate = order['created_at'] as String? ?? '';
      try {
        final items = jsonDecode(order['items'] as String) as List;
        for (var item in items) {
          final name = (item['name'] as String).trim().toLowerCase();
          final finalPrice = (item['finalPrice'] as num?)?.toDouble() ?? 
                             (item['price'] as num?)?.toDouble() ?? 0;
          final discount = (item['discount'] as num?)?.toDouble() ?? 0;
          final price = (item['price'] as num?)?.toDouble() ?? 0;

          if (finalPrice <= 0) continue;

          priceMap.putIfAbsent(name, () => []);
          // نأخذ أحدث سعر من كل مندوب
          priceMap[name]!.removeWhere((e) => e['repName'] == repName);
          priceMap[name]!.add({
            'repName': repName,
            'finalPrice': finalPrice,
            'discount': discount,
            'price': price,
            'date': orderDate,
          });
        }
      } catch (_) {}
    }

    // مقارنة أصناف المندوب الحالي مع البقية
    final List<Map<String, dynamic>> alerts = [];

    for (var item in _response!.availableItems) {
      final key = item.drugName.trim().toLowerCase();
      final currentNet = item.finalPrice;

      if (!priceMap.containsKey(key)) continue;

      final offers = priceMap[key]!;
      if (offers.length < 2) continue;

      // ترتيب حسب أقل سعر صافي
      offers.sort((a, b) => (a['finalPrice'] as double).compareTo(b['finalPrice'] as double));
      final best = offers.first;
      final bestPrice = best['finalPrice'] as double;
      final bestRep = best['repName'] as String;

      // لو فيه مندوب أرخص من الحالي
      if (bestPrice < currentNet && bestRep != _response!.repName) {
        final saving = currentNet - bestPrice;
        alerts.add({
          'drugName': item.drugName,
          'currentRep': _response!.repName,
          'currentPrice': currentNet,
          'currentDiscount': item.discount,
          'bestRep': bestRep,
          'bestPrice': bestPrice,
          'bestDiscount': best['discount'] as double,
          'saving': saving,
          'allOffers': offers,
        });
      }
    }

    if (alerts.isEmpty || !mounted) return;

    // عرض تنبيه ذكي بالمقارنة
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🔔', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('ركّز! فيه عروض أفضل 💰',
                      style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                // زر تغيير فترة المقارنة
                InkWell(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _changeComparisonPeriod();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.settings, color: AppColors.textMuted, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '📅 مقارنة آخر $comparisonDays يوم',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: alerts.length,
            itemBuilder: (ctx, i) {
              final a = alerts[i];
              final allOffers = a['allOffers'] as List<Map<String, dynamic>>;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('💊 ${a['drugName']}',
                        style: const TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 8),
                    // جدول المقارنة
                    ...allOffers.map((offer) {
                      final isBest = offer == allOffers.first;
                      final isCurrent = offer['repName'] == _response!.repName;
                      // عرض التاريخ
                      String dateText = '';
                      try {
                        final d = DateTime.parse(offer['date'] as String);
                        final now = DateTime.now();
                        final diff = now.difference(d).inDays;
                        dateText = diff == 0 ? 'اليوم' : 'من $diff يوم';
                      } catch (_) {}
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isBest
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : isCurrent
                                  ? AppColors.danger.withValues(alpha: 0.1)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isBest ? Border.all(color: AppColors.primary.withValues(alpha: 0.4)) : null,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(isBest ? '👑' : isCurrent ? '📍' : '  ', style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(offer['repName'] as String,
                                      style: TextStyle(
                                        color: isBest ? AppColors.primary : AppColors.textLight,
                                        fontWeight: isBest ? FontWeight.w800 : FontWeight.w500,
                                        fontSize: 12,
                                      )),
                                ),
                                Text('خصم ${(offer['discount'] as double).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: isBest ? AppColors.primary : AppColors.textMuted,
                                      fontSize: 11,
                                    )),
                                const SizedBox(width: 10),
                                Text('${(offer['finalPrice'] as double).toStringAsFixed(1)} $_currency',
                                    style: TextStyle(
                                      color: isBest ? AppColors.primary : AppColors.textLight,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                            if (dateText.isNotEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 24, top: 2),
                                  child: Text(dateText,
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '💡 توفير ${(a['saving'] as double).toStringAsFixed(1)} $_currency/علبة مع "${a['bestRep']}"',
                        style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          // زر مشاركة PDF
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _shareComparisonPDF(alerts, comparisonDays);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('PDF', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          // زر مشاركة نص
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _shareComparisonText(alerts, comparisonDays);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
            ),
            icon: const Icon(Icons.share, size: 16),
            label: const Text('نص', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('فهمت ✅', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ▌ إنشاء ومشاركة PDF مقارنة الأسعار
  Future<void> _shareComparisonPDF(List<Map<String, dynamic>> alerts, int comparisonDays) async {
    final pdf = pw.Document();
    final pharmacyName = await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدلي PRO';
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
      textDirection: pw.TextDirection.rtl,
      header: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('📊 تقرير مقارنة الأسعار',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(pharmacyName,
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('فترة المقارنة: آخر $comparisonDays يوم',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
                  pw.Text('التاريخ: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 8),
        ],
      ),
      build: (pw.Context context) {
        final widgets = <pw.Widget>[];

        for (int i = 0; i < alerts.length; i++) {
          final a = alerts[i];
          final allOffers = a['allOffers'] as List<Map<String, dynamic>>;

          widgets.add(pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 16),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('${i + 1}. ${a['drugName']}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.5),
                    1: const pw.FlexColumnWidth(2.5),
                    2: const pw.FlexColumnWidth(1.2),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1.2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: ['#', 'المندوب', 'الخصم %', 'السعر الصافي', 'التاريخ']
                          .map((h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(h,
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                              ))
                          .toList(),
                    ),
                    ...allOffers.asMap().entries.map((e) {
                      final idx = e.key;
                      final offer = e.value;
                      String dateText = '';
                      try {
                        final d = DateTime.parse(offer['date'] as String);
                        dateText = '${d.day}/${d.month}/${d.year}';
                      } catch (_) {
                        dateText = '-';
                      }
                      final isBest = idx == 0;
                      return pw.TableRow(
                        decoration: isBest ? const pw.BoxDecoration(color: PdfColors.green50) : null,
                        children: [
                          isBest ? '👑' : '${idx + 1}',
                          offer['repName'] as String,
                          '${(offer['discount'] as double).toStringAsFixed(0)}%',
                          '${(offer['finalPrice'] as double).toStringAsFixed(2)} $_currency',
                          dateText,
                        ].map((t) => pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(t, style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: t.startsWith('👑') ? pw.FontWeight.bold : pw.FontWeight.normal,
                              )),
                            )).toList(),
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'التوفير: ${(a['saving'] as double).toStringAsFixed(2)} $_currency/علبة عند الشراء من "${a['bestRep']}" بدلاً من "${a['currentRep']}"',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
                  ),
                ),
              ],
            ),
          ));
        }

        // ملخص إجمالي
        widgets.add(pw.SizedBox(height: 12));
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.amber50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: PdfColors.amber200),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('📋 ملخص التقرير',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('عدد الأصناف التي وُجد لها عروض أفضل: ${alerts.length} صنف',
                  style: const pw.TextStyle(fontSize: 11)),
              pw.Text(
                'إجمالي التوفير الممكن: ${alerts.fold(0.0, (s, a) => s + (a['saving'] as double)).toStringAsFixed(2)} $_currency/علبة',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ));

        widgets.add(pw.SizedBox(height: 20));
        widgets.add(pw.Center(
          child: pw.Text('تم إنشاء هذا التقرير بواسطة تطبيق صيدلي PRO 💊',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        ));

        return widgets;
      },
    ));

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'price_comparison_report.pdf');
  }

  // ▌ مشاركة المقارنة كنص
  void _shareComparisonText(List<Map<String, dynamic>> alerts, int comparisonDays) {
    String msg = '📊 تقرير مقارنة أسعار المندوبين\n';
    msg += '📅 فترة المقارنة: آخر $comparisonDays يوم\n';
    msg += '━━━━━━━━━━━━━━━━━━━━\n\n';

    for (int i = 0; i < alerts.length; i++) {
      final a = alerts[i];
      final allOffers = a['allOffers'] as List<Map<String, dynamic>>;

      msg += '💊 ${i + 1}. ${a['drugName']}\n';
      for (var offer in allOffers) {
        final isBest = offer == allOffers.first;
        final icon = isBest ? '👑' : '  ';
        String dateText = '';
        try {
          final d = DateTime.parse(offer['date'] as String);
          final diff = DateTime.now().difference(d).inDays;
          dateText = diff == 0 ? '(اليوم)' : '(من $diff يوم)';
        } catch (_) {}
        msg += '$icon ${offer['repName']} - خصم ${(offer['discount'] as double).toStringAsFixed(0)}% - ${(offer['finalPrice'] as double).toStringAsFixed(2)} $_currency $dateText\n';
      }
      msg += '💡 توفير: ${(a['saving'] as double).toStringAsFixed(2)} $_currency/علبة\n\n';
    }

    final totalSaving = alerts.fold(0.0, (s, a) => s + (a['saving'] as double));
    msg += '━━━━━━━━━━━━━━━━━━━━\n';
    msg += '📋 إجمالي التوفير الممكن: ${totalSaving.toStringAsFixed(2)} $_currency/علبة\n';
    msg += '\nتم الإرسال عبر صيدلي PRO 💊';

    Share.share(msg);
  }

  // ▌ تغيير فترة المقارنة
  Future<void> _changeComparisonPeriod() async {
    final db = DatabaseHelper.instance;
    final currentStr = await db.getSetting('comparison_days') ?? '30';
    final current = int.tryParse(currentStr) ?? 30;

    final options = [7, 14, 30, 60, 90, 180, 365];

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚙️ فترة المقارنة',
            style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختر الفترة الزمنية لمقارنة الأسعار بين المندوبين:',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            ...options.map((days) {
              final isSelected = days == current;
              String label;
              if (days == 7) label = 'أسبوع';
              else if (days == 14) label = 'أسبوعين';
              else if (days == 30) label = 'شهر';
              else if (days == 60) label = 'شهرين';
              else if (days == 90) label = '3 شهور';
              else if (days == 180) label = '6 شهور';
              else label = 'سنة';

              return InkWell(
                onTap: () async {
                  await db.setSetting('comparison_days', days.toString());
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    showSnack(context, 'تم تعيين فترة المقارنة: $label ✅');
                  }
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.dark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.darkBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? AppColors.primary : AppColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(label,
                          style: TextStyle(
                            color: isSelected ? AppColors.primary : AppColors.textLight,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          )),
                      const Spacer(),
                      Text('$days يوم',
                          style: TextStyle(
                            color: isSelected ? AppColors.primary : AppColors.textMuted,
                            fontSize: 12,
                          )),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPDF() async {
    if (_response == null) return;

    final pdf = pw.Document();
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
                  pw.Text('صيدلي PRO',
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
                  pw.Text('رد المندوب: ${_response!.repName}',
                      style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('التاريخ: ${_formatDate(_response!.respondedAt)}',
                      style: const pw.TextStyle(
                          fontSize: 11, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 10),
          if (_response!.availableItems.isNotEmpty) ...[
            pw.Text('✅ الأصناف المتاحة (${_response!.availableItems.length})',
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1.2),
                5: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children:
                      ['الصنف', 'الكمية', 'السعر', 'الخصم', 'الصافي', 'الإجمالي']
                          .map((h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(h,
                                    style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 9)),
                              ))
                          .toList(),
                ),
                ..._response!.availableItems.map((item) => pw.TableRow(
                      children: [
                        '${item.drugName}\n(${item.company})',
                        '${item.quantity}',
                        item.price.toStringAsFixed(2),
                        '${item.discount.toStringAsFixed(0)}%',
                        item.finalPrice.toStringAsFixed(2),
                        '${item.totalPrice.toStringAsFixed(2)} $_currency',
                      ]
                          .map((t) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(t,
                                    style: const pw.TextStyle(fontSize: 9)),
                              ))
                          .toList(),
                    )),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                'إجمالي: ${_response!.availableItems.fold(0.0, (s, i) => s + i.totalPrice).toStringAsFixed(2)} $_currency',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                    color: PdfColors.green700),
              ),
            ),
            pw.SizedBox(height: 16),
          ],
          if (_response!.unavailableItems.isNotEmpty) ...[
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(
                '❌ الأصناف غير المتاحة (${_response!.unavailableItems.length})',
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700)),
            pw.SizedBox(height: 8),
            ..._response!.unavailableItems.map((item) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Text(
                      '• ${item.drugName} (${item.company}) - ${item.quantity} علبة',
                      style: const pw.TextStyle(fontSize: 11)),
                )),
          ],
          pw.Spacer(),
          pw.Divider(),
          pw.Center(
            child: pw.Text('تم إنشاء هذا التقرير بواسطة تطبيق صيدلي PRO',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          ),
        ],
      ),
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  void _shareAsText() {
    if (_response == null) return;
    final r = _response!;
    String msg = '📦 تقرير رد المندوب: ${r.repName}\n';
    msg += '📅 التاريخ: ${_formatDate(r.respondedAt)}\n';
    msg += '--------------------------\n';

    if (r.availableItems.isNotEmpty) {
      msg += '✅ الأصناف المتاحة:\n';
      for (var item in r.availableItems) {
        msg += '- ${item.drugName} (${item.quantity} علبة)\n';
        msg += '  سعر: ${item.price.toStringAsFixed(2)} | خصم: ${item.discount.toStringAsFixed(0)}% | صافي: ${item.finalPrice.toStringAsFixed(2)} | إجمالي: ${item.totalPrice.toStringAsFixed(2)} $_currency\n';
      }
      msg +=
          '\n💰 الإجمالي: ${r.availableItems.fold(0.0, (s, i) => s + i.totalPrice).toStringAsFixed(2)} $_currency\n';
    }

    if (r.unavailableItems.isNotEmpty) {
      msg += '\n❌ غير متاحة (تحتاج مندوب آخر):\n';
      for (var item in r.unavailableItems) {
        msg += '- ${item.drugName}\n';
      }
    }

    msg += '\nتم الإرسال عبر صيدلي PRO 💊';
    Share.share(msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'ابحث عن صنف...',
                    hintStyle: TextStyle(color: Colors.white60),
                    border: InputBorder.none),
                onChanged: (val) => setState(() => _searchQuery = val),
                autofocus: true,
              )
            : const Text('استقبال رد المندوب',
                style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.arrow_back_ios_rounded,
              color: AppColors.textColor),
          onPressed: () {
            if (_showSearch) {
              setState(() {
                _showSearch = false;
                _searchQuery = '';
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (_response != null) ...[
            IconButton(
              icon: const Icon(Icons.search, color: AppColors.primary),
              onPressed: () => setState(() => _showSearch = true),
            ),
            IconButton(
              icon: const Icon(Icons.share, color: AppColors.accent),
              onPressed: _shareAsText,
            ),
          ]
        ],
      ),
      body: _response == null ? _buildCodeEntry() : _buildResponse(),
      bottomNavigationBar: _response == null
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.darkCard,
                border: Border(top: BorderSide(color: AppColors.darkBorder)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _exportPDF,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                            label: const Text('PDF',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _shareAsText,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: const BorderSide(color: AppColors.accent),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('نص',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            onPressed: () => _processResponse(false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('تم (مع إبقاء النواقص)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            onPressed: () => _processResponse(true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.done_all, size: 18),
                            label: const Text('إنهاء اليوم',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ],
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
          const Text('أدخل كود الرد',
              style: TextStyle(
                  color: AppColors.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('أدخل الكود المكوّن من 8 أحرف الذي أرسله المندوب',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 32),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 8),
            maxLength: 8,
            decoration: InputDecoration(
              hintText: '--------',
              hintStyle: const TextStyle(
                  color: AppColors.darkBorder, letterSpacing: 8, fontSize: 28),
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
    final filteredAvailable = r.availableItems
        .where((i) =>
            i.drugName.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
    final filteredUnavailable = r.unavailableItems
        .where((i) =>
            i.drugName.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
    final total = filteredAvailable.fold(0.0, (s, i) => s + i.totalPrice);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_showSearch) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF0D2E1C), Color(0xFF0A3525)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primaryDark),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark]),
                      borderRadius: BorderRadius.circular(99)),
                  child: Center(
                      child: Text(r.repName[0],
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.repName,
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                      Text('رد في ${_formatDate(r.respondedAt)}',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                      '${r.availableItems.length + r.unavailableItems.length} صنف',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (filteredAvailable.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('✅ متاح (${filteredAvailable.length})',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
              Text('${total.toStringAsFixed(2)} $_currency',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ...filteredAvailable.map((item) => _buildAvailableCard(item)),
          const SizedBox(height: 12),
        ],
        if (filteredUnavailable.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('⏳', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text('لديها فرصة (${filteredUnavailable.length})',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                    'هذه الأصناف غير متاحة من هذا المندوب - يمكن إرسالها لمندوب آخر',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...filteredUnavailable.map((item) => _buildUnavailableCard(item)),
        ],
        if (filteredAvailable.isEmpty && filteredUnavailable.isEmpty)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('لا توجد نتائج بحث مطابقة',
                      style: TextStyle(color: AppColors.textMuted)))),
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
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(item.drugName,
                              style: const TextStyle(
                                  color: AppColors.textColor,
                                  fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 18),
                          onPressed: () => _searchGoogleImages(item.drugName),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          constraints: const BoxConstraints(),
                          tooltip: 'بحث في جوجل (صور)',
                        ),
                      ],
                    ),
                    Text('${item.company} · ${item.quantity} علبة',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 4),
                    if (item.discount > 0) ...[
                      Text('سعر القطعة الأساسي: ${item.price.toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, decoration: TextDecoration.lineThrough)),
                      Text('الصافي للقطعة: ${item.finalPrice.toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
                      Text('الإجمالي قبل الخصم: ${(item.price * item.quantity).toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, decoration: TextDecoration.lineThrough)),
                    ] else ...[
                      Text('سعر القطعة: ${item.price.toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
                    ]
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('الإجمالي', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  Text('${item.totalPrice.toStringAsFixed(2)} $_currency',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  if (item.discount > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('خصم ${item.discount.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.notes!,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.2))),
      child: Row(
        children: [
          const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(item.drugName,
                          style: const TextStyle(
                              color: AppColors.textLight,
                              fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 18),
                      onPressed: () => _searchGoogleImages(item.drugName),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      constraints: const BoxConstraints(),
                      tooltip: 'بحث في جوجل (صور)',
                    ),
                  ],
                ),
                Text('${item.company} · ${item.quantity} علبة',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('⏳ لديها فرصة',
                style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
