import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../utils/app_theme.dart';
import '../utils/country_config.dart';
import '../widgets/common_widgets.dart';
import 'rep_response_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

class ParsedItem {
  final String originalText;
  String name;
  double? price;
  bool isNewPrice;
  String? notes;
  int quantity;
  bool isSelected;

  ParsedItem({
    required this.originalText,
    required this.name,
    this.price,
    this.isNewPrice = false,
    this.notes,
    this.quantity = 1,
    this.isSelected = false,
  });
}

class RepMessageParserScreen extends StatefulWidget {
  const RepMessageParserScreen({super.key});

  @override
  State<RepMessageParserScreen> createState() => _RepMessageParserScreenState();
}

class _RepMessageParserScreenState extends State<RepMessageParserScreen> {
  Representative? _selectedRep;
  final TextEditingController _messageCtrl = TextEditingController();
  List<ParsedItem> _parsedItems = [];
  bool _isParsing = false;
  bool _sending = false;

  String? _generatedLink;
  String? _sessionCode;
  String _countryCode = 'EG';
  String _currency = 'ج.م';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final currency = await DatabaseHelper.instance.getCurrency();
    final countryCode = await DatabaseHelper.instance.getCountryCode();
    if (mounted) {
      setState(() {
        _currency = currency;
        _countryCode = countryCode;
      });
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _showSelectRepDialog() async {
    final reps = await DatabaseHelper.instance.getReps();
    if (reps.isEmpty) {
      if (mounted) showSnack(context, 'لا يوجد مندوبون مسجلون', isError: true);
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختر المندوب',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: reps.length,
                itemBuilder: (ctx, i) {
                  final rep = Representative.fromMap(reps[i]);
                  return ListTile(
                    leading: const Icon(Icons.person, color: AppColors.primary),
                    title: Text(rep.name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(rep.company ?? '',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                    onTap: () {
                      setState(() {
                        _selectedRep = rep;
                      });
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _parseMessage() async {
    if (_messageCtrl.text.trim().isEmpty) {
      showSnack(context, 'الرجاء إدخال رسالة المندوب أولاً', isError: true);
      return;
    }

    setState(() {
      _isParsing = true;
      _parsedItems.clear();
    });

    final lines = _messageCtrl.text.split('\n');
    final Map<String, ParsedItem> uniqueItems = {};

    final curPattern = r'(?:ج\.م|ر\.س|د\.إ|د\.ك|ر\.ق|د\.ب|ر\.ع|د\.ع|د\.أ|د\.ل|ج\.س|ر\.ي|ل\.س|ل\.ل|ش\.ج|د\.م\.?|د\.ج|د\.ت|ش\.ص|ف\.ج\.ق|ف\.ج|جنيهات|جنيه|دراهم|درهم|ريالات|ريال|دنانير|دينار|ليرات|ليرة|شواكل|شيكل|أوقية|فرنكات|فرنك|شلنات|شلن|EGP|SAR|AED|KWD|QAR|BHD|OMR|IQD|JOD|LYD|SDG|YER|SYP|LBP|ILS|MAD|DZD|TND|MRU|SOS|DJF|KMF|ج|ر|ل|ش)';
    final pattern1 = RegExp('(جديد\\s*)?(\\d+(?:\\.\\d+)?)\\s*($curPattern)', caseSensitive: false);
    final pattern2 = RegExp('(جديد\\s*)?($curPattern)\\s*(\\d+(?:\\.\\d+)?)', caseSensitive: false);
    final pattern3 = RegExp('(?:سعر|سعرها|بسعر|بـ|ب)\\s*(\\d+(?:\\.\\d+)?)', caseSensitive: false);
    final pattern4 = RegExp('(جديد)\\s*(\\d+(?:\\.\\d+)?)', caseSensitive: false);
    final pattern5 = RegExp('(\\d+(?:\\.\\d+)?)\\s*\$');

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Extract Name
      String name = line;
      double? price;
      bool isNewPrice = false;
      String? notes;

      Match? match;
      int matchType = 0;

      if (pattern1.hasMatch(line)) {
        match = pattern1.firstMatch(line);
        matchType = 1;
      } else if (pattern2.hasMatch(line)) {
        match = pattern2.firstMatch(line);
        matchType = 2;
      } else if (pattern3.hasMatch(line)) {
        match = pattern3.firstMatch(line);
        matchType = 3;
      } else if (pattern4.hasMatch(line)) {
        match = pattern4.firstMatch(line);
        matchType = 4;
      } else if (pattern5.hasMatch(line)) {
        match = pattern5.firstMatch(line);
        matchType = 5;
      }

      if (match != null) {
        if (matchType == 1) {
          if (match.group(1) != null) isNewPrice = true;
          price = double.tryParse(match.group(2) ?? '');
        } else if (matchType == 2) {
          if (match.group(1) != null) isNewPrice = true;
          price = double.tryParse(match.group(3) ?? '');
        } else if (matchType == 3) {
          price = double.tryParse(match.group(1) ?? '');
        } else if (matchType == 4) {
          isNewPrice = true;
          price = double.tryParse(match.group(2) ?? '');
        } else if (matchType == 5) {
          price = double.tryParse(match.group(1) ?? '');
        }
        // Remove the price part from the name
        name = name.replaceAll(match.group(0)!, '').trim();
      }

      if (line.contains('جديد') && !isNewPrice) {
        isNewPrice = true;
        name = name.replaceAll('جديد', '').trim();
      }

      // Check for notes like "بديل كذا"
      if (name.contains('بديل')) {
        final parts = name.split('بديل');
        name = parts[0].trim();
        notes = 'بديل ${parts[1].trim()}';
      }

      // Check for '؟'
      if (name.contains('؟') || name.contains('?')) {
        if (notes == null) {
          notes = 'تأكيد؟';
        } else {
          notes = '$notes - تأكيد؟';
        }
        name = name.replaceAll('؟', '').replaceAll('?', '').trim();
      }

      // Clean up name
      name = name.replaceAll('/', '').replaceAll('-', '').trim();

      if (name.isNotEmpty) {
        final key = name.toLowerCase();
        // Deduplicate: Keep the latest item if it appears multiple times
        uniqueItems[key] = ParsedItem(
          originalText: line,
          name: name,
          price: price,
          isNewPrice: isNewPrice,
          notes: notes,
        );
      }
    }

    // Save new items to dictionary
    await _saveNewItemsToDictionary(uniqueItems.values.map((e) => e.name).toList());

    setState(() {
      _parsedItems = uniqueItems.values.toList();
      // Sort: Items with price first, then without price/needs confirmation
      _parsedItems.sort((a, b) {
        if (a.price != null && b.price == null) return -1;
        if (a.price == null && b.price != null) return 1;
        return 0;
      });
      _isParsing = false;
    });
  }

  Future<void> _saveNewItemsToDictionary(List<String> names) async {
    try {
      final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
      List<Map<String, dynamic>> drugList = [];
      
      if (dictStr != null) {
        try {
          final List<dynamic> decoded = jsonDecode(dictStr);
          drugList = decoded.cast<Map<String, dynamic>>();
        } catch (_) {}
      }

      bool added = false;
      for (String name in names) {
        final exists = drugList.any((d) => 
          (d['enName']?.toString().toLowerCase() ?? '') == name.toLowerCase()
        );

        if (!exists) {
          drugList.add({
            'enName': name,
            'arName': '',
            'activeIngredient': '',
            'company': _selectedRep?.company ?? 'غير محدد',
            'barcode': '',
            'price': 0,
          });
          added = true;
        }
      }

      if (added) {
        await DatabaseHelper.instance.setSetting('drug_dictionary_v2', jsonEncode(drugList));
      }
    } catch (e) {
      debugPrint('Error saving to dictionary: $e');
    }
  }

  Future<void> _sendOrder() async {
    final selectedItems = _parsedItems.where((i) => i.isSelected).toList();
    if (selectedItems.isEmpty) return;

    if (_selectedRep == null) {
      showSnack(context, 'الرجاء اختيار المندوب أولاً', isError: true);
      return;
    }

    setState(() => _sending = true);

    final pharmacyName = await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدليتي';
    final currency = await DatabaseHelper.instance.getCurrency();
    _countryCode = await DatabaseHelper.instance.getCountryCode();

    final items = selectedItems
        .map((s) => {
              'name': s.name,
              'company': _selectedRep!.company ?? 'غير محدد',
              'quantity': s.quantity,
              'is_private': 0,
            })
        .toList();

    try {
      final code = await SupabaseService.instance.createSession(
        repName: _selectedRep!.name,
        repPhone: _selectedRep!.phone ?? '',
        pharmacyName: pharmacyName,
        items: items,
        currency: currency,
      );

      if (mounted) {
        setState(() => _sending = false);
        if (code != null) {
          setState(() {
            _sessionCode = code;
            _generatedLink = SupabaseService.instance.buildRepLink(code);
          });
          _showLinkSheet();
        } else {
          showSnack(context, SupabaseService.instance.lastError ?? 'فشل إنشاء الطلب، يرجى المحاولة لاحقاً', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        showSnack(context, 'حدث خطأ: ${e.toString()}', isError: true);
      }
    }
  }

  void _showLinkSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.darkBorder,
                        borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 20),
            const Text('✅ تم إنشاء الرابط!',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('أرسل الرابط لـ ${_selectedRep?.name}',
                style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _generatedLink ?? '',
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy,
                        color: AppColors.primary, size: 18),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _generatedLink ?? ''));
                      showSnack(ctx, 'تم نسخ الرابط ✅');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final msg =
                          'مرحباً ${_selectedRep?.name}،\nيرجى مراجعة الطلبية والرد عبر الرابط:\n$_generatedLink';
                      final phone = _selectedRep?.phone ?? '';
                      final formattedPhone = phone.isNotEmpty
                          ? CountryConfig.formatPhone(phone, _countryCode)
                              .replaceAll('+', '')
                          : '';
                      final urlStr = formattedPhone.isNotEmpty
                          ? 'https://wa.me/$formattedPhone?text=${Uri.encodeComponent(msg)}'
                          : 'https://wa.me/?text=${Uri.encodeComponent(msg)}';
                      final url = Uri.parse(urlStr);
                      try {
                        if (!await launchUrl(url,
                            mode: LaunchMode.externalApplication)) {
                          throw Exception('Could not launch');
                        }
                      } catch (e) {
                        Clipboard.setData(ClipboardData(text: msg));
                        if (ctx.mounted)
                          showSnack(ctx, 'تم نسخ الرسالة - افتح واتساب يدويًا');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366)),
                    icon: const Icon(Icons.message, size: 16),
                    label: const Text('واتساب'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _generatedLink ?? ''));
                      showSnack(ctx, 'تم نسخ الرابط ✅');
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.darkBorder),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('نسخ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            RepResponseScreen(initialCode: _sessionCode)),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('استقبال رد المندوب',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int selectedCount = _parsedItems.where((i) => i.isSelected).length;

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('تحليل رسائل المندوبين',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step 1: Select Mandoob
                  GestureDetector(
                    onTap: _showSelectRepDialog,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    _selectedRep?.name ??
                                        'اختر المندوب من القائمة',
                                    style: const TextStyle(
                                        color: AppColors.textColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16)),
                                if (_selectedRep != null &&
                                    _selectedRep!.company != null)
                                  Text(_selectedRep!.company!,
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12)),
                              ],
                            ),
                          ),
                          const Text('تغيير',
                              style: TextStyle(
                                  color: AppColors.primary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Step 2: Input Textarea
                  const Text('رسالة المندوب',
                      style: TextStyle(
                          color: AppColors.textLight,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  AppTextField(
                    hint: 'الصق رسالة الواتساب هنا...\nمثال:\nبروفين شراب/جديد 44ج\nنانازوكسيد شراب/جديد 39ج',
                    controller: _messageCtrl,
                    maxLines: 8,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isParsing ? null : _parseMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: _isParsing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_isParsing ? 'جاري التحليل...' : 'تحليل الرسالة'),
                    ),
                  ),

                  if (_parsedItems.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الأصناف المستخرجة',
                            style: TextStyle(
                                color: AppColors.textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              bool allSelected = _parsedItems.every((i) => i.isSelected);
                              for (var item in _parsedItems) {
                                item.isSelected = !allSelected;
                              }
                            });
                          },
                          child: Text('تحديد الكل', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Parsed Items List
                    ..._parsedItems.map((item) {
                      final bool needsConfirmation = item.notes != null && item.notes!.contains('تأكيد');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: item.isSelected
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : AppColors.darkCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: item.isSelected
                                  ? AppColors.primary.withValues(alpha: 0.5)
                                  : AppColors.darkBorder),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: item.isSelected,
                              activeColor: AppColors.primary,
                              onChanged: (val) {
                                setState(() {
                                  item.isSelected = val ?? false;
                                });
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(item.name,
                                                  style: const TextStyle(
                                                      color: AppColors.textColor,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 14)),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 18),
                                              onPressed: () async {
                                                final query = Uri.encodeComponent(item.name);
                                                final url = Uri.parse('https://www.google.com/search?q=$query');
                                                try {
                                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                                } catch (e) {
                                                  if (mounted) showSnack(context, 'تعذر فتح المتصفح', isError: true);
                                                }
                                              },
                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                              constraints: const BoxConstraints(),
                                              tooltip: 'بحث في جوجل',
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (item.isNewPrice)
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.accent.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text('جديد',
                                              style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w700)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(item.price != null ? '${item.price} $_currency' : '—',
                                          style: const TextStyle(
                                              color: AppColors.textLight,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                      if (needsConfirmation) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text('تأكيد؟',
                                              style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                      if (item.notes != null && !needsConfirmation) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(item.notes!,
                                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Quantity Controls
                            Container(
                              decoration: BoxDecoration(
                                color: item.isSelected ? AppColors.dark : AppColors.dark.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: item.isSelected ? () {
                                      if (item.quantity > 1) {
                                        setState(() => item.quantity--);
                                      }
                                    } : null,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Icon(Icons.remove, size: 16, color: item.isSelected ? AppColors.textColor : AppColors.textMuted),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: item.isSelected ? () async {
                                      final controller = TextEditingController(text: '${item.quantity}');
                                      final newQty = await showDialog<int>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: AppColors.darkCard,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          title: const Text('تعديل الكمية', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                          content: TextField(
                                            controller: controller,
                                            keyboardType: TextInputType.number,
                                            autofocus: true,
                                            style: const TextStyle(color: Colors.white),
                                            decoration: const InputDecoration(
                                              hintText: 'الكمية المطلوبة',
                                              hintStyle: TextStyle(color: AppColors.textMuted),
                                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.darkBorder)),
                                              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                                            ),
                                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx),
                                              child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
                                            ),
                                            ElevatedButton(
                                              onPressed: () {
                                                final val = int.tryParse(controller.text);
                                                if (val != null && val > 0) {
                                                  Navigator.pop(ctx, val);
                                                } else {
                                                  Navigator.pop(ctx);
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                              child: const Text('حفظ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (newQty != null) {
                                        setState(() => item.quantity = newQty);
                                      }
                                    } : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        border: Border.symmetric(vertical: BorderSide(color: AppColors.darkBorder.withValues(alpha: 0.5))),
                                      ),
                                      child: Text('${item.quantity}',
                                          style: TextStyle(
                                              color: item.isSelected ? AppColors.primary : AppColors.textMuted,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14)),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: item.isSelected ? () {
                                      setState(() => item.quantity++);
                                    } : null,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Icon(Icons.add, size: 16, color: item.isSelected ? AppColors.textColor : AppColors.textMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
          ),
          
          // Bottom Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.darkCard,
              border: Border(top: BorderSide(color: AppColors.darkBorder)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('الأصناف المحددة', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      Text('$selectedCount', style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: selectedCount > 0 && !_sending ? _sendOrder : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(_sending ? 'جاري الإرسال...' : 'إرسال الطلب'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
