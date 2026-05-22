import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/open_fda_service.dart';

class AlternativesScreen extends StatefulWidget {
  final String? initialSearch;
  const AlternativesScreen({super.key, this.initialSearch});

  @override
  State<AlternativesScreen> createState() => _AlternativesScreenState();
}

class _AlternativesScreenState extends State<AlternativesScreen> {
  final _searchCtrl = TextEditingController();
  List<Alternative> _alternatives = [];
  List<FdaDrugModel> _fdaResults = [];
  bool _loading = false;
  bool _searchByIngredient = false;
  bool _isFdaMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSearch != null) {
      _searchCtrl.text = widget.initialSearch!;
    }
    _search();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final query = _searchCtrl.text.trim();
      
      if (_isFdaMode) {
        if (query.isEmpty) {
          setState(() {
            _fdaResults = [];
            _loading = false;
          });
          return;
        }
        final results = await OpenFdaService.instance.searchDrug(query);
        setState(() {
          _fdaResults = results;
          _loading = false;
        });
      } else {
        List<Map<String, dynamic>> data;
        if (query.isEmpty) {
          final db = await DatabaseHelper.instance.database;
          data = await db.query('alternatives', limit: 50, orderBy: 'id DESC');
        } else {
          if (_searchByIngredient) {
            data = await DatabaseHelper.instance.getAlternativesByIngredient(query);
          } else {
            data = await DatabaseHelper.instance.getAlternativesFor(query);
          }
        }

        // After local search, if nothing found, fall back to FDA search automatically
        if (data.isEmpty && query.isNotEmpty) {
          // Switch to FDA mode and perform remote search
          setState(() {
            _isFdaMode = true;
          });
          final results = await OpenFdaService.instance.searchDrug(query);
          setState(() {
            _fdaResults = results;
            _loading = false;
          });
          return; // skip setting local alternatives
        }

        setState(() {
          _alternatives = data.map((e) => Alternative.fromMap(e)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        showSnack(context, '⚠️ فشل تحميل البدائل: $e', isError: true);
      }
    }
  }

  Future<void> _showAddModal() async {
    final medCtrl = TextEditingController(text: widget.initialSearch ?? '');
    final altCtrl = TextEditingController();
    final ingCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ربط دواء ببديل جديد 🔗',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: medCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اسم الدواء الأصلي *',
                  prefixIcon: Icon(Icons.medication_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: altCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اسم الدواء البديل *',
                  prefixIcon: Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ingCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'المادة الفعالة المشتركة (اختياري)',
                  prefixIcon: Icon(Icons.biotech_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final med = medCtrl.text.trim();
                  final alt = altCtrl.text.trim();
                  final ing = ingCtrl.text.trim();

                  if (med.isEmpty || alt.isEmpty) {
                    showSnack(ctx, 'يرجى إدخال اسم الدواء الأصلي والبديل', isError: true);
                    return;
                  }

                  try {
                    await DatabaseHelper.instance.insertAlternative({
                      'medication_name': med,
                      'alternative_name': alt,
                      'active_ingredient': ing.isEmpty ? null : ing,
                    });
                    Navigator.pop(ctx);
                    _search();
                    if (mounted) {
                      showSnack(context, 'تم ربط الدواء البديل بنجاح 🎉');
                    }
                  } catch (e) {
                    showSnack(ctx, '⚠️ فشل الربط: $e', isError: true);
                  }
                },
                child: const Text('حفظ الرابط'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAsLocal(FdaDrugModel item) async {
    final medCtrl = TextEditingController(text: _searchCtrl.text.trim());
    final altCtrl = TextEditingController(text: item.brandName);
    final ingCtrl = TextEditingController(text: item.genericName);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ربط البديل المكتشف محلياً 🔗',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: medCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اسم الدواء الأصلي المطلوب *',
                  prefixIcon: Icon(Icons.medication_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: altCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اسم الدواء البديل المختار *',
                  prefixIcon: Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ingCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'المادة الفعالة المصاحبة',
                  prefixIcon: Icon(Icons.biotech_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final med = medCtrl.text.trim();
                  final alt = altCtrl.text.trim();
                  final ing = ingCtrl.text.trim();

                  if (med.isEmpty || alt.isEmpty) {
                    showSnack(ctx, 'يرجى إدخال اسم الدواء الأصلي والبديل', isError: true);
                    return;
                  }

                  try {
                    await DatabaseHelper.instance.insertAlternative({
                      'medication_name': med,
                      'alternative_name': alt,
                      'active_ingredient': ing.isEmpty ? null : ing,
                    });
                    Navigator.pop(ctx);
                    if (mounted) {
                      showSnack(context, 'تم حفظ البديل بنجاح في القاموس المحلي! 🎉');
                    }
                  } catch (e) {
                    showSnack(ctx, '⚠️ فشل الحفظ: $e', isError: true);
                  }
                },
                child: const Text('حفظ في القاموس المحلي'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteLink(int id, String med, String alt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('حذف رابط البديل', style: TextStyle(color: Colors.white)),
        content: Text(
          'هل تريد إلغاء رابط البديل بين "$med" و "$alt"؟',
          style: const TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('حذف الرابط'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await DatabaseHelper.instance.deleteAlternativeLink(id);
        _search();
        if (mounted) {
          showSnack(context, 'تم حذف رابط البديل بنجاح 🗑️');
        }
      } catch (e) {
        if (mounted) {
          showSnack(context, '⚠️ فشل الحذف: $e', isError: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text(
          'دليل بدائل الأدوية 🔄',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link_rounded, color: AppColors.primary, size: 28),
            onPressed: _showAddModal,
            tooltip: 'إضافة رابط بديل',
          ),
        ],
      ),
      body: Column(
        children: [
          // لوحة التبديل بين البحث المحلي والعالمي
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isFdaMode = false;
                        _alternatives = [];
                      });
                      _search();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_isFdaMode ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.home_filled, size: 18, color: !_isFdaMode ? AppColors.primary : Colors.white60),
                            const SizedBox(width: 6),
                            Text(
                              'البحث المحلي 🏠',
                              style: TextStyle(
                                color: !_isFdaMode ? AppColors.primary : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isFdaMode = true;
                        _fdaResults = [];
                      });
                      _search();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _isFdaMode ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.language_rounded, size: 18, color: _isFdaMode ? AppColors.primary : Colors.white60),
                            const SizedBox(width: 6),
                            Text(
                              'البحث العالمي FDA 🌐',
                              style: TextStyle(
                                color: _isFdaMode ? AppColors.primary : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // لوحة البحث الذكي
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Card(
              color: AppColors.darkCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.darkBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: _isFdaMode 
                            ? 'ابحث باسم الدواء بالإنجليزية (مثل Tylenol)...'
                            : (_searchByIngredient ? 'ابحث باسم المادة الفعالة...' : 'ابحث باسم الدواء الأصلي أو البديل...'),
                        prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _search();
                                },
                              )
                            : null,
                      ),
                    ),
                    if (!_isFdaMode) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'طريقة البحث:',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontFamily: 'Cairo'),
                          ),
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('اسم الدواء'),
                                selected: !_searchByIngredient,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _searchByIngredient = false);
                                    _search();
                                  }
                                },
                                selectedColor: AppColors.primary.withValues(alpha: 0.25),
                                disabledColor: AppColors.dark,
                                labelStyle: TextStyle(
                                  color: !_searchByIngredient ? AppColors.primary : Colors.white70,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('المادة الفعالة'),
                                selected: _searchByIngredient,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _searchByIngredient = true);
                                    _search();
                                  }
                                },
                                selectedColor: AppColors.primary.withValues(alpha: 0.25),
                                disabledColor: AppColors.dark,
                                labelStyle: TextStyle(
                                  color: _searchByIngredient ? AppColors.primary : Colors.white70,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // قائمة نتائج البدائل (محلية / عالمية)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _isFdaMode 
                    ? _buildFdaResultsView() 
                    : _buildLocalResultsView(),
          ),
        ],
      ),
    );
  }

  // نتائج البحث المحلي
  Widget _buildLocalResultsView() {
    if (_alternatives.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isEmpty
                  ? 'دليل البدائل فارغ، ابدأ بربط أول بديل!'
                  : 'لا توجد بدائل مطابقة للبحث',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14, fontFamily: 'Cairo'),
            ),
            if (_searchCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _showAddModal,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة هذا البديل الآن'),
              ),
            ]
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _alternatives.length,
      itemBuilder: (ctx, idx) {
        final item = _alternatives[idx];
        return Card(
          color: AppColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.darkBorder),
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.medication_rounded, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.medicationName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                      onPressed: () => _deleteLink(item.id!, item.medicationName, item.alternativeName),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(color: AppColors.darkBorder, thickness: 1),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(Icons.swap_vertical_circle_rounded, color: AppColors.accent, size: 20),
                      ),
                      Expanded(
                        child: Divider(color: AppColors.darkBorder, thickness: 1),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.swap_horiz_rounded, color: AppColors.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.alternativeName,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.activeIngredient != null && item.activeIngredient!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.biotech_rounded, color: Colors.blue, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'المادة الفعالة: ${item.activeIngredient}',
                          style: const TextStyle(color: AppColors.textLight, fontSize: 12, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // نتائج البحث العالمي (FDA)
  Widget _buildFdaResultsView() {
    if (_fdaResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.travel_explore_rounded, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              _searchCtrl.text.isEmpty
                  ? 'اكتب اسم دواء بالإنجليزية للبحث في FDA...'
                  : 'لم يتم العثور على أدوية مطابقة في FDA',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14, fontFamily: 'Cairo'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _fdaResults.length,
      itemBuilder: (ctx, idx) {
        final item = _fdaResults[idx];
        return Card(
          color: AppColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.darkBorder),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.brandName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.biotech_rounded, color: Colors.blue, size: 14),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.genericName,
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _saveAsLocal(item),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                        foregroundColor: AppColors.primary,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('حفظ محلي', style: TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // قائمة البراندات البديلة المشتركة في المادة الفعالة
                if (item.allBrands.length > 1) ...[
                  const Text(
                    'البراندات البديلة المطابقة (FDA):',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: item.allBrands.skip(1).map((b) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.dark,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Text(
                        b,
                        style: const TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 6),
                ],

                // الأكورديونات الطبية
                FdaAccordion(
                  title: '📖 دواعي الاستعمال (Indications)',
                  content: item.indications,
                  icon: Icons.assignment_rounded,
                ),
                FdaAccordion(
                  title: '🧪 الجرعات وطريقة الاستعمال (Dosage)',
                  content: item.dosage,
                  icon: Icons.science_rounded,
                ),
                FdaAccordion(
                  title: '⚠️ الأعراض الجانبية وموانع الاستعمال',
                  content: '${item.adverseReactions}\n\n${item.contraindications}',
                  icon: Icons.warning_amber_rounded,
                  iconColor: Colors.amber,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// عنصر الأكورديون القابل للتوسيع للـ FDA
class FdaAccordion extends StatefulWidget {
  final String title;
  final String content;
  final IconData icon;
  final Color iconColor;

  const FdaAccordion({
    super.key,
    required this.title,
    required this.content,
    required this.icon,
    this.iconColor = AppColors.primary,
  });

  @override
  State<FdaAccordion> createState() => _FdaAccordionState();
}

class _FdaAccordionState extends State<FdaAccordion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.content.trim().isEmpty || widget.content == 'Not available') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            onTap: () => setState(() => _expanded = !_expanded),
            leading: Icon(widget.icon, color: widget.iconColor, size: 18),
            title: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                fontFamily: 'Cairo',
              ),
            ),
            trailing: Icon(
              _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: Colors.white54,
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14, top: 4),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  widget.content,
                  style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
