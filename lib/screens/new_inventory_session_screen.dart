import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:provider/provider.dart';
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../providers/current_user_provider.dart';
import 'fast_count_screen.dart';

class NewInventorySessionScreen extends StatefulWidget {
  const NewInventorySessionScreen({super.key});

  @override
  State<NewInventorySessionScreen> createState() => _NewInventorySessionScreenState();
}

class _NewInventorySessionScreenState extends State<NewInventorySessionScreen> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _customItemNameController = TextEditingController();
  final _customItemQtyController = TextEditingController();

  List<Map<String, dynamic>> _previewItems = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final monthName = _arabicMonth(now.month);
    _titleController.text = 'جرد مخزن $monthName ${now.year}';
  }

  String _arabicMonth(int m) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    if (m >= 1 && m <= 12) return months[m - 1];
    return '$m';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _customItemNameController.dispose();
    _customItemQtyController.dispose();
    super.dispose();
  }

  Future<void> _importFromDrugDictionary() async {
    setState(() => _isLoading = true);
    final items = await DatabaseHelper.instance.getDrugDictionaryItemsForInventory();
    if (!mounted) return;

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('قاموس الأدوية فارغ! يمكنك الاستيراد من Excel أو إضافة أصناف يدوياً.')),
      );
    } else {
      setState(() {
        _previewItems = items;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم استيراد ${items.length} صنف من قاموس الأدوية بنجاح!'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _importFromShortages() async {
    setState(() => _isLoading = true);
    final shortages = await DatabaseHelper.instance.getShortages();
    if (!mounted) return;

    if (shortages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد نواقص حالية لاستيرادها!')),
      );
    } else {
      final list = shortages.map((s) {
        return {
          'name': s['name']?.toString() ?? '',
          'barcode': null,
          'system_quantity': (s['quantity'] as num?)?.toDouble() ?? 1.0,
        };
      }).where((it) => it['name'].toString().isNotEmpty).toList();

      setState(() {
        _previewItems = list;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم استيراد ${list.length} صنف من قائمة النواقص!'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _importFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() => _isLoading = true);

    try {
      final bytes = File(result.files.single.path!).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      final list = <Map<String, dynamic>>[];

      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table]!;
        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.row(i);
          if (row.isEmpty || row[0]?.value == null) continue;

          final name = row[0]?.value?.toString().trim() ?? '';
          if (name.isEmpty) continue;

          final barcode = row.length > 1 ? row[1]?.value?.toString() : null;
          final qty = row.length > 2
              ? (double.tryParse(row[2]?.value?.toString() ?? '') ?? 0.0)
              : 0.0;

          list.add({
            'name': name,
            'barcode': barcode,
            'system_quantity': qty,
          });
        }
      }

      if (mounted) {
        setState(() {
          _previewItems = list;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم استيراد ${list.length} صنف من ملف Excel بنجاح!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في قراءة ملف Excel: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addManualItem() {
    final name = _customItemNameController.text.trim();
    if (name.isEmpty) return;

    final qty = double.tryParse(_customItemQtyController.text.trim()) ?? 0.0;
    setState(() {
      _previewItems.add({
        'name': name,
        'barcode': null,
        'system_quantity': qty,
      });
      _customItemNameController.clear();
      _customItemQtyController.clear();
    });
  }

  Future<void> _startSession() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة عنوان لجلسة الجرد')),
      );
      return;
    }

    if (_previewItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة أو استيراد صنف واحد على الأقل للجرد')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<CurrentUserProvider>();
      final notes = _notesController.text.trim();

      // 1. إنشاء الجلسة
      final sessionId = await DatabaseHelper.instance.insertInventorySession({
        'title': title,
        'notes': notes.isNotEmpty ? notes : null,
        'total_items': _previewItems.length,
        'created_by': userProvider.currentName,
      });

      // 2. إدراج الأصناف
      await DatabaseHelper.instance.insertInventoryItemsBatch(sessionId, _previewItems);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚀 تم إنشاء جلسة الجرد بنجاح! جاري الانتقال للعد السريع...'),
          backgroundColor: AppColors.primary,
        ),
      );

      // 3. التوجيه المباشر لشاشة العد السريع
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FastCountScreen(
            sessionId: sessionId,
            sessionTitle: title,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء بدء الجلسة: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('بدء جلسة جرد جديدة'),
        backgroundColor: AppColors.darkCard,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // بطاقة بيانات الجلسة
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
                  const Text(
                    'عنوان جلسة الجرد',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'مثال: جرد شامل للصيدلية...',
                      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      fillColor: AppColors.dark,
                      filled: true,
                      prefixIcon: const Icon(Icons.inventory_rounded, color: AppColors.primary, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ملاحظات اختيارية',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notesController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'مثال: يشمل قسم الأقراص والأشربة فقط...',
                      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      fillColor: AppColors.dark,
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // خيارات استيراد الأصناف
            const Text(
              'استيراد أصناف الجرد',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _importOptionCard(
                    icon: Icons.menu_book_rounded,
                    title: 'قاموس الأدوية',
                    color: const Color(0xFF6366F1),
                    onTap: _isLoading ? null : _importFromDrugDictionary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _importOptionCard(
                    icon: Icons.table_chart_rounded,
                    title: 'ملف Excel',
                    color: const Color(0xFF10B981),
                    onTap: _isLoading ? null : _importFromExcel,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _importOptionCard(
                    icon: Icons.medical_services_outlined,
                    title: 'النواقص الحالية',
                    color: const Color(0xFFF59E0B),
                    onTap: _isLoading ? null : _importFromShortages,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // إضافة صنف يدوي
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _customItemNameController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'اسم الصنف يدوياً...',
                        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _customItemQtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'الكمية',
                        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addManualItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: const Text('+ إضافة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // معاينة الأصناف
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الأصناف المجهزة للجرد (${_previewItems.length})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (_previewItems.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _previewItems.clear()),
                    icon: const Icon(Icons.delete_outline, size: 14, color: AppColors.danger),
                    label: const Text('مسح الكل', style: TextStyle(color: AppColors.danger, fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (_previewItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: const Center(
                  child: Text(
                    'لم يتم إضافة أو استيراد أي أصناف بعد.\nاختر أحد خيارات الاستيراد بالأعلى.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _previewItems.length,
                  separatorBuilder: (_, __) => const Divider(color: AppColors.darkBorder, height: 1),
                  itemBuilder: (context, i) {
                    final it = _previewItems[i];
                    return ListTile(
                      dense: true,
                      title: Text(it['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text('الكمية المسجلة: ${it['system_quantity'] ?? 0}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 14, color: AppColors.danger),
                        onPressed: () => setState(() => _previewItems.removeAt(i)),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 24),

            // زر البدء
            ElevatedButton(
              onPressed: _isLoading ? null : _startSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                    )
                  : const Text(
                      'بدء الجلسة والانتقال للعد السريع 🚀',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _importOptionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
