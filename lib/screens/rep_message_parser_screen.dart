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
  double? price;       // سعر المندوب (من الرسالة — بعلامة عملة فقط)
  double? storedPrice; // سعر التخزين المحلي
  bool isNewPrice;
  String? notes;
  int quantity;
  bool isSelected;

  ParsedItem({
    required this.originalText,
    required this.name,
    this.price,
    this.storedPrice,
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

class _RepMessageParserScreenState extends State<RepMessageParserScreen>
    with TickerProviderStateMixin {
  Representative? _selectedRep;
  final TextEditingController _messageCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  List<ParsedItem> _parsedItems = [];
  List<ParsedItem> _filteredItems = [];
  bool _isParsing = false;
  bool _sending = false;

  String? _generatedLink;
  String? _sessionCode;
  String _countryCode = 'EG';
  String _currency = 'ج.م';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
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

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = List.from(_parsedItems);
      } else {
        _filteredItems = _parsedItems
            .where((item) =>
                item.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RepSelectSheet(
        reps: reps,
        onSelect: (rep) {
          setState(() => _selectedRep = rep);
          Navigator.pop(ctx);
        },
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
      _filteredItems.clear();
    });

    _fadeCtrl.reset();

    final lines = _messageCtrl.text.split('\n');
    final Map<String, ParsedItem> uniqueItems = {};

    // ── أنماط السعر: فقط مع علامة عملة ──
    final curPattern =
        r'(?:ج\.م|ر\.س|د\.إ|د\.ك|ر\.ق|د\.ب|ر\.ع|د\.ع|د\.أ|د\.ل|ج\.س|ر\.ي|ل\.س|ل\.ل|ش\.ج|د\.م\.?|د\.ج|د\.ت|ش\.ص|ف\.ج\.ق|ف\.ج|جنيهات|جنيه|دراهم|درهم|ريالات|ريال|دنانير|دينار|ليرات|ليرة|شواكل|شيكل|أوقية|فرنكات|فرنك|شلنات|شلن|EGP|SAR|AED|KWD|QAR|BHD|OMR|IQD|JOD|LYD|SDG|YER|SYP|LBP|ILS|MAD|DZD|TND|MRU|SOS|DJF|KMF|ج|ر|ل|ش)';

    // رقم + عملة (مثال: 44ج أو 44 ج.م)
    final pattern1 = RegExp(
        '(جديد\\s*)?(\\d+(?:\\.\\d+)?)\\s*($curPattern)',
        caseSensitive: false);
    // عملة + رقم (مثال: ج44)
    final pattern2 = RegExp(
        '(جديد\\s*)?($curPattern)\\s*(\\d+(?:\\.\\d+)?)',
        caseSensitive: false);
    // "بسعر/سعر 44" — لكن فقط لو في نفس السطر علامة عملة
    final pattern3 = RegExp(
        '(?:سعر|سعرها|بسعر|بـ|ب)\\s*(\\d+(?:\\.\\d+)?)\\s*($curPattern)',
        caseSensitive: false);

    for (String rawLine in lines) {
      String line = rawLine.trim();
      if (line.isEmpty || line.length < 2) continue;
      if (RegExp(r'^[\d\s\-\+\*\.\,\/\\@#]+$').hasMatch(line)) continue;

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
        }
        name = name.replaceAll(match.group(0)!, '').trim();
      }

      // "جديد" بدون رقم
      if (line.contains('جديد') && !isNewPrice) {
        isNewPrice = true;
        name = name.replaceAll('جديد', '').trim();
      }

      // ملاحظات: بديل
      if (name.contains('بديل')) {
        final parts = name.split('بديل');
        name = parts[0].trim();
        notes = 'بديل ${parts[1].trim()}';
      }

      // ملاحظات: تأكيد
      if (name.contains('؟') || name.contains('?')) {
        notes = notes == null ? 'تأكيد؟' : '$notes · تأكيد؟';
        name = name.replaceAll('؟', '').replaceAll('?', '').trim();
      }

      // ── تنظيف الاسم ──
      name = name.replaceAll('/', ' ').replaceAll('-', ' ').trim();
      name = name.replaceAll(RegExp(r'^[@#\*\+]+'), '').trim();
      name = name.replaceAllMapped(
        RegExp(r'([\u0600-\u06FF])\1{2,}'),
        (m) => m.group(1)! * 2,
      );
      name = name.replaceAllMapped(
        RegExp(r'([a-zA-Z])\1{2,}', caseSensitive: false),
        (m) => m.group(1)! * 2,
      );
      name = name.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      name = name
          .replaceAll(RegExp(r'^\d+\s+'), '')
          .replaceAll(RegExp(r'\s+\d+$'), '')
          .trim();

      if (name.length < 2) continue;

      final key = name.toLowerCase();
      uniqueItems[key] = ParsedItem(
        originalText: line,
        name: name,
        price: price,
        isNewPrice: isNewPrice,
        notes: notes,
      );
    }

    await _saveNewItemsToDictionary(
        uniqueItems.values.map((e) => e.name).toList());

    setState(() {
      _parsedItems = uniqueItems.values.toList();
      _parsedItems.sort((a, b) {
        if (a.price != null && b.price == null) return -1;
        if (a.price == null && b.price != null) return 1;
        return 0;
      });
      _filteredItems = List.from(_parsedItems);
      _searchCtrl.clear();
      _isParsing = false;
    });

    await _loadStoredPrices();
    if (mounted) {
      setState(() {});
      _fadeCtrl.forward();
    }
  }

  Future<void> _loadStoredPrices() async {
    try {
      final dictStr =
          await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
      if (dictStr == null) return;

      final List<dynamic> decoded = jsonDecode(dictStr);
      final drugList = decoded.cast<Map<String, dynamic>>();

      for (var item in _parsedItems) {
        final found = drugList.firstWhere(
          (d) =>
              (d['enName']?.toString().toLowerCase() ?? '') ==
              item.name.toLowerCase(),
          orElse: () => {},
        );
        if (found.isNotEmpty && found['price'] != null) {
          final p = double.tryParse(found['price'].toString());
          if (p != null && p > 0) {
            item.storedPrice = p;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading stored prices: $e');
    }
  }

  Future<void> _saveNewItemsToDictionary(List<String> names) async {
    try {
      final dictStr =
          await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
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
            (d['enName']?.toString().toLowerCase() ?? '') ==
            name.toLowerCase());
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
        await DatabaseHelper.instance
            .setSetting('drug_dictionary_v2', jsonEncode(drugList));
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

    final pharmacyName =
        await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدليتي';
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
          showSnack(
              context,
              SupabaseService.instance.lastError ??
                  'فشل إنشاء الطلب، يرجى المحاولة لاحقاً',
              isError: true);
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LinkSheet(
        repName: _selectedRep?.name ?? '',
        repPhone: _selectedRep?.phone ?? '',
        generatedLink: _generatedLink ?? '',
        sessionCode: _sessionCode,
        countryCode: _countryCode,
        onViewResponse: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    RepResponseScreen(initialCode: _sessionCode)),
          );
        },
        onSnack: (msg) => showSnack(ctx, msg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int selectedCount = _parsedItems.where((i) => i.isSelected).length;
    final displayItems = _filteredItems;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RepSelectorCard(
                    selectedRep: _selectedRep,
                    onTap: _showSelectRepDialog,
                  ),
                  const SizedBox(height: 20),
                  _MessageInputSection(
                    controller: _messageCtrl,
                    isParsing: _isParsing,
                    onParse: _parseMessage,
                  ),
                  if (_parsedItems.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _buildResultsHeader(),
                    const SizedBox(height: 12),
                    _buildSearchBar(),
                    const SizedBox(height: 4),
                    if (_filteredItems.isEmpty &&
                        _searchCtrl.text.isNotEmpty)
                      _buildEmptySearch(),
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Column(
                        children: displayItems
                            .map((item) => _ItemCard(
                                  item: item,
                                  currency: _currency,
                                  onChanged: (val) =>
                                      setState(() => item.isSelected = val ?? false),
                                  onQtyDecrease: () =>
                                      setState(() => item.quantity--),
                                  onQtyIncrease: () =>
                                      setState(() => item.quantity++),
                                  onQtyEdit: () => _showQtyDialog(item),
                                  onSearch: () => _searchGoogle(item.name),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
          _BottomBar(
            selectedCount: selectedCount,
            sending: _sending,
            onSend: selectedCount > 0 && !_sending ? _sendOrder : null,
            currency: _currency,
            parsedItems: _parsedItems,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D0F14),
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: Color(0xFF8A8FA8), size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C896), Color(0xFF00A37A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تحليل رسائل المندوبين',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo')),
              Text('استخراج الأصناف والأسعار تلقائياً',
                  style: TextStyle(
                      color: Color(0xFF8A8FA8),
                      fontSize: 11,
                      fontFamily: 'Cairo')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsHeader() {
    final allSelected = _parsedItems.every((i) => i.isSelected);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25), width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              Text('${_parsedItems.length} صنف',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo')),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() {
            for (var item in _parsedItems) {
              item.isSelected = !allSelected;
            }
          }),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: allSelected
                  ? Colors.red.withValues(alpha: 0.1)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: allSelected
                      ? Colors.red.withValues(alpha: 0.3)
                      : AppColors.primary.withValues(alpha: 0.3),
                  width: 1),
            ),
            child: Row(
              children: [
                Icon(
                    allSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                    color: allSelected ? Colors.red : AppColors.primary,
                    size: 14),
                const SizedBox(width: 6),
                Text(
                    allSelected ? 'إلغاء الكل' : 'تحديد الكل',
                    style: TextStyle(
                        color: allSelected ? Colors.red : AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF252A3A), width: 1),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _filterItems,
        style: const TextStyle(
            color: Colors.white, fontSize: 14, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          hintText: 'ابحث عن صنف...',
          hintStyle: const TextStyle(
              color: Color(0xFF8A8FA8), fontSize: 13, fontFamily: 'Cairo'),
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.primary, size: 20),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF8A8FA8), size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _filterItems('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildEmptySearch() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.search_off_rounded,
                color: const Color(0xFF8A8FA8).withValues(alpha: 0.5),
                size: 36),
            const SizedBox(height: 8),
            const Text('لا توجد نتائج مطابقة',
                style: TextStyle(
                    color: Color(0xFF8A8FA8),
                    fontSize: 14,
                    fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  Future<void> _showQtyDialog(ParsedItem item) async {
    final controller =
        TextEditingController(text: '${item.quantity}');
    final newQty = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF161B26),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تعديل الكمية',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
              const SizedBox(height: 4),
              Text(item.name,
                  style: const TextStyle(
                      color: Color(0xFF8A8FA8),
                      fontSize: 12,
                      fontFamily: 'Cairo'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'Cairo'),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: 'الكمية',
                  hintStyle: const TextStyle(color: Color(0xFF8A8FA8)),
                  filled: true,
                  fillColor: const Color(0xFF0D0F14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF252A3A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF252A3A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                                color: Color(0xFF252A3A))),
                      ),
                      child: const Text('إلغاء',
                          style: TextStyle(
                              color: Color(0xFF8A8FA8),
                              fontFamily: 'Cairo')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final val = int.tryParse(controller.text);
                        if (val != null && val > 0) {
                          Navigator.pop(ctx, val);
                        } else {
                          Navigator.pop(ctx);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('حفظ',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (newQty != null) setState(() => item.quantity = newQty);
  }

  Future<void> _searchGoogle(String name) async {
    final url =
        Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(name)}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showSnack(context, 'تعذر فتح المتصفح', isError: true);
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// ── Sub-Widgets ──
// ══════════════════════════════════════════════════════════════════

class _RepSelectorCard extends StatelessWidget {
  final Representative? selectedRep;
  final VoidCallback onTap;
  const _RepSelectorCard({required this.selectedRep, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasRep = selectedRep != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasRep
              ? AppColors.primary.withValues(alpha: 0.07)
              : const Color(0xFF161B26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasRep
                ? AppColors.primary.withValues(alpha: 0.35)
                : const Color(0xFF252A3A),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: hasRep
                    ? const LinearGradient(
                        colors: [Color(0xFF00C896), Color(0xFF00A37A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: hasRep ? null : const Color(0xFF252A3A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                hasRep ? Icons.person_rounded : Icons.person_add_alt_rounded,
                color: hasRep ? Colors.white : const Color(0xFF8A8FA8),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasRep ? selectedRep!.name : 'اختر المندوب',
                    style: TextStyle(
                        color: hasRep ? Colors.white : const Color(0xFF8A8FA8),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        fontFamily: 'Cairo'),
                  ),
                  if (hasRep && selectedRep!.company != null)
                    Text(
                      selectedRep!.company!,
                      style: const TextStyle(
                          color: Color(0xFF8A8FA8),
                          fontSize: 12,
                          fontFamily: 'Cairo'),
                    )
                  else
                    const Text(
                      'اضغط لاختيار مندوب من القائمة',
                      style: TextStyle(
                          color: Color(0xFF8A8FA8),
                          fontSize: 11,
                          fontFamily: 'Cairo'),
                    ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasRep ? 'تغيير' : 'اختيار',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageInputSection extends StatelessWidget {
  final TextEditingController controller;
  final bool isParsing;
  final VoidCallback onParse;
  const _MessageInputSection(
      {required this.controller,
      required this.isParsing,
      required this.onParse});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text('رسالة المندوب',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    fontFamily: 'Cairo')),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161B26),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: const Color(0xFF252A3A), width: 1),
          ),
          child: TextField(
            controller: controller,
            maxLines: 8,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.6,
                fontFamily: 'Cairo'),
            decoration: const InputDecoration(
              hintText:
                  'الصق رسالة الواتساب هنا...\nمثال:\nبروفين شراب جديد 44ج\nنانازوكسيد شراب 39 ج.م',
              hintStyle: TextStyle(
                  color: Color(0xFF555D72),
                  fontSize: 12,
                  height: 1.7,
                  fontFamily: 'Cairo'),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isParsing ? null : onParse,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: isParsing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 10),
                      Text('جاري التحليل...',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Cairo')),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('تحليل الرسالة',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              fontFamily: 'Cairo')),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  final ParsedItem item;
  final String currency;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onQtyDecrease;
  final VoidCallback onQtyIncrease;
  final VoidCallback onQtyEdit;
  final VoidCallback onSearch;

  const _ItemCard({
    required this.item,
    required this.currency,
    required this.onChanged,
    required this.onQtyDecrease,
    required this.onQtyIncrease,
    required this.onQtyEdit,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final bool needsConfirmation =
        item.notes != null && item.notes!.contains('تأكيد');
    final bool hasRepPrice = item.price != null;
    final bool hasStoredPrice = item.storedPrice != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: item.isSelected
            ? AppColors.primary.withValues(alpha: 0.07)
            : const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isSelected
              ? AppColors.primary.withValues(alpha: 0.4)
              : const Color(0xFF252A3A),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox
                Transform.scale(
                  scale: 0.9,
                  child: Checkbox(
                    value: item.isSelected,
                    activeColor: AppColors.primary,
                    checkColor: Colors.white,
                    side: const BorderSide(
                        color: Color(0xFF555D72), width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                    onChanged: onChanged,
                  ),
                ),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    fontFamily: 'Cairo'),
                              ),
                            ),
                            if (item.isNewPrice) ...[
                              const SizedBox(width: 6),
                              _Badge(
                                  label: 'جديد',
                                  color: AppColors.accent,
                                  icon: Icons.fiber_new_rounded),
                            ],
                            if (needsConfirmation) ...[
                              const SizedBox(width: 6),
                              _Badge(
                                  label: 'تأكيد؟',
                                  color: AppColors.warning,
                                  icon: Icons.help_outline_rounded),
                            ],
                            GestureDetector(
                              onTap: onSearch,
                              child: Container(
                                margin: const EdgeInsets.only(right: 4, left: 4),
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF252A3A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.search_rounded,
                                    color: Color(0xFF8A8FA8), size: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Prices row
                        Row(
                          children: [
                            // سعر المندوب
                            _PriceChip(
                              label: 'المندوب',
                              value: hasRepPrice
                                  ? '${item.price} $currency'
                                  : '—',
                              color: hasRepPrice
                                  ? AppColors.primary
                                  : const Color(0xFF555D72),
                              icon: Icons.local_offer_rounded,
                            ),
                            if (hasStoredPrice) ...[
                              const SizedBox(width: 8),
                              _PriceChip(
                                label: 'مخزن',
                                value: '${item.storedPrice} $currency',
                                color: const Color(0xFF6C8EFF),
                                icon: Icons.inventory_2_rounded,
                              ),
                            ],
                          ],
                        ),

                        // Notes
                        if (item.notes != null && !needsConfirmation) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: Color(0xFF555D72), size: 12),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.notes!,
                                  style: const TextStyle(
                                      color: Color(0xFF8A8FA8),
                                      fontSize: 11,
                                      fontFamily: 'Cairo'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Quantity control
                _QtyControl(
                  qty: item.quantity,
                  enabled: item.isSelected,
                  onDecrease: item.quantity > 1 ? onQtyDecrease : null,
                  onIncrease: onQtyIncrease,
                  onEdit: onQtyEdit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _PriceChip(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo'),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Badge(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  final int qty;
  final bool enabled;
  final VoidCallback? onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onEdit;
  const _QtyControl(
      {required this.qty,
      required this.enabled,
      this.onDecrease,
      required this.onIncrease,
      required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final activeColor =
        enabled ? AppColors.primary : const Color(0xFF555D72);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? AppColors.primary.withValues(alpha: 0.2)
              : const Color(0xFF252A3A),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _QtyBtn(
              icon: Icons.add,
              color: activeColor,
              onTap: enabled ? onIncrease : null),
          GestureDetector(
            onTap: enabled ? onEdit : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                '$qty',
                style: TextStyle(
                    color: enabled ? AppColors.primary : const Color(0xFF555D72),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    fontFamily: 'Cairo'),
              ),
            ),
          ),
          _QtyBtn(
              icon: Icons.remove,
              color: onDecrease != null ? activeColor : const Color(0xFF2A2F3A),
              onTap: enabled ? onDecrease : null),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _QtyBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int selectedCount;
  final bool sending;
  final VoidCallback? onSend;
  final String currency;
  final List<ParsedItem> parsedItems;

  const _BottomBar({
    required this.selectedCount,
    required this.sending,
    required this.onSend,
    required this.currency,
    required this.parsedItems,
  });

  @override
  Widget build(BuildContext context) {
    final selected = parsedItems.where((i) => i.isSelected).toList();
    final totalItems = selected.fold<int>(0, (s, i) => s + i.quantity);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: const BoxDecoration(
        color: Color(0xFF161B26),
        border: Border(top: BorderSide(color: Color(0xFF252A3A), width: 1)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Stats
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('المحدد',
                    style: TextStyle(
                        color: Color(0xFF8A8FA8),
                        fontSize: 11,
                        fontFamily: 'Cairo')),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$selectedCount',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          fontFamily: 'Cairo'),
                    ),
                    if (totalItems > selectedCount) ...[
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '($totalItems وحدة)',
                          style: const TextStyle(
                              color: Color(0xFF8A8FA8),
                              fontSize: 11,
                              fontFamily: 'Cairo'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: onSend,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        const Color(0xFF252A3A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: sending
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            ),
                            SizedBox(width: 10),
                            Text('جاري الإرسال...',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo')),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send_rounded,
                                size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              selectedCount > 0
                                  ? 'إرسال $selectedCount صنف'
                                  : 'إرسال الطلب',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepSelectSheet extends StatelessWidget {
  final List<Map<String, dynamic>> reps;
  final ValueChanged<Representative> onSelect;
  const _RepSelectSheet({required this.reps, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161B26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFF252A3A),
                borderRadius: BorderRadius.circular(99)),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.people_rounded,
                    color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Text('اختر المندوب',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF252A3A), height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: reps.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: Color(0xFF1E2330), height: 1),
              itemBuilder: (ctx, i) {
                final rep = Representative.fromMap(reps[i]);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 4),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C896), Color(0xFF00A37A)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        rep.name.isNotEmpty
                            ? rep.name[0].toUpperCase()
                            : '؟',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                    ),
                  ),
                  title: Text(rep.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Cairo')),
                  subtitle: rep.company != null
                      ? Text(rep.company!,
                          style: const TextStyle(
                              color: Color(0xFF8A8FA8),
                              fontSize: 12,
                              fontFamily: 'Cairo'))
                      : null,
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Color(0xFF555D72)),
                  onTap: () => onSelect(rep),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _LinkSheet extends StatelessWidget {
  final String repName;
  final String repPhone;
  final String generatedLink;
  final String? sessionCode;
  final String countryCode;
  final VoidCallback onViewResponse;
  final ValueChanged<String> onSnack;

  const _LinkSheet({
    required this.repName,
    required this.repPhone,
    required this.generatedLink,
    required this.sessionCode,
    required this.countryCode,
    required this.onViewResponse,
    required this.onSnack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161B26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFF252A3A),
                borderRadius: BorderRadius.circular(99)),
          ),
          const SizedBox(height: 20),
          // Success Icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C896), Color(0xFF00A37A)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(height: 14),
          const Text('تم إنشاء الرابط!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 4),
          Text('أرسل الرابط لـ $repName',
              style: const TextStyle(
                  color: Color(0xFF8A8FA8),
                  fontSize: 13,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 20),

          // Link Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0F14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF252A3A), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    generatedLink,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontFamily: 'Cairo'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded,
                      color: AppColors.primary, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: generatedLink));
                    onSnack('تم نسخ الرابط ✅');
                  },
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  label: 'واتساب',
                  icon: Icons.message_rounded,
                  color: const Color(0xFF25D366),
                  onTap: () async {
                    final msg =
                        'مرحباً $repName،\nيرجى مراجعة الطلبية والرد عبر الرابط:\n$generatedLink';
                    final formattedPhone = repPhone.isNotEmpty
                        ? CountryConfig.formatPhone(repPhone, countryCode)
                            .replaceAll('+', '')
                        : '';
                    final urlStr = formattedPhone.isNotEmpty
                        ? 'https://wa.me/$formattedPhone?text=${Uri.encodeComponent(msg)}'
                        : 'https://wa.me/?text=${Uri.encodeComponent(msg)}';
                    try {
                      if (!await launchUrl(Uri.parse(urlStr),
                          mode: LaunchMode.externalApplication)) {
                        throw Exception('Could not launch');
                      }
                    } catch (e) {
                      Clipboard.setData(ClipboardData(text: msg));
                      onSnack('تم نسخ الرسالة - افتح واتساب يدويًا');
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  label: 'نسخ الرابط',
                  icon: Icons.copy_rounded,
                  color: const Color(0xFF555D72),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: generatedLink));
                    onSnack('تم نسخ الرابط ✅');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: onViewResponse,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(
                    color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text('استقبال رد المندوب',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        icon: Icon(icon, size: 16, color: Colors.white),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo')),
      ),
    );
  }
}
