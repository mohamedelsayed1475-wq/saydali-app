import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'send_to_rep_screen.dart';

class ShortagesScreen extends StatefulWidget {
  const ShortagesScreen({super.key});

  @override
  State<ShortagesScreen> createState() => _ShortagesScreenState();
}

class _ShortagesScreenState extends State<ShortagesScreen> {
  List<Shortage> _shortages = [];
  String _filter = 'all';
  String _search = '';
  bool _loading = true;
  List<String> _suggestions = [];

  final _filters = [
    ('all', 'الكل'),
    ('pending', 'انتظار'),
    ('offered', 'عروض'),
    ('covered', 'مغطى'),
    ('stubborn', 'مستعصي'),
  ];

  @override
  void initState() {
    super.initState();
    _loadShortages();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary');
    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        if (mounted) setState(() => _suggestions = decoded.cast<String>());
      } catch (e) {}
    }
  }

  Future<void> _loadShortages() async {
    final data = await DatabaseHelper.instance.getShortages();
    if (mounted) {
      setState(() {
        _shortages = data.map(Shortage.fromMap).toList();
        _loading = false;
      });
    }
  }

  List<Shortage> get _filtered => _shortages.where((s) {
        final matchFilter = _filter == 'all' || s.status == _filter;
        final matchSearch = _search.isEmpty || s.name.contains(_search) || s.company.contains(_search);
        return matchFilter && matchSearch;
      }).toList();

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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختر المندوب لإرسال النواقص', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: reps.length,
                itemBuilder: (ctx, i) {
                  final rep = Representative.fromMap(reps[i]);
                  return ListTile(
                    leading: const Icon(Icons.person, color: AppColors.primary),
                    title: Text(rep.name, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(rep.company ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => SendToRepScreen(rep: rep)));
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

          final company = row.length > 1 ? (row[1]?.value?.toString() ?? 'غير محدد') : 'غير محدد';
          final qty = row.length > 2 ? (int.tryParse(row[2]?.value?.toString() ?? '') ?? 1) : 1;

          await DatabaseHelper.instance.insertShortage({
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

  Future<void> _showAddSheet({Shortage? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final companyCtrl = TextEditingController(text: existing?.company);
    final qtyCtrl = TextEditingController(text: existing?.quantity.toString() ?? '1');
    final notesCtrl = TextEditingController(text: existing?.notes);
    bool isUrgent = existing?.isUrgent ?? false;
    String status = existing?.status ?? 'pending';

    final suggestions = ['أوجمنتين', 'برونكوسول', 'فلاجيل', 'فنتولين', 'كونكور', 'زيثروماكس', 'بنادول', 'فولتارين', 'ريزولين', 'بريدنيزون'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.darkBorder, borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                Text(existing == null ? '➕ إضافة ناقص جديد' : '✏️ تعديل الناقص',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 16),

                Autocomplete<String>(
                  optionsBuilder: (v) {
                    if (v.text.isEmpty) return const Iterable<String>.empty();
                    return _suggestions.where((s) => s.toLowerCase().contains(v.text.toLowerCase()));
                  },
                  onSelected: (s) => nameCtrl.text = s,
                  fieldViewBuilder: (ctx, ctrl, fn, onSubmit) {
                    if (existing != null && ctrl.text.isEmpty && existing.name.isNotEmpty) ctrl.text = existing.name;
                    return AppTextField(
                      hint: 'اسم الدواء *',
                      controller: ctrl,
                      onChanged: (val) => nameCtrl.text = val,
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
                          side: const BorderSide(color: AppColors.darkBorder),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final option = options.elementAt(index);
                              return InkWell(
                                onTap: () {
                                  onSelected(option);
                                  nameCtrl.text = option; // Ensure it syncs when selected
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Text(option, style: const TextStyle(color: Colors.white)),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                AppTextField(hint: 'الشركة المصنعة', controller: companyCtrl),
                const SizedBox(height: 10),
                AppTextField(hint: 'الكمية', controller: qtyCtrl, keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                AppTextField(hint: 'ملاحظات (اختياري)', controller: notesCtrl, maxLines: 2),
                const SizedBox(height: 10),

                // الحالة
                if (existing != null) ...[
                  const Text('الحالة', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in ['pending', 'offered', 'covered', 'stubborn'])
                        ChoiceChip(
                          label: Text(Shortage(name: '', status: s, createdAt: DateTime.now(), updatedAt: DateTime.now()).statusLabel),
                          selected: status == s,
                          onSelected: (_) => setBS(() => status = s),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.dark,
                          labelStyle: TextStyle(color: status == s ? Colors.white : AppColors.textMuted, fontSize: 12),
                          side: BorderSide(color: status == s ? AppColors.primary : AppColors.darkBorder),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // عاجل
                Row(
                  children: [
                    Switch(value: isUrgent, onChanged: (v) => setBS(() => isUrgent = v), activeColor: AppColors.danger),
                    const Text('عاجل 🚨', style: TextStyle(color: AppColors.textLight)),
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
                      'company': companyCtrl.text.trim().isEmpty ? 'غير محدد' : companyCtrl.text.trim(),
                      'quantity': int.tryParse(qtyCtrl.text) ?? 1,
                      'is_urgent': isUrgent ? 1 : 0,
                      'notes': notesCtrl.text.trim(),
                      if (existing != null) 'status': status,
                    };

                    if (existing == null) {
                      await DatabaseHelper.instance.insertShortage(data);
                    } else {
                      await DatabaseHelper.instance.updateShortage(existing.id!, data);
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadShortages();
                    if (mounted) showSnack(context, existing == null ? 'تم الإضافة ✅' : 'تم التعديل ✅');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                // Search
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(color: AppColors.textColor),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن دواء...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.upload_file, color: AppColors.primary),
                      tooltip: 'استيراد Excel',
                      onPressed: _importExcel,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Filter Tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.send, size: 16, color: Colors.white),
                          label: const Text('إرسال لمندوب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          backgroundColor: AppColors.primary,
                          onPressed: _showSelectRepDialog,
                        ),
                      ),
                      ..._filters.map((f) {
                        final isActive = _filter == f.$1;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: FilterChip(
                          label: Text(f.$2),
                          selected: isActive,
                          onSelected: (_) => setState(() => _filter = f.$1),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.darkCard,
                          side: BorderSide(color: isActive ? AppColors.primary : AppColors.darkBorder),
                          labelStyle: TextStyle(color: isActive ? Colors.white : AppColors.textMuted, fontWeight: FontWeight.w600),
                        ),
                      );
                      }).toList(),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _filtered.isEmpty
                    ? EmptyState(
                        emoji: '🎉',
                        title: 'لا توجد نواقص',
                        subtitle: 'اضغط + لإضافة ناقص جديد\nأو استورد من Excel',
                        buttonText: 'إضافة ناقص',
                        onButton: () => _showAddSheet(),
                      )
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('ناقص جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildCard(Shortage item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _showAddSheet(existing: item),
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              icon: Icons.edit_rounded,
              label: 'تعديل',
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
            ),
            SlidableAction(
              onPressed: (_) async {
                final confirm = await showDeleteDialog(context, item.name);
                if (confirm == true) {
                  await DatabaseHelper.instance.deleteShortage(item.id!);
                  await _loadShortages();
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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border(
              right: BorderSide(color: item.isUrgent ? AppColors.danger : AppColors.darkBorder, width: 4),
              top: BorderSide(color: item.isUrgent ? AppColors.danger.withValues(alpha: 0.3) : AppColors.darkBorder),
              bottom: BorderSide(color: item.isUrgent ? AppColors.danger.withValues(alpha: 0.3) : AppColors.darkBorder),
              left: BorderSide(color: item.isUrgent ? AppColors.danger.withValues(alpha: 0.3) : AppColors.darkBorder),
            ),
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
                        Text(item.name, style: const TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 3),
                        Text('${item.company} · ${item.quantity} علبة · ${item.timeAgo}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  StatusBadge(status: item.status),
                ],
              ),
              if (item.isUrgent) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFF2D0A0A), borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_rounded, color: AppColors.danger, size: 14),
                      SizedBox(width: 4),
                      Text('عاجل', style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
              if (item.notes != null && item.notes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(item.notes!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
