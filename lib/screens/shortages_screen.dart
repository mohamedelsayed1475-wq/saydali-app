import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'send_to_rep_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/fuzzy_search.dart';
import '../providers/current_user_provider.dart';


import 'package:flutter/services.dart';
import 'scanner_screen.dart';
import 'rep_message_parser_screen.dart';
import 'alternatives_screen.dart';
import 'rapid_shortages_entry_screen.dart';

class ShortagesScreen extends StatefulWidget {
  const ShortagesScreen({super.key});

  @override
  State<ShortagesScreen> createState() => _ShortagesScreenState();
}

class _ShortagesScreenState extends State<ShortagesScreen> {
  List<Map<String, dynamic>> _suggestions = [];
  final _searchController = TextEditingController();

  // Wizard quick add variables
  int _wizardStep = 1;
  final _wizardNameCtrl = TextEditingController();
  int _wizardQty = 1;
  bool _wizardIsUrgent = false;
  bool _showSearchField = false;

  final _filters = [
    ('all', 'الكل'),
    ('pending', 'انتظار'),
    ('offered', 'عروض'),
    ('covered', 'مغطى'),
    ('stubborn', 'مستعصي'),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _wizardNameCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadShortages(silent: false);
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final dictStr =
        await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        if (mounted)
          setState(() => _suggestions = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      } catch (e) {}
    } else {
      final oldDictStr =
          await DatabaseHelper.instance.getSetting('drug_dictionary');
      if (oldDictStr != null) {
        try {
          final List<dynamic> decoded = jsonDecode(oldDictStr);
          if (mounted)
            setState(() => _suggestions =
                decoded.map((s) => {'enName': s.toString()}).toList());
        } catch (e) {}
      }
    }
  }

  Future<void> _loadShortages({bool silent = false}) async {
    await context.read<ShortagesProvider>().load(silent: silent);
  }

  // Filtering delegated to ShortagesProvider.filtered

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
            const Text('اختر المندوب لإرسال النواقص',
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
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => SendToRepScreen(rep: rep)));
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

  Future<void> _importExcel() async {
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canManageShortages) {
      showSnack(context, '⛔ ليس لديك صلاحية إدارة النواقص', isError: true);
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final bytes = File(result.files.single.path!).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      int count = 0;

      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table]!;
        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.row(i);
          if (row.isEmpty || row[0]?.value == null) continue;

          final name = row[0]?.value?.toString().trim() ?? '';
          if (name.isEmpty) continue;

          final company = row.length > 1
              ? (row[1]?.value?.toString() ?? 'غير محدد')
              : 'غير محدد';
          final qty = row.length > 2
              ? (int.tryParse(row[2]?.value?.toString() ?? '') ?? 1)
              : 1;

          await context.read<ShortagesProvider>().add({
            'name': name,
            'company': company,
            'quantity': qty,
            'status': 'pending',
            'is_urgent': 0,
          });
          count++;
        }
      }

      await _loadShortages();
      if (mounted) showSnack(context, 'تم استيراد $count صنف من Excel ✅');
    } catch (e) {
      if (mounted) showSnack(context, 'خطأ في قراءة الملف', isError: true);
    }
  }

  void _openRapidEntry() {
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canManageShortages) {
      showSnack(context, '⛔ ليس لديك صلاحية لإدارة النواقص', isError: true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RapidShortagesEntryScreen()),
    );
  }

  Future<void> _searchGoogleImages(String query) async {
    if (query.trim().isEmpty) {
      if (mounted)
        showSnack(context, 'الرجاء إدخال اسم الدواء للبحث', isError: true);
      return;
    }
    final url = Uri.parse(
        'https://www.google.com/search?tbm=isch&q=${Uri.encodeComponent(query)}+دواء');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }



  /// ▌ حفظ دواء جديد في القاموس المحلي تلقائياً
  Future<void> _saveDrugToDictionary(String drugName, {String? company}) async {
    try {
      // ▌ جيب القاموس الحالي
      final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
      List<Map<String, dynamic>> drugList = [];
      
      if (dictStr != null) {
        try {
          final List<dynamic> decoded = jsonDecode(dictStr);
          drugList = decoded.cast<Map<String, dynamic>>();
        } catch (_) {}
      }

      // ▌ تأكد إن الدواء مش موجود بالفعل
      final exists = drugList.any((d) => 
        (d['enName']?.toString().toLowerCase() ?? '') == drugName.toLowerCase()
      );

      if (exists) return; // مفيش لازمة نضيفه تاني

      // ▌ أضف الدواء الجديد
      drugList.add({
        'enName': drugName,
        'arName': '',
        'activeIngredient': '',
        'company': company ?? 'غير محدد',
        'barcode': '',
        'price': 0,
      });

      // ▌ خزّن القاموس المحدث
      await DatabaseHelper.instance.setSetting('drug_dictionary_v2', jsonEncode(drugList));

      // ▌ حدّث القائمة في الميموري
      setState(() {
        _suggestions = drugList;
      });

      debugPrint('✅ تم حفظ "$drugName" في القاموس المحلي');
    } catch (e) {
      debugPrint('❌ فشل حفظ الدواء: $e');
    }
  }

  Future<void> _showAddSheet({Shortage? existing, String? initialName, String? initialCompany}) async {
    // فحص صلاحية إدارة النواقص
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canManageShortages) {
      showSnack(context, '⛔ ليس لديك صلاحية إدارة النواقص', isError: true);
      return;
    }
    final nameCtrl = TextEditingController(text: initialName ?? existing?.name ?? '');

    final companyCtrl = TextEditingController(text: initialCompany ?? existing?.company);
    final qtyCtrl =
        TextEditingController(text: existing?.quantity.toString() ?? '1');
    final notesCtrl = TextEditingController(text: existing?.notes);
    bool isUrgent = existing?.isUrgent ?? false;
    String status = existing?.status ?? 'pending';

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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                Text(existing == null ? '➕ إضافة ناقص جديد' : '✏️ تعديل الناقص',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Autocomplete<Map<String, dynamic>>(
                        initialValue: TextEditingValue(text: initialName ?? existing?.name ?? ''),
                        optionsBuilder: (v) {
                          if (v.text.isEmpty) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }

                          final query = v.text;

                          // ① اقتراحات القاموس المحلي
                          final dictMatches = _suggestions.map((s) {
                            final en = s['enName']?.toString() ?? '';
                            final ar = s['arName']?.toString() ?? '';
                            final act = s['activeIngredient']?.toString() ?? '';
                            final bar = s['barcode']?.toString() ?? '';
                            final scoreEn = FuzzySearch.getScore(query, en);
                            final scoreAr = FuzzySearch.getScore(query, ar);
                            final scoreAct = FuzzySearch.getScore(query, act);
                            final scoreBar = bar.contains(query.trim()) ? 1000 : 0;
                            final maxScore = [scoreEn, scoreAr, scoreAct, scoreBar].reduce((a, b) => a > b ? a : b);
                            return {'item': s, 'score': maxScore};
                          }).where((e) => (e['score'] as int) > 0).toList();

                          // الترتيب حسب الأعلى تقييماً
                          dictMatches.sort((a, b) =>
                              (b['score'] as int).compareTo(a['score'] as int));

                          return dictMatches
                              .map((e) => e['item'] as Map<String, dynamic>)
                              .take(14);
                        },
                        displayStringForOption: (option) =>
                            option['enName']?.toString() ?? '',
                        onSelected: (s) {
                          nameCtrl.text = s['enName']?.toString() ?? '';
                          if (s['company'] != null && s['company'].toString() != 'غير محدد') {
                            companyCtrl.text = s['company'].toString();
                          }
                        },
                        fieldViewBuilder: (ctx, ctrl, fn, onSubmit) {
                          return AppTextField(
                            hint: 'اسم الدواء *',
                            controller: ctrl,
                            focusNode: fn,
                            onSubmitted: (_) => onSubmit(),
                            onChanged: (val) {
                              nameCtrl.text = val;
                            },
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
                                side: const BorderSide(
                                    color: AppColors.darkBorder),
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    maxHeight: 250, maxWidth: 300),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                    final option = options.elementAt(index);
                                    final en = option['enName']?.toString() ?? '';
                                    final ar = option['arName']?.toString() ?? '';
                                    final act = option['activeIngredient']?.toString() ?? '';

                                    return InkWell(
                                      onTap: () {
                                        onSelected(option);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(en,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14)),
                                                ),
                                                if (option['company'] != null && option['company'].toString().isNotEmpty && option['company'].toString() != 'غير محدد')
                                                  Text(option['company'].toString(),
                                                      style: const TextStyle(
                                                          color: AppColors.textMuted,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                            if (ar.isNotEmpty)
                                              Text(ar,
                                                  style: const TextStyle(
                                                      color: AppColors.primary,
                                                      fontSize: 12)),
                                            if (act.isNotEmpty)
                                              Text(act,
                                                  style: const TextStyle(
                                                      color: AppColors.textMuted,
                                                      fontSize: 11)),
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
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.qr_code_scanner,
                            color: AppColors.primary),
                        onPressed: () async {
                          Navigator.pop(context);
                          final code = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ScannerScreen()));
                          if (code != null && code.isNotEmpty) {
                            // ابحث أولاً في القاموس المحلي عن باركود مطابق
                            final match = _suggestions.firstWhere(
                              (s) => s['barcode']?.toString().trim() == code.trim(),
                              orElse: () => <String, dynamic>{},
                            );
                            if (match.isNotEmpty) {
                              debugPrint('🔍 [SHORTAGES_SCANNER] تم العثور على الدواء المطابق للرمز $code في القاموس: ${match['enName']}');
                              _showAddSheet(
                                initialName: match['enName']?.toString(),
                                initialCompany: (match['company'] != null && match['company'].toString() != 'غير محدد')
                                    ? match['company'].toString()
                                    : null,
                              );
                            } else {
                              debugPrint('🔍 [SHORTAGES_SCANNER] لم يتم العثور على الرمز $code في القاموس المحلي');
                              _showAddSheet(initialName: code);
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.search, color: Colors.blue),
                        onPressed: () => _searchGoogleImages(nameCtrl.text),
                        tooltip: 'بحث في جوجل (صور)',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                AppTextField(hint: 'الشركة المصنعة', controller: companyCtrl),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'الكمية',
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'ملاحظات (اختياري)',
                    controller: notesCtrl,
                    maxLines: 2),
                const SizedBox(height: 10),

                // الحالة
                if (existing != null) ...[
                  const Text('الحالة',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in [
                        'pending',
                        'offered',
                        'covered',
                        'stubborn'
                      ])
                        ChoiceChip(
                          label: Text(Shortage(
                                  name: '',
                                  status: s,
                                  createdAt: DateTime.now(),
                                  updatedAt: DateTime.now())
                              .statusLabel),
                          selected: status == s,
                          onSelected: (_) => setBS(() => status = s),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.dark,
                          labelStyle: TextStyle(
                              color: status == s
                                  ? Colors.white
                                  : AppColors.textMuted,
                              fontSize: 12),
                          side: BorderSide(
                              color: status == s
                                  ? AppColors.primary
                                  : AppColors.darkBorder),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // عاجل
                Row(
                  children: [
                    Switch(
                        value: isUrgent,
                        onChanged: (v) => setBS(() => isUrgent = v),
                        activeThumbColor: AppColors.danger),
                    const Text('عاجل 🚨',
                        style: TextStyle(color: AppColors.textLight)),
                  ],
                ),
                const SizedBox(height: 16),

                PrimaryButton(
                  text: existing == null ? 'إضافة' : 'حفظ التعديلات',
                  onTap: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      showSnack(ctx, 'أدخل اسم الدواء', isError: true);
                      return;
                    }


                    final data = {
                      'name': name,
                      'company': companyCtrl.text.trim().isEmpty
                          ? 'غير محدد'
                          : companyCtrl.text.trim(),
                      'quantity': int.tryParse(qtyCtrl.text) ?? 1,
                      'is_urgent': isUrgent ? 1 : 0,
                      'notes': notesCtrl.text.trim(),
                      if (existing != null) 'status': status,
                    };

                    if (existing == null) {
                      await context.read<ShortagesProvider>().add(data);
                      
                      // ▌ حفظ الدواء في القاموس المحلي تلقائياً
                      await _saveDrugToDictionary(name, company: companyCtrl.text.trim());
                      
                      // تسجيل النشاط
                      await DatabaseHelper.instance.logActivity(
                        assistantId: userProvider.currentAssistantId,
                        assistantName: userProvider.currentName,
                        action: 'إضافة ناقص',
                        details: 'تم إضافة الناقص: $name',
                        screen: 'shortages',
                      );
                      
                    } else {
                      await context.read<ShortagesProvider>().update(existing.id!, data);
                      // تسجيل النشاط
                      await DatabaseHelper.instance.logActivity(
                        assistantId: userProvider.currentAssistantId,
                        assistantName: userProvider.currentName,
                        action: 'تعديل ناقص',
                        details: 'تم تعديل الناقص: $name',
                        screen: 'shortages',
                      );
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadShortages();
                    if (mounted)
                      showSnack(context,
                          existing == null ? 'تم الإضافة ✅' : 'تم التعديل ✅',
                          durationMs: 800);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareShortages() async {
    final provider = context.read<ShortagesProvider>();
    final filtered = provider.filtered;
    if (filtered.isEmpty) {
      showSnack(context, 'لا توجد نواقص للمشاركة', isError: true);
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('📋 تقرير النواقص (${filtered.length} أصناف):');
    buffer.writeln('-------------------');
    for (var s in filtered) {
      buffer.writeln('📋 الدواء: ${s.name}');
      buffer.writeln('🏢 الشركة: ${s.company}');
      buffer.writeln('📦 الكمية: ${s.quantity}');
      if (s.isUrgent) buffer.writeln('🚨 حالة: عاجل جداً');
      buffer.writeln('-------------------');
    }
    await Share.share(buffer.toString());
  }

  Future<void> _importFromClipboard() async {
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canManageShortages) {
      showSnack(context, '⛔ ليس لديك صلاحية إدارة النواقص', isError: true);
      return;
    }
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null || data.text!.isEmpty) {
      showSnack(context, 'الحافظة فارغة! انسخ الرسالة من واتساب أولاً',
          isError: true);
      return;
    }

    final text = data.text!;
    final drugRegex = RegExp(r'[💊📋]?\s*الدواء:\s*(.*)');
    final companyRegex = RegExp(r'🏢 الشركة:\s*(.*)');
    final qtyRegex = RegExp(r'📦 الكمية:\s*(\d+)');
    final urgentRegex = RegExp(r'🚨 حالة:\s*عاجل');

    final blocks = text.split('-------------------');
    int count = 0;

    for (var block in blocks) {
      final nameMatch = drugRegex.firstMatch(block);
      if (nameMatch != null) {
        final name = nameMatch.group(1)?.trim() ?? '';
        if (name.isEmpty) continue;

        final companyMatch = companyRegex.firstMatch(block);
        final company = companyMatch?.group(1)?.trim() ?? 'غير محدد';

        final qtyMatch = qtyRegex.firstMatch(block);
        final qtyStr = qtyMatch?.group(1) ?? '1';
        final qty = int.tryParse(qtyStr) ?? 1;

        final isUrgent = urgentRegex.hasMatch(block);

        await context.read<ShortagesProvider>().add({
          'name': name,
          'company': company,
          'quantity': qty,
          'status': 'pending',
          'is_urgent': isUrgent ? 1 : 0,
        });
        count++;
      }
    }

    if (count > 0) {
      await _loadShortages();
      if (mounted) showSnack(context, 'تم استيراد $count أصناف بنجاح ✅');
    } else {
      if (mounted)
        showSnack(context, 'لم يتم العثور على أصناف متوافقة في النص المنسوخ',
            isError: true);
    }
  }

  /// ▌ حذف جماعي للأصناف المعروضة حالياً
  Future<void> _bulkDeleteFiltered() async {
    // فحص صلاحية الحذف
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canDelete) {
      showSnack(context, '⛔ ليس لديك صلاحية الحذف', isError: true);
      return;
    }
    final provider = context.read<ShortagesProvider>();
    final filtered = provider.filtered;
    if (filtered.isEmpty) {
      showSnack(context, 'لا توجد أصناف للحذف', isError: true);
      return;
    }

    final statusLabel = provider.filter == 'all' ? 'جميع الأصناف' : _filters.firstWhere((f) => f.$1 == provider.filter).$2;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚠️ حذف جماعي',
            style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
        content: Text(
          'هل تريد حذف ${filtered.length} صنف ($statusLabel)؟\n\n⚠️ لا يمكن التراجع عن هذا الإجراء.',
          style: const TextStyle(color: AppColors.textLight, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text('حذف ${filtered.length} صنف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (final item in filtered) {
        if (item.id != null) {
          await provider.delete(item.id!);
        }
      }
      // تسجيل النشاط
      await DatabaseHelper.instance.logActivity(
        assistantId: userProvider.currentAssistantId,
        assistantName: userProvider.currentName,
        action: 'حذف جماعي نواقص',
        details: 'تم حذف ${filtered.length} صنف',
        screen: 'shortages',
      );
      if (mounted) showSnack(context, 'تم حذف ${filtered.length} صنف ✅');
    }
  }

  Future<void> _addQuickShortage(String name) async {
    final provider = context.read<ShortagesProvider>();
    final alreadyExists = provider.shortages.any((s) => s.name.trim().toLowerCase() == name.trim().toLowerCase() && s.status != 'covered');
    if (alreadyExists) {
      showSnack(context, 'الدواء موجود بالفعل في النواقص ⚠️', isError: true);
      return;
    }
    final userProvider = context.read<CurrentUserProvider>();
    final data = {
      'name': name,
      'company': 'غير محدد',
      'quantity': 1,
      'is_urgent': 0,
      'notes': 'إضافة سريعة',
      'status': 'pending',
    };
    await provider.add(data);
    await _saveDrugToDictionary(name, company: 'غير محدد');
    await DatabaseHelper.instance.logActivity(
      assistantId: userProvider.currentAssistantId,
      assistantName: userProvider.currentName,
      action: 'إضافة ناقص',
      details: 'تم إضافة الناقص (سريع): $name',
      screen: 'shortages',
    );
    await _loadShortages();
    showSnack(context, 'تم إضافة $name بنجاح ✅', durationMs: 800);
  }

  Future<void> _submitWizardAdd() async {
    final name = _wizardNameCtrl.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'الرجاء إدخال اسم الدواء', isError: true);
      return;
    }
    final userProvider = context.read<CurrentUserProvider>();
    final data = {
      'name': name,
      'company': 'غير محدد',
      'quantity': _wizardQty,
      'is_urgent': _wizardIsUrgent ? 1 : 0,
      'notes': 'إضافة سريعة',
      'status': 'pending',
    };
    await context.read<ShortagesProvider>().add(data);
    await _saveDrugToDictionary(name, company: 'غير محدد');
    await DatabaseHelper.instance.logActivity(
      assistantId: userProvider.currentAssistantId,
      assistantName: userProvider.currentName,
      action: 'إضافة ناقص',
      details: 'تم إضافة الناقص (سريع): $name',
      screen: 'shortages',
    );
    setState(() {
      _wizardStep = 1;
      _wizardNameCtrl.clear();
      _wizardQty = 1;
      _wizardIsUrgent = false;
    });
    await _loadShortages();
    showSnack(context, 'تم إضافة $name بنجاح ✅', durationMs: 800);
  }

  Widget _buildStepDot(int step) {
    final isActive = _wizardStep == step;
    final isDone = _wizardStep > step;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary
            : isDone
                ? AppColors.accent
                : AppColors.dark,
        shape: BoxShape.circle,
        border: Border.all(color: isActive ? AppColors.primary : AppColors.darkBorder),
      ),
      child: Center(
        child: Text(
          '$step',
          style: TextStyle(
            color: isActive || isDone ? Colors.white : AppColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _openScanner() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (code != null && code.isNotEmpty) {
      final match = _suggestions.firstWhere(
        (s) => s['barcode']?.toString().trim() == code.trim(),
        orElse: () => <String, dynamic>{},
      );
      if (match.isNotEmpty) {
        debugPrint('🔍 [SHORTAGES_SCANNER] تم العثور على الدواء المطابق للرمز $code في القاموس: ${match['enName']}');
        _showAddSheet(
          initialName: match['enName']?.toString(),
          initialCompany: (match['company'] != null && match['company'].toString() != 'غير محدد')
              ? match['company'].toString()
              : null,
        );
      } else {
        debugPrint('🔍 [SHORTAGES_SCANNER] لم يتم العثور على الرمز $code في القاموس المحلي');
        _showAddSheet(initialName: code);
      }
    }
  }

  Future<void> _updateQuantity(Shortage item, int newQty) async {
    if (newQty < 1) return;
    final data = {
      'quantity': newQty,
    };
    await context.read<ShortagesProvider>().update(item.id!, data);
    await _loadShortages();
  }

  Future<void> _deleteShortage(Shortage item) async {
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canDelete) {
      showSnack(context, '⛔ ليس لديك صلاحية الحذف', isError: true);
      return;
    }
    final confirm = await showDeleteDialog(context, item.name);
    if (confirm == true && item.id != null) {
      await context.read<ShortagesProvider>().delete(item.id!);
      await DatabaseHelper.instance.logActivity(
        assistantId: userProvider.currentAssistantId,
        assistantName: userProvider.currentName,
        action: 'حذف ناقص',
        details: 'تم حذف الناقص: ${item.name}',
        screen: 'shortages',
      );
      await _loadShortages();
      if (mounted) showSnack(context, 'تم الحذف');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShortagesProvider>();
    final userProvider = context.watch<CurrentUserProvider>();
    final _shortages = provider.shortages;
    final _filtered = provider.filtered;
    final _loading = provider.loading;

    // حساب الإحصائيات
    final totalCount = _shortages.length;
    final pendingCount = _shortages.where((s) => s.status == 'pending').length;
    final sentCount = _shortages.where((s) => s.status == 'offered').length;

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Column(
        children: [
          // Custom Header
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
                            'نواقص اليوم',
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
                // 1. إجمالي النواقص
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            totalCount.toString(),
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800),
                          ),
                          const Text(
                            'النواقص',
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
                        child: const Icon(Icons.inventory_2_rounded, color: AppColors.accent, size: 14),
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

                // 2. بانتظار الرد
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            pendingCount.toString(),
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800),
                          ),
                          const Text(
                            'انتظار',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.hourglass_empty_rounded, color: Colors.amber, size: 14),
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

                // 3. تم الإرسال
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            sentCount.toString(),
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800),
                          ),
                          const Text(
                            'مرسل',
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
                        child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.primary, size: 14),
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

                // 4. أزرار البحث والمسح وخيارات الضبط
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showSearchField = !_showSearchField;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _showSearchField ? AppColors.primary.withOpacity(0.2) : AppColors.dark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _showSearchField ? AppColors.primary : AppColors.darkBorder),
                        ),
                        child: Icon(Icons.search, color: _showSearchField ? AppColors.primary : AppColors.textMuted, size: 15),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _openScanner,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.dark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: const Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 15),
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
                              value: 'send_rep',
                              child: Row(children: [
                                Icon(Icons.send_rounded, color: AppColors.primary, size: 16),
                                SizedBox(width: 8),
                                Text('إرسال لمندوب', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 13)),
                              ])),
                          const PopupMenuItem(
                              value: 'share_manager',
                              child: Row(children: [
                                Icon(Icons.share_rounded, color: AppColors.accent, size: 16),
                                SizedBox(width: 8),
                                Text('مشاركة للمدير', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 13)),
                              ])),
                          const PopupMenuItem(
                              value: 'parse_msg',
                              child: Row(children: [
                                Icon(Icons.swap_vert_rounded, color: AppColors.textLight, size: 16),
                                SizedBox(width: 8),
                                Text('ترتيب رسالة مندوب', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 13)),
                              ])),
                          if (userProvider.canManageShortages) ...[
                            const PopupMenuItem(
                                value: 'rapid_entry',
                                child: Row(children: [
                                  Icon(Icons.bolt_rounded, color: Color(0xFF00D4B4), size: 16),
                                  SizedBox(width: 8),
                                  Text('إدخال سريع بالكيبورد ⚡', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                                ])),
                            const PopupMenuItem(
                                value: 'import_excel',
                                child: Row(children: [
                                  Icon(Icons.upload_file, color: AppColors.primary, size: 16),
                                  SizedBox(width: 8),
                                  Text('استيراد Excel', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 13)),
                                ])),
                            const PopupMenuItem(
                                value: 'import_clipboard',
                                child: Row(children: [
                                  Icon(Icons.paste_rounded, color: AppColors.warning, size: 16),
                                  SizedBox(width: 8),
                                  Text('إضافة من الحافظة', style: TextStyle(color: AppColors.textColor, fontFamily: 'Cairo', fontSize: 13)),
                                ])),
                          ],
                        ],
                        onSelected: (v) {
                          if (v == 'rapid_entry') _openRapidEntry();
                          if (v == 'send_rep') _showSelectRepDialog();
                          if (v == 'share_manager') _shareShortages();
                          if (v == 'parse_msg') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RepMessageParserScreen()),
                            );
                          }
                          if (v == 'import_excel') _importExcel();
                          if (v == 'import_clipboard') _importFromClipboard();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search Field if expanded
          if (_showSearchField)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                onChanged: (v) => provider.setSearch(v),
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textColor),
                decoration: InputDecoration(
                  hintText: 'ابحث عن دواء...',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (provider.search.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            provider.setSearch('');
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.danger, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          provider.setSearch('');
                          setState(() => _showSearchField = false);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // "نواقص سريعة" (Quick Shortages) Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'نواقص سريعة ⚡',
                  style: TextStyle(color: AppColors.textLight, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true, // For RTL flow layout
                  child: Row(
                    children: [
                      // إدخال سريع بالكيبورد pill
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.bolt_rounded, size: 16, color: Colors.black),
                          label: const Text('إدخال سريع ⚡',
                              style: TextStyle(color: Colors.black, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.w900)),
                          backgroundColor: const Color(0xFF00D4B4),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onPressed: _openRapidEntry,
                        ),
                      ),
                      // + إضافة pill (النموذج الكامل)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.add, size: 14, color: Colors.white),
                          label: const Text('إضافة صنف',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          backgroundColor: AppColors.primary,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onPressed: () => _showAddSheet(),
                        ),
                      ),
                      // Common items
                      ...['بنادول', 'فلاجيل 500', 'أوجمنتين', 'كونجستال', 'كولونا', 'سولبادين', 'بروفين 400'].map((name) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ActionChip(
                            label: Text(name,
                                style: const TextStyle(color: AppColors.textColor, fontSize: 11, fontFamily: 'Cairo')),
                            backgroundColor: AppColors.darkCard,
                            side: const BorderSide(color: AppColors.darkBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onPressed: () => _addQuickShortage(name),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // "إضافة سريعة" Wizard Box
          if (userProvider.canManageShortages)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Title + Steps indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _buildStepDot(1),
                          const SizedBox(width: 4),
                          _buildStepDot(2),
                          const SizedBox(width: 4),
                          _buildStepDot(3),
                        ],
                      ),
                      const Text(
                        'إضافة سريعة ⚡',
                        style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Step content
                  if (_wizardStep == 1) ...[
                    // Step 1: Drug Name with Autocomplete
                    Row(
                      children: [
                        Expanded(
                          child: Autocomplete<Map<String, dynamic>>(
                            optionsBuilder: (TextEditingValue v) {
                              if (v.text.isEmpty) {
                                return const Iterable<Map<String, dynamic>>.empty();
                              }
                              return _suggestions.where((s) {
                                final en = s['enName']?.toString().toLowerCase() ?? '';
                                final ar = s['arName']?.toString().toLowerCase() ?? '';
                                final q = v.text.toLowerCase();
                                return en.contains(q) || ar.contains(q);
                              }).take(8);
                            },
                            displayStringForOption: (option) => option['enName']?.toString() ?? '',
                            onSelected: (option) {
                              _wizardNameCtrl.text = option['enName']?.toString() ?? '';
                            },
                            fieldViewBuilder: (ctx, ctrl, fn, onSubmit) {
                              // Sync controller
                              ctrl.text = _wizardNameCtrl.text;
                              ctrl.addListener(() {
                                _wizardNameCtrl.text = ctrl.text;
                              });
                              return TextField(
                                controller: ctrl,
                                focusNode: fn,
                                style: const TextStyle(color: AppColors.textColor, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'اسم الدواء أو الباركود...',
                                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Cairo'),
                                  filled: true,
                                  fillColor: AppColors.dark,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                ),
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topRight,
                                child: Material(
                                  color: AppColors.darkCard,
                                  elevation: 4.0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: AppColors.darkBorder),
                                  ),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 180, maxWidth: 280),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (BuildContext context, int index) {
                                        final option = options.elementAt(index);
                                        final en = option['enName']?.toString() ?? '';
                                        return InkWell(
                                          onTap: () => onSelected(option),
                                          child: Padding(
                                            padding: const EdgeInsets.all(10.0),
                                            child: Text(en, style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (_wizardNameCtrl.text.trim().isEmpty) {
                              showSnack(context, 'الرجاء إدخال اسم الدواء', isError: true);
                              return;
                            }
                            setState(() => _wizardStep = 2);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('التالي', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ] else if (_wizardStep == 2) ...[
                    // Step 2: Quantity counter
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _wizardStep = 1),
                              child: const Text('السابق', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo', fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => setState(() => _wizardStep = 3),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('التالي', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text('الكمية المطلوبة:', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Cairo')),
                            const SizedBox(width: 12),
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.dark,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.darkBorder),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, color: AppColors.primary, size: 16),
                                    onPressed: () {
                                      if (_wizardQty > 1) {
                                        setState(() => _wizardQty--);
                                      }
                                    },
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                  ),
                                  Text(
                                    '$_wizardQty',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, color: AppColors.primary, size: 16),
                                    onPressed: () => setState(() => _wizardQty++),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else if (_wizardStep == 3) ...[
                    // Step 3: Urgency and add
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _wizardStep = 2),
                              child: const Text('السابق', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo', fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _submitWizardAdd,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('إضافة للجدول ✅', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text('صنف عاجل جداً؟', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Cairo')),
                            const SizedBox(width: 8),
                            Switch(
                              value: _wizardIsUrgent,
                              onChanged: (v) => setState(() => _wizardIsUrgent = v),
                              activeThumbColor: AppColors.danger,
                              activeTrackColor: AppColors.danger.withOpacity(0.3),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // Filter Tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Bulk Delete - only show when a specific filter is active
                  if (provider.filter != 'all' && _filtered.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.delete_sweep,
                            size: 16, color: Colors.white),
                        label: Text('حذف ${_filtered.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        backgroundColor: AppColors.danger,
                        onPressed: _bulkDeleteFiltered,
                      ),
                    ),
                  ..._filters.map((f) {
                    final isActive = provider.filter == f.$1;
                    final count = f.$1 == 'all'
                        ? _shortages.length
                        : _shortages.where((s) => s.status == f.$1).length;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text('${f.$2} ($count)'),
                        selected: isActive,
                        onSelected: (_) => provider.setFilter(f.$1),
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.darkCard,
                        side: BorderSide(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.darkBorder),
                        labelStyle: TextStyle(
                            color: isActive
                                ? Colors.white
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),

          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.darkCard,
                        onRefresh: _loadShortages,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) => _buildCard(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: userProvider.canManageShortages
          ? Container(
              color: AppColors.dark,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: PrimaryButton(
                text: '+ إضافة صنف جديد',
                onTap: () => _showAddSheet(),
              ),
            )
          : null,
    );
  }



  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.08),
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.15), width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // نجوم صغيرة
                Positioned(
                    top: 20,
                    left: 25,
                    child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle))),
                Positioned(
                    top: 35,
                    right: 20,
                    child: Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle))),
                Positioned(
                    bottom: 25,
                    left: 20,
                    child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle))),
                // أيقونة الصندوق
                Icon(Icons.inventory_2_rounded,
                    color: AppColors.primary, size: 60),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('لا توجد نواقص',
              style: TextStyle(
                  color: AppColors.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('جميع الأصناف متوفرة حالياً',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('عند وجود نقص ستظهر هنا',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          // ميزات
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _featureChip(Icons.shield_rounded, 'مخزون منظم'),
              const SizedBox(width: 12),
              _featureChip(Icons.timer_rounded, 'تحديث لحظي'),
              const SizedBox(width: 12),
              _featureChip(Icons.check_rounded, 'بيانات دقيقة'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primary, size: 14),
        const SizedBox(width: 4),
        Text(label,
            style:
                const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }

  Widget _buildCard(Shortage item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            right: BorderSide(
                color: item.isUrgent ? AppColors.danger : AppColors.darkBorder,
                width: 4),
            top: BorderSide(
                color: item.isUrgent
                    ? AppColors.danger.withOpacity(0.2)
                    : AppColors.darkBorder),
            bottom: BorderSide(
                color: item.isUrgent
                    ? AppColors.danger.withOpacity(0.2)
                    : AppColors.darkBorder),
            left: BorderSide(
                color: item.isUrgent
                    ? AppColors.danger.withOpacity(0.2)
                    : AppColors.darkBorder),
          ),
          boxShadow: item.isUrgent ? [
            BoxShadow(
              color: AppColors.danger.withOpacity(0.08),
              blurRadius: 8,
              spreadRadius: 1,
            )
          ] : null,
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Drag handle (Far Left)
                const Icon(Icons.drag_handle_rounded, color: AppColors.textMuted, size: 20),
                const SizedBox(width: 8),

                // Urgency Badge (Middle-left)
                if (item.isUrgent) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D0A0A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_rounded, color: AppColors.danger, size: 10),
                        SizedBox(width: 2),
                        Text(
                          'عاجل',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Quantity Counter (Middle)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.dark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, color: AppColors.primary, size: 14),
                        onPressed: () {
                          if (item.quantity > 1) {
                            _updateQuantity(item, item.quantity - 1);
                          }
                        },
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                      Text(
                        '${item.quantity}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: AppColors.primary, size: 14),
                        onPressed: () {
                          _updateQuantity(item, item.quantity + 1);
                        },
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Medication Details (Middle-right)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showAddSheet(existing: item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 16),
                              onPressed: () => _searchGoogleImages(item.name),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              constraints: const BoxConstraints(),
                              tooltip: 'بحث في جوجل (صور)',
                            ),
                            Flexible(
                              child: Text(
                                item.name,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: AppColors.textColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.company} · ${item.timeAgo}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'Cairo'),
                        ),
                        if (item.createdBy != null && item.createdBy!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'أضافه: ${item.createdBy}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Delete Button (Far Right)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                  onPressed: () => _deleteShortage(item),
                ),
              ],
            ),
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  item.notes!,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'Cairo'),
                ),
              ),
            ],
            FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.getAlternativesFor(item.name),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                final alts = snapshot.data!.map((row) {
                  final med = row['medication_name']?.toString() ?? '';
                  final alt = row['alternative_name']?.toString() ?? '';
                  if (med.toLowerCase() == item.name.toLowerCase()) {
                    return alt;
                  }
                  return med;
                }).where((name) => name.isNotEmpty).toSet().toList();

                if (alts.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '💡 بدائل محلية مقترحة: ${alts.join(" ، ")}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatusBadge(status: item.status),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AlternativesScreen(initialSearch: item.name),
                      ),
                    );
                  },
                  icon: const Icon(Icons.swap_horiz_rounded, size: 14, color: AppColors.accent),
                  label: const Text(
                    'البحث عن بديل 🔄',
                    style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
