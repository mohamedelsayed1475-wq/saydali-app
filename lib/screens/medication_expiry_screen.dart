import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'scanner_screen.dart';

class MedicationExpiryScreen extends StatefulWidget {
  const MedicationExpiryScreen({super.key});

  @override
  State<MedicationExpiryScreen> createState() => _MedicationExpiryScreenState();
}

class _MedicationExpiryScreenState extends State<MedicationExpiryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MedicationExpiry> _allExpiries = [];
  List<MedicationExpiry> _filteredExpiries = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadExpiries();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    _filterList();
  }

  Future<void> _loadExpiries() async {
    setState(() => _loading = true);
    try {
      final data = await DatabaseHelper.instance.getMedicationExpiries();
      setState(() {
        _allExpiries = data.map((map) => MedicationExpiry.fromMap(map)).toList();
        _loading = false;
      });
      _filterList();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        showSnack(context, '⚠️ خطأ أثناء تحميل تواريخ الصلاحية: $e', isError: true);
      }
    }
  }

  void _filterList() {
    List<MedicationExpiry> temp = _allExpiries;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      temp = temp
          .where((item) =>
              item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (item.supplierName != null &&
                  item.supplierName!.toLowerCase().contains(_searchQuery.toLowerCase())))
          .toList();
    }

    // Apply tab filter
    final now = DateTime.now();
    final limit3m = now.add(const Duration(days: 90));
    final limit6m = now.add(const Duration(days: 180));

    switch (_tabController.index) {
      case 1: // منتهي
        temp = temp.where((item) => item.isExpired).toList();
        break;
      case 2: // حرج (خلال 3 أشهر)
        temp = temp.where((item) => !item.isExpired && item.expiryDate.isBefore(limit3m)).toList();
        break;
      case 3: // تحذير (خلال 6 أشهر)
        temp = temp.where((item) => !item.isExpired && item.expiryDate.isAfter(limit3m) && item.expiryDate.isBefore(limit6m)).toList();
        break;
      case 0: // الكل
      default:
        break;
    }

    setState(() {
      _filteredExpiries = temp;
    });
  }

  Future<void> _showAddEditModal({MedicationExpiry? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final qtyCtrl = TextEditingController(text: existing?.quantity.toString() ?? '1');
    final supplierCtrl = TextEditingController(text: existing?.supplierName ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    DateTime selectedDate = existing?.expiryDate ?? DateTime.now().add(const Duration(days: 365));

    final isEdit = existing != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setBS) => Padding(
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
                    Text(
                      isEdit ? 'تعديل تاريخ صلاحية دواء' : 'إضافة تاريخ صلاحية دواء',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // اسم الدواء
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'اسم الدواء أو الباركود *',
                          prefixIcon: Icon(Icons.medication, color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // زر مسح الباركود
                    InkWell(
                      onTap: () async {
                        final code = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(builder: (_) => const ScannerScreen()),
                        );
                        if (code != null && code.isNotEmpty) {
                          setBS(() {
                            nameCtrl.text = code;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // الكمية
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'الكمية (علبة)',
                    prefixIcon: Icon(Icons.production_quantity_limits_rounded, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 12),

                // المورد
                TextField(
                  controller: supplierCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'اسم المورد أو الشركة',
                    prefixIcon: Icon(Icons.business_rounded, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 12),

                // اختيار تاريخ الانتهاء
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: AppColors.primary,
                            onPrimary: Colors.white,
                            surface: AppColors.darkCard,
                            onSurface: Colors.white,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setBS(() {
                        selectedDate = picked;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      border: Border.all(color: AppColors.darkBorder),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 20),
                            SizedBox(width: 12),
                            Text('تاريخ انتهاء الصلاحية', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                        Text(
                          DateFormat('yyyy-MM').format(selectedDate),
                          style: const TextStyle(
                              color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ملاحظات
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات إضافية',
                    prefixIcon: Icon(Icons.notes, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      showSnack(ctx, 'يرجى إدخال اسم الدواء', isError: true);
                      return;
                    }
                    final qty = int.tryParse(qtyCtrl.text) ?? 1;

                    final data = {
                      'name': name,
                      'quantity': qty,
                      'expiry_date': selectedDate.toIso8601String().substring(0, 10),
                      'supplier_name': supplierCtrl.text.trim(),
                      'notes': notesCtrl.text.trim(),
                    };

                    try {
                      if (isEdit) {
                        await DatabaseHelper.instance.updateMedicationExpiry(existing.id!, data);
                      } else {
                        await DatabaseHelper.instance.insertMedicationExpiry(data);
                      }
                      Navigator.pop(ctx);
                      _loadExpiries();
                      if (mounted) {
                        showSnack(context, isEdit ? 'تم تحديث تاريخ الصلاحية ✅' : 'تمت الإضافة بنجاح ✅');
                      }
                    } catch (e) {
                      showSnack(ctx, '⚠️ فشل الحفظ: $e', isError: true);
                    }
                  },
                  child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة الصنف'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteItem(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('حذف تاريخ الصلاحية', style: TextStyle(color: Colors.white)),
        content: const Text('هل أنت متأكد من حذف هذا الصنف من قائمة الصلاحيات؟', style: TextStyle(color: AppColors.textLight)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await DatabaseHelper.instance.deleteMedicationExpiry(id);
        _loadExpiries();
        if (mounted) {
          showSnack(context, 'تم حذف الصنف بنجاح 🗑️');
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
        title: const Text('صلاحية الأدوية 📅',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 28),
            onPressed: () => _showAddEditModal(),
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
                _filterList();
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'البحث باسم الدواء أو المورد...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                fillColor: AppColors.darkCard,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // التبويبات
          TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.primary,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'),
            tabs: const [
              Tab(text: 'الكل'),
              Tab(text: 'منتهي'),
              Tab(text: 'حرج (3أشهر)'),
              Tab(text: 'تحذير (6أشهر)'),
            ],
          ),

          const SizedBox(height: 10),

          // قائمة البيانات
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _filteredExpiries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🚫', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'لا توجد أدوية مسجلة في هذا القسم'
                                  : 'لا توجد نتائج مطابقة لبحثك',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        itemCount: _filteredExpiries.length,
                        itemBuilder: (ctx, idx) {
                          final item = _filteredExpiries[idx];
                          return _buildMedicationCard(item);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(MedicationExpiry item) {
    final now = DateTime.now();
    final remainingDays = item.expiryDate.difference(now).inDays;
    
    Color statusColor;
    String statusText;

    if (item.isExpired) {
      statusColor = AppColors.danger;
      statusText = 'منتهي الصلاحية ⛔';
    } else if (remainingDays <= 90) {
      statusColor = AppColors.warning;
      statusText = 'حرج جداً ⚠️';
    } else if (remainingDays <= 180) {
      statusColor = Colors.orange;
      statusText = 'قارب على الانتهاء ⏳';
    } else {
      statusColor = AppColors.primary;
      statusText = 'آمن ✅';
    }

    return Card(
      color: AppColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.production_quantity_limits_rounded, color: AppColors.textMuted, size: 16),
                const SizedBox(width: 6),
                Text('الكمية: ${item.quantity} علبة', style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                if (item.supplierName != null && item.supplierName!.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.business_rounded, color: AppColors.textMuted, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'المورد: ${item.supplierName}',
                      style: const TextStyle(color: AppColors.textLight, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: AppColors.textMuted, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'انتهاء الصلاحية: ${DateFormat('yyyy-MM').format(item.expiryDate)}',
                      style: const TextStyle(color: AppColors.textLight, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  item.isExpired
                      ? 'منتهي منذ ${-remainingDays} يوم'
                      : 'متبقي $remainingDays يوم',
                  style: TextStyle(
                      color: item.isExpired ? AppColors.danger : AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.dark.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '📝 ملاحظة: ${item.notes}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ),
            ],

            const SizedBox(height: 8),
            const Divider(color: AppColors.darkBorder, height: 1),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showAddEditModal(existing: item),
                  icon: const Icon(Icons.edit, size: 16, color: AppColors.primary),
                  label: const Text('تعديل', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteItem(item.id!),
                  icon: const Icon(Icons.delete, size: 16, color: AppColors.danger),
                  label: const Text('حذف', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
