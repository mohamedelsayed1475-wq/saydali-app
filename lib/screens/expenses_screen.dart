import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Expense> _expenses = [];
  bool _loading = true;
  double _totalExpenses = 0.0;
  String _selectedFilter = 'all'; // all, daily, weekly, monthly
  String? _selectedCategoryFilter;
  String _currency = 'ج.م';

  final List<String> _categories = [
    'رواتب',
    'إيجار',
    'كهرباء ومياه',
    'مشتريات ونواقص',
    'أخرى'
  ];

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() => _loading = true);
    try {
      String? startDate;
      String? endDate;
      final now = DateTime.now();

      if (_selectedFilter == 'daily') {
        startDate = DateTime(now.year, now.month, now.day).toIso8601String().substring(0, 10);
        endDate = startDate;
      } else if (_selectedFilter == 'weekly') {
        final lastWeek = now.subtract(const Duration(days: 7));
        startDate = lastWeek.toIso8601String().substring(0, 10);
        endDate = now.toIso8601String().substring(0, 10);
      } else if (_selectedFilter == 'monthly') {
        startDate = DateTime(now.year, now.month, 1).toIso8601String().substring(0, 10);
        endDate = now.toIso8601String().substring(0, 10);
      }

      final data = await DatabaseHelper.instance.getExpenses(
        category: _selectedCategoryFilter,
        startDate: startDate,
        endDate: endDate,
      );

      final total = await DatabaseHelper.instance.getTotalExpenses();
      final currency = await DatabaseHelper.instance.getCurrency();

      setState(() {
        _expenses = data.map((e) => Expense.fromMap(e)).toList();
        _totalExpenses = total;
        _currency = currency;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        showSnack(context, '⚠️ خطأ أثناء تحميل المصروفات: $e', isError: true);
      }
    }
  }

  Future<void> _showAddModal() async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedCategory = _categories.first;
    DateTime selectedDate = DateTime.now();

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
                    const Text(
                      'إضافة مصروف جديد 💸',
                      style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // المبلغ
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ *',
                    prefixIcon: Icon(Icons.attach_money_rounded, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 12),

                // الفئة
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  dropdownColor: AppColors.darkCard,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    labelText: 'الفئة',
                    prefixIcon: Icon(Icons.category_rounded, color: AppColors.primary),
                  ),
                  items: _categories
                      .map((cat) => DropdownMenuItem(
                            value: cat,
                            child: Text(cat),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setBS(() => selectedCategory = val);
                    }
                  },
                ),
                const SizedBox(height: 12),

                // تاريخ المصروف
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
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
                      setBS(() => selectedDate = picked);
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
                            Text('تاريخ المصروف', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                        Text(
                          DateFormat('yyyy-MM-dd').format(selectedDate),
                          style: const TextStyle(
                              color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // الوصف
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'الوصف أو الملاحظات',
                    prefixIcon: Icon(Icons.description_rounded, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: () async {
                    final amountText = amountCtrl.text.trim();
                    if (amountText.isEmpty) {
                      showSnack(ctx, 'يرجى إدخال المبلغ', isError: true);
                      return;
                    }
                    final amount = double.tryParse(amountText);
                    if (amount == null || amount <= 0) {
                      showSnack(ctx, 'يرجى إدخال مبلغ صحيح', isError: true);
                      return;
                    }

                    final data = {
                      'category': selectedCategory,
                      'amount': amount,
                      'expense_date': selectedDate.toIso8601String().substring(0, 10),
                      'description': descCtrl.text.trim(),
                    };

                    try {
                      await DatabaseHelper.instance.insertExpense(data);
                      Navigator.pop(ctx);
                      _loadExpenses();
                      if (mounted) {
                        showSnack(context, 'تم تسجيل المصروف بنجاح ✅');
                      }
                    } catch (e) {
                      showSnack(ctx, '⚠️ فشل الحفظ: $e', isError: true);
                    }
                  },
                  child: const Text('إضافة المصروف'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteExpense(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('حذف المصروف', style: TextStyle(color: Colors.white)),
        content: const Text('هل أنت متأكد من حذف هذا المصروف؟', style: TextStyle(color: AppColors.textLight)),
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
        await DatabaseHelper.instance.deleteExpense(id);
        _loadExpenses();
        if (mounted) {
          showSnack(context, 'تم حذف المصروف بنجاح 🗑️');
        }
      } catch (e) {
        if (mounted) {
          showSnack(context, '⚠️ فشل الحذف: $e', isError: true);
        }
      }
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'رواتب':
        return Colors.blue;
      case 'إيجار':
        return Colors.purple;
      case 'كهرباء ومياه':
        return Colors.amber;
      case 'مشتريات ونواقص':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('المصروفات التشغيلية 💸',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 28),
            onPressed: _showAddModal,
          ),
        ],
      ),
      body: Column(
        children: [
          // لوحة المجموع والمصروفات
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary.withValues(alpha: 0.15), AppColors.darkCard],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('💰', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إجمالي المصروفات العامة',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      Text(
                        '${_totalExpenses.toStringAsFixed(2)} $_currency',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // الفلاتر الزمنية
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('all', 'الكل'),
                const SizedBox(width: 8),
                _buildFilterChip('daily', 'اليوم'),
                const SizedBox(width: 8),
                _buildFilterChip('weekly', 'آخر 7 أيام'),
                const SizedBox(width: 8),
                _buildFilterChip('monthly', 'هذا الشهر'),
                const SizedBox(width: 16),
                // فلتر الفئة
                DropdownButton<String?>(
                  value: _selectedCategoryFilter,
                  hint: const Text('كل الفئات', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontFamily: 'Cairo')),
                  dropdownColor: AppColors.darkCard,
                  underline: const SizedBox(),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Cairo'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('كل الفئات'),
                    ),
                    ..._categories.map((cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat),
                        ))
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedCategoryFilter = val;
                    });
                    _loadExpenses();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // قائمة المصروفات
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _expenses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('💸', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text(
                              _selectedCategoryFilter == null && _selectedFilter == 'all'
                                  ? 'لا توجد مصروفات مسجلة بعد'
                                  : 'لا توجد نتائج مطابقة للفلاتر',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _expenses.length,
                        itemBuilder: (ctx, idx) {
                          final item = _expenses[idx];
                          final catColor = _getCategoryColor(item.category);
                           return Container(
                            decoration: BoxDecoration(
                              color: AppColors.darkCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: catColor.withValues(alpha: 0.25)),
                              boxShadow: [
                                BoxShadow(
                                  color: catColor.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: catColor.withValues(alpha: 0.15),
                                child: Icon(Icons.payments_rounded, color: catColor, size: 20),
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item.category,
                                    style: const TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Text(
                                    '- ${item.amount.toStringAsFixed(2)} $_currency',
                                    style: const TextStyle(
                                        color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.description != null && item.description!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(item.description!, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('yyyy-MM-dd').format(item.expenseDate),
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                                onPressed: () => _deleteExpense(item.id!),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFilter = value;
          });
          _loadExpenses();
        }
      },
      selectedColor: AppColors.primary.withValues(alpha: 0.25),
      disabledColor: AppColors.darkCard,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontFamily: 'Cairo',
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? AppColors.primary : AppColors.darkBorder),
      ),
    );
  }
}
