import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../providers/current_user_provider.dart';

class FastCountScreen extends StatefulWidget {
  final int sessionId;
  final String sessionTitle;

  const FastCountScreen({
    super.key,
    required this.sessionId,
    required this.sessionTitle,
  });

  @override
  State<FastCountScreen> createState() => _FastCountScreenState();
}

class _FastCountScreenState extends State<FastCountScreen> {
  List<Map<String, dynamic>> _items = [];
  int _currentIndex = 0;
  bool _loading = true;
  final _qtyController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final items = await DatabaseHelper.instance.getInventoryItems(widget.sessionId);
    if (!mounted) return;

    // العثور على أول صنف لم يتم عده بعد للبدء منه تلقائياً
    int firstUncounted = items.indexWhere((it) => it['actual_quantity'] == null);
    if (firstUncounted == -1) firstUncounted = 0;

    setState(() {
      _items = items;
      _currentIndex = items.isNotEmpty ? firstUncounted : 0;
      _loading = false;
    });

    _syncCurrentItemInputs();
  }

  void _syncCurrentItemInputs() {
    if (_items.isEmpty || _currentIndex >= _items.length) return;
    final item = _items[_currentIndex];
    final actual = item['actual_quantity'];
    if (actual != null) {
      final double val = (actual as num).toDouble();
      _qtyController.text = val == val.roundToDouble() ? val.toInt().toString() : val.toString();
    } else {
      _qtyController.clear();
    }
    _notesController.text = item['notes']?.toString() ?? '';
  }

  Future<void> _saveCurrentAndNext() async {
    if (_items.isEmpty || _currentIndex >= _items.length) return;

    final item = _items[_currentIndex];
    final text = _qtyController.text.trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال الكمية الفعلية أو تخطي الصنف')),
      );
      return;
    }

    final actualQty = double.tryParse(text);
    if (actualQty == null || actualQty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رقم صحيح موجب')),
      );
      return;
    }

    final userProvider = context.read<CurrentUserProvider>();
    final countedBy = userProvider.currentName;
    final notes = _notesController.text.trim();

    await DatabaseHelper.instance.updateInventoryItemCount(
      item['id'] as int,
      actualQty,
      countedBy,
      notes: notes.isNotEmpty ? notes : null,
    );

    // تحديث العنصر محلياً في القائمة
    final systemQty = (item['system_quantity'] as num?)?.toDouble() ?? 0.0;
    final diff = actualQty - systemQty;
    String status = 'matched';
    if (diff > 0.001) status = 'surplus';
    if (diff < -0.001) status = 'deficit';

    setState(() {
      _items[_currentIndex] = {
        ..._items[_currentIndex],
        'actual_quantity': actualQty,
        'difference': diff,
        'status': status,
        'counted_by': countedBy,
      };

      if (_currentIndex < _items.length - 1) {
        _currentIndex++;
        _syncCurrentItemInputs();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 تم عد جميع أصناف الجلسة بنجاح!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    });
  }

  void _previousItem() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _syncCurrentItemInputs();
      });
    }
  }

  void _skipNext() {
    if (_currentIndex < _items.length - 1) {
      setState(() {
        _currentIndex++;
        _syncCurrentItemInputs();
      });
    }
  }

  void _adjustQty(double delta) {
    double current = double.tryParse(_qtyController.text) ?? 0.0;
    current += delta;
    if (current < 0) current = 0;
    setState(() {
      _qtyController.text = current == current.roundToDouble() ? current.toInt().toString() : current.toString();
    });
  }

  void _showJumpSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.darkBorder,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'قائمة أصناف الجرد',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.darkBorder, height: 1),
                      itemBuilder: (context, i) {
                        final it = _items[i];
                        final isSelected = i == _currentIndex;
                        final actual = it['actual_quantity'];
                        final isCounted = actual != null;

                        Color badgeColor = AppColors.textMuted;
                        String badgeText = 'لم يُعد';
                        if (isCounted) {
                          final status = it['status'];
                          if (status == 'matched') {
                            badgeColor = AppColors.primary;
                            badgeText = 'مطابق ($actual)';
                          } else if (status == 'surplus') {
                            badgeColor = const Color(0xFF3B82F6);
                            badgeText = 'زيادة ($actual)';
                          } else if (status == 'deficit') {
                            badgeColor = AppColors.danger;
                            badgeText = 'عجز ($actual)';
                          }
                        }

                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
                          leading: CircleAvatar(
                            backgroundColor: isSelected ? AppColors.primary : AppColors.dark,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            it['name'] ?? '',
                            style: TextStyle(
                              color: isSelected ? AppColors.primary : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            'المسجل: ${it['system_quantity'] ?? 0}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _currentIndex = i;
                              _syncCurrentItemInputs();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          title: Text(widget.sessionTitle),
          backgroundColor: AppColors.darkCard,
        ),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          title: Text(widget.sessionTitle),
          backgroundColor: AppColors.darkCard,
        ),
        body: const Center(
          child: Text(
            'لا توجد أصناف في هذه الجلسة',
            style: TextStyle(color: AppColors.textMuted, fontSize: 16),
          ),
        ),
      );
    }

    final currentItem = _items[_currentIndex];
    final totalItems = _items.length;
    final countedCount = _items.where((it) => it['actual_quantity'] != null).length;
    final progress = totalItems > 0 ? (countedCount / totalItems) : 0.0;

    final systemQty = (currentItem['system_quantity'] as num?)?.toDouble() ?? 0.0;
    final double? enteredQty = double.tryParse(_qtyController.text);

    // حساب الفرق الفوري
    String diffLabel = 'أدخل الكمية';
    Color diffColor = AppColors.textMuted;
    if (enteredQty != null) {
      final diff = enteredQty - systemQty;
      if (diff.abs() < 0.001) {
        diffLabel = 'مطابق (0)';
        diffColor = AppColors.primary;
      } else if (diff > 0) {
        final valStr = diff == diff.roundToDouble() ? diff.toInt().toString() : diff.toStringAsFixed(1);
        diffLabel = 'زيادة (+ $valStr)';
        diffColor = const Color(0xFF3B82F6);
      } else {
        final valStr = diff.abs() == diff.abs().roundToDouble() ? diff.abs().toInt().toString() : diff.abs().toStringAsFixed(1);
        diffLabel = 'عجز (- $valStr)';
        diffColor = AppColors.danger;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.sessionTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('صنف ${_currentIndex + 1} من $totalItems', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
        backgroundColor: AppColors.darkCard,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.format_list_bulleted_rounded, color: AppColors.primary),
            tooltip: 'قائمة الأصناف',
            onPressed: _showJumpSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // شريط التقدم
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.darkCard,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 4,
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // بطاقة الصنف الحالي
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'صنف ${_currentIndex + 1} / $totalItems',
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                              if (currentItem['barcode'] != null && currentItem['barcode'].toString().isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.qr_code_rounded, size: 14, color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                      currentItem['barcode'].toString(),
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            currentItem['name'] ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.dark,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.darkBorder),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('الكمية المسجلة بالسيستم:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                Text(
                                  '${systemQty == systemQty.roundToDouble() ? systemQty.toInt() : systemQty}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // حقل العد الفعلي
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: diffColor.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'الكمية الفعلية بالمخزن',
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () => _adjustQty(-1),
                                icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger, size: 36),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 130,
                                child: TextField(
                                  controller: _qtyController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '0',
                                    hintStyle: const TextStyle(color: AppColors.textMuted),
                                    fillColor: AppColors.dark,
                                    filled: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(color: AppColors.darkBorder),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: diffColor, width: 2),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                onPressed: () => _adjustQty(1),
                                icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 36),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // أزرار سريعة
                          Wrap(
                            spacing: 8,
                            children: [
                              _quickAddChip('+5', 5),
                              _quickAddChip('+10', 10),
                              _quickAddChip('+20', 20),
                              _quickSetChip('مطابق', systemQty),
                              _quickSetChip('صفر', 0),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // بادج الفرق الفوري
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: diffColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: diffColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  diffColor == AppColors.primary
                                      ? Icons.check_circle_outline
                                      : (diffColor == AppColors.danger ? Icons.error_outline : Icons.trending_up),
                                  color: diffColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  diffLabel,
                                  style: TextStyle(color: diffColor, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ملاحظات اختيارية
                    TextField(
                      controller: _notesController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'ملاحظات الصنف (اختياري)...',
                        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        fillColor: AppColors.darkCard,
                        filled: true,
                        prefixIcon: const Icon(Icons.note_alt_outlined, color: AppColors.textMuted, size: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // أزرار التحكم السفلية
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.darkCard,
                border: Border(top: BorderSide(color: AppColors.darkBorder)),
              ),
              child: Row(
                children: [
                  // زر السابق
                  OutlinedButton.icon(
                    onPressed: _currentIndex > 0 ? _previousItem : null,
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    label: const Text('السابق'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: AppColors.darkBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // زر تخطي
                  OutlinedButton(
                    onPressed: _currentIndex < totalItems - 1 ? _skipNext : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      side: const BorderSide(color: AppColors.darkBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    child: const Text('تخطي'),
                  ),
                  const SizedBox(width: 8),

                  // زر حفظ والتالي
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveCurrentAndNext,
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(
                        _currentIndex < totalItems - 1 ? 'حفظ والتالي ⏭️' : 'حفظ وإنهاء الجلسة 🏁',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAddChip(String label, double val) {
    return ActionChip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      backgroundColor: AppColors.dark,
      onPressed: () => _adjustQty(val),
    );
  }

  Widget _quickSetChip(String label, double val) {
    return ActionChip(
      label: Text(label, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      onPressed: () {
        setState(() {
          _qtyController.text = val == val.roundToDouble() ? val.toInt().toString() : val.toString();
        });
      },
    );
  }
}
