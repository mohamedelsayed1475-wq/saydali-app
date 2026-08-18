import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_theme.dart';
import '../utils/fuzzy_search.dart';
import '../database/database_helper.dart';
import '../providers/app_providers.dart';
import '../providers/current_user_provider.dart';

class RapidShortagesEntryScreen extends StatefulWidget {
  const RapidShortagesEntryScreen({super.key});

  @override
  State<RapidShortagesEntryScreen> createState() => _RapidShortagesEntryScreenState();
}

class _RapidShortagesEntryScreenState extends State<RapidShortagesEntryScreen> {
  final _nameController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _nameFocusNode = FocusNode();
  final _qtyFocusNode = FocusNode();

  List<Map<String, dynamic>> _drugDictionary = [];
  List<Map<String, dynamic>> _filteredSuggestions = [];
  final List<Map<String, dynamic>> _recentAddedItems = [];

  @override
  void initState() {
    super.initState();
    _loadDrugDictionary();
    // إعطاء التركيز فوراً لحقل الاسم عند فتح الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _nameFocusNode.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDrugDictionary() async {
    try {
      final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary_v2') ??
          await DatabaseHelper.instance.getSetting('drug_dictionary');
      if (dictStr != null && dictStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(dictStr);
        _drugDictionary = decoded.map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return {'enName': e.toString()};
        }).toList();
      }
    } catch (_) {}
  }

  void _onNameChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() => _filteredSuggestions = []);
      return;
    }

    final q = query.trim();
    final results = _drugDictionary.where((item) {
      final en = item['enName']?.toString() ?? '';
      final ar = item['arName']?.toString() ?? '';
      return FuzzySearch.match(q, en) || FuzzySearch.match(q, ar);
    }).take(6).toList();

    setState(() => _filteredSuggestions = results);
  }

  void _selectSuggestion(Map<String, dynamic> item) {
    final name = (item['arName'] != null && item['arName'].toString().isNotEmpty)
        ? item['arName'].toString()
        : (item['enName']?.toString() ?? '');

    _nameController.text = name;
    _filteredSuggestions.clear();
    setState(() {});

    // الانتقال المباشر لحقل الكمية مع تحديد النص لتسهيل تغييره بضغطة واحدة
    _qtyFocusNode.requestFocus();
    _qtyController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _qtyController.text.length,
    );
  }

  void _onNameSubmitted(String value) {
    final name = value.trim();
    if (name.isEmpty) {
      _nameFocusNode.requestFocus();
      return;
    }

    // الانتقال التلقائي لحقل الكمية وتحديد الرقم الافتراضي
    _qtyFocusNode.requestFocus();
    _qtyController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _qtyController.text.length,
    );
  }

  Future<void> _onQtySubmitted(String value) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _nameFocusNode.requestFocus();
      return;
    }

    final qty = int.tryParse(value.trim()) ?? 1;
    final finalQty = qty <= 0 ? 1 : qty;

    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canManageShortages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⛔ ليس لديك صلاحية لإضافة نواقص')),
      );
      return;
    }

    // 1. إضافة الصنف إلى مزود النواقص وقاعدة البيانات
    final shortageData = {
      'name': name,
      'company': 'غير محدد',
      'quantity': finalQty,
      'status': 'pending',
      'is_urgent': 0,
    };

    final id = await context.read<ShortagesProvider>().add(shortageData);

    // 2. حفظ الصنف في قاموس الأدوية المحلي إن لم يكن موجوداً
    _saveToDictionary(name);

    // 3. إضافة الصنف للقائمة المصغرة لهذه الجلسة
    setState(() {
      _recentAddedItems.insert(0, {
        'id': id,
        'name': name,
        'quantity': finalQty,
        'added_at': DateTime.now(),
      });
      _filteredSuggestions.clear();
      _nameController.clear();
      _qtyController.text = '1';
    });

    // 4. إعادة التركيز فوراً وبشكل تلقائي لحقل اسم الصنف التالي بدون لمس الشاشة
    _nameFocusNode.requestFocus();
  }

  Future<void> _saveToDictionary(String drugName) async {
    try {
      final exists = _drugDictionary.any((d) =>
          (d['enName']?.toString().toLowerCase() ?? '') == drugName.toLowerCase() ||
          (d['arName']?.toString().toLowerCase() ?? '') == drugName.toLowerCase());

      if (exists) return;

      final newItem = {
        'enName': drugName,
        'arName': '',
        'activeIngredient': '',
        'company': 'غير محدد',
        'barcode': '',
        'price': 0,
      };

      _drugDictionary.add(newItem);
      await DatabaseHelper.instance.setSetting(
        'drug_dictionary_v2',
        jsonEncode(_drugDictionary),
      );
    } catch (_) {}
  }

  Future<void> _deleteRecentItem(int index) async {
    final item = _recentAddedItems[index];
    final id = item['id'];
    if (id != null) {
      await context.read<ShortagesProvider>().delete(id is int ? id : int.parse(id.toString()));
    }

    setState(() {
      _recentAddedItems.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم حذف "${item['name']}" من النواقص'),
        duration: const Duration(seconds: 2),
      ),
    );

    // الحفاظ على التركيز على حقل الاسم
    _nameFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        backgroundColor: AppColors.darkCard,
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Color(0xFF00D4B4), size: 24),
            SizedBox(width: 8),
            Text(
              'إدخال سريع للنواقص ⚡',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary),
            ),
            child: Text(
              'أُضيف: ${_recentAddedItems.length}',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // بطاقة الإدخال السريع المركّزة
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.darkCard,
                border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اكتب اسم الدواء ثم اضغط Enter ↵ لنقل الكمية والحفظ التلقائي:',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      // حقل اسم الصنف (مركّز عليه دائماً)
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'اسم الصنف الناقص...',
                            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                            fillColor: AppColors.dark,
                            filled: true,
                            prefixIcon: const Icon(Icons.medication_rounded, color: AppColors.primary, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.darkBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          onChanged: _onNameChanged,
                          onSubmitted: _onNameSubmitted,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // حقل الكمية
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _qtyController,
                          focusNode: _qtyFocusNode,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: 'الكمية',
                            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            fillColor: AppColors.dark,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.darkBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF00D4B4), width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                          ),
                          onSubmitted: _onQtySubmitted,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // زر الحفظ اليدوي السريع
                      IconButton.filled(
                        onPressed: () => _onQtySubmitted(_qtyController.text),
                        icon: const Icon(Icons.keyboard_return_rounded, color: Colors.black),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.all(14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        tooltip: 'حفظ (Enter)',
                      ),
                    ],
                  ),

                  // اقتراحات البحث الذكي (Fuzzy Search Suggestions)
                  if (_filteredSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filteredSuggestions.map((item) {
                          final name = (item['arName'] != null && item['arName'].toString().isNotEmpty)
                              ? item['arName'].toString()
                              : (item['enName']?.toString() ?? '');
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ActionChip(
                              label: Text(name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                              backgroundColor: const Color(0xFF1E3A5F),
                              side: const BorderSide(color: Color(0xFF2D5A8E)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              onPressed: () => _selectSuggestion(item),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ترويسة قائمة الجلسة الحالية
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'الأصناف المضافة في هذه الجلسة (${_recentAddedItems.length})',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (_recentAddedItems.isNotEmpty)
                    Text(
                      'تُحفظ مباشرة في النواقص ✅',
                      style: TextStyle(color: AppColors.primary.withValues(alpha: 0.8), fontSize: 10),
                    ),
                ],
              ),
            ),

            // قائمة الأصناف المضافة
            Expanded(
              child: _recentAddedItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.keyboard_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 10),
                          const Text(
                            'ابدأ بالكتابة فوراً والضغط على Enter ↵',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'سيتم الحفظ والعودة لحقل الاسم تلقائياً لإضافة الصنف التالي',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      itemCount: _recentAddedItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = _recentAddedItems[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.darkCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                child: Text(
                                  '${_recentAddedItems.length - index}',
                                  style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item['name'] ?? '',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.dark,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.darkBorder),
                                ),
                                child: Text(
                                  'الكمية: ${item['quantity']}',
                                  style: const TextStyle(color: Color(0xFF00D4B4), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: AppColors.danger, size: 18),
                                tooltip: 'حذف التراجع',
                                onPressed: () => _deleteRecentItem(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // شريط سفلي للإنهاء
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.darkCard,
                border: Border(top: BorderSide(color: AppColors.darkBorder)),
              ),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('تم والعودة لشاشة النواقص ✅', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
