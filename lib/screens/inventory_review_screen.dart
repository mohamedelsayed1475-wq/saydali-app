import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../providers/current_user_provider.dart';
import 'fast_count_screen.dart';

class InventoryReviewScreen extends StatefulWidget {
  final int sessionId;

  const InventoryReviewScreen({super.key, required this.sessionId});

  @override
  State<InventoryReviewScreen> createState() => _InventoryReviewScreenState();
}

class _InventoryReviewScreenState extends State<InventoryReviewScreen> {
  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _selectedFilter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final session = await DatabaseHelper.instance.getInventorySession(widget.sessionId);
    final items = await DatabaseHelper.instance.getInventoryItems(
      widget.sessionId,
      statusFilter: _selectedFilter,
      search: _searchQuery,
    );

    if (mounted) {
      setState(() {
        _session = session;
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _approveSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 8),
            Text('اعتماد نتيجة الجرد', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'هل أنت متأكد من اعتماد نتائج الجرد؟\nسيتم إغلاق الجلسة كجلسة مكتملة ومعتمدة.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، اعتماد ✅', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final userProvider = context.read<CurrentUserProvider>();
      await DatabaseHelper.instance.approveInventorySession(widget.sessionId, userProvider.currentName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🏆 تم اعتماد الجلسة بنجاح!'), backgroundColor: AppColors.primary),
        );
        _loadData();
      }
    }
  }

  Future<void> _requestRecountAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.replay_rounded, color: AppColors.warning, size: 28),
            SizedBox(width: 8),
            Text('طلب إعادة العد للجلسة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'سيتم مسح عمليات العد السابقة وإعادة تعيين حالة جميع الأصناف لإعادة عدها من جديد.\n\nهل تريد المتابعة؟',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('طلب إعادة العد 🔄', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.requestInventoryRecount(widget.sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحويل الجلسة إلى إعادة العد 🔄')),
        );
        _loadData();
      }
    }
  }

  Future<void> _exportAndShareReport() async {
    if (_session == null) return;

    final allItems = await DatabaseHelper.instance.getInventoryItems(widget.sessionId);
    final buffer = StringBuffer();
    buffer.writeln('📋 *تقرير جرد صيدلية: ${_session!['title']}*');
    buffer.writeln('📅 التاريخ: ${_session!['created_at']?.toString().substring(0, 10) ?? ''}');
    buffer.writeln('👤 المسؤول: ${_session!['created_by'] ?? ''}');
    buffer.writeln('────────────────────────');
    buffer.writeln('📊 إجمالي الأصناف: ${_session!['total_items'] ?? 0}');
    buffer.writeln('✅ الأصناف المطابقة: ${_session!['matched_items'] ?? 0}');
    buffer.writeln('📈 أصناف الزيادة: ${_session!['surplus_items'] ?? 0}');
    buffer.writeln('📉 أصناف العجز: ${_session!['deficit_items'] ?? 0}');
    buffer.writeln('────────────────────────\n');

    final deficits = allItems.where((it) => it['status'] == 'deficit').toList();
    if (deficits.isNotEmpty) {
      buffer.writeln('🔴 *أصناف العجز:*');
      for (final it in deficits) {
        buffer.writeln('• ${it['name']}: مسجل ${it['system_quantity']} | فعلي ${it['actual_quantity']} | الفرق (${it['difference']})');
      }
      buffer.writeln('');
    }

    final surplus = allItems.where((it) => it['status'] == 'surplus').toList();
    if (surplus.isNotEmpty) {
      buffer.writeln('🔵 *أصناف الزيادة:*');
      for (final it in surplus) {
        buffer.writeln('• ${it['name']}: مسجل ${it['system_quantity']} | فعلي ${it['actual_quantity']} | الفرق (+${it['difference']})');
      }
      buffer.writeln('');
    }

    buffer.writeln('صيدلي PRO - نظام إدارة الصيدليات الذكي');

    await Share.share(buffer.toString(), subject: 'تقرير جرد ${_session!['title']}');
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<CurrentUserProvider>();

    if (!userProvider.isOwner) {
      return Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          title: const Text('مراجعة الجرد'),
          backgroundColor: AppColors.darkCard,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 64, color: AppColors.danger),
              const SizedBox(height: 14),
              const Text('شاشة مخصصة للمالك فقط', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('ليس لديك الصلاحية لمراجعة واعتماد الجرد', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('رجوع'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          title: const Text('مراجعة الجرد'),
          backgroundColor: AppColors.darkCard,
        ),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final session = _session;
    if (session == null) {
      return Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(title: const Text('مراجعة الجرد')),
        body: const Center(child: Text('الجلسة غير موجودة', style: TextStyle(color: Colors.white))),
      );
    }

    final total = session['total_items'] ?? 0;
    final counted = session['counted_items'] ?? 0;
    final matched = session['matched_items'] ?? 0;
    final surplus = session['surplus_items'] ?? 0;
    final deficit = session['deficit_items'] ?? 0;
    final isCompleted = session['status'] == 'completed';

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: Text(session['title'] ?? 'مراجعة الجرد'),
        backgroundColor: AppColors.darkCard,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: AppColors.primary),
            tooltip: 'مشاركة التقرير',
            onPressed: _exportAndShareReport,
          ),
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Color(0xFF00D4B4)),
            tooltip: 'العد السريع',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FastCountScreen(
                    sessionId: widget.sessionId,
                    sessionTitle: session['title'] ?? 'جلسة جرد',
                  ),
                ),
              ).then((_) => _loadData());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ملخص إحصائي
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.darkCard,
              border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _statBadge('إجمالي الأصناف', '$total', Colors.white70),
                    const SizedBox(width: 8),
                    _statBadge('تم العد', '$counted', const Color(0xFF00D4B4)),
                    const SizedBox(width: 8),
                    _statBadge('مطابق', '$matched', AppColors.primary),
                    const SizedBox(width: 8),
                    _statBadge('زيادة', '$surplus', const Color(0xFF3B82F6)),
                    const SizedBox(width: 8),
                    _statBadge('عجز', '$deficit', AppColors.danger),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCompleted ? AppColors.primary.withValues(alpha: 0.15) : AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isCompleted ? AppColors.primary : AppColors.warning),
                        ),
                        child: Text(
                          isCompleted ? '🏆 حالة الجلسة: معتمدة ومكتملة' : '⏳ حالة الجلسة: قيد المراجعة والعد',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isCompleted ? AppColors.primary : AppColors.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // شريط البحث وفلاتر الحالات
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'بحث في أصناف الجرد...',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
                    fillColor: AppColors.darkCard,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (q) {
                    _searchQuery = q;
                    _loadData();
                  },
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('الكل', 'all'),
                      const SizedBox(width: 6),
                      _filterChip('🔴 عجز', 'deficit'),
                      const SizedBox(width: 6),
                      _filterChip('🔵 زيادة', 'surplus'),
                      const SizedBox(width: 6),
                      _filterChip('🟢 مطابق', 'matched'),
                      const SizedBox(width: 6),
                      _filterChip('⚪ لم يُعد', 'pending'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // قائمة الأصناف
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text('لا توجد أصناف مطابقة للبحث أو الفلتر', style: TextStyle(color: AppColors.textMuted)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final systemQty = (item['system_quantity'] as num?)?.toDouble() ?? 0.0;
                      final actual = item['actual_quantity'];
                      final diff = item['difference'];
                      final status = item['status'];

                      Color statusColor = AppColors.textMuted;
                      String statusText = 'لم يُعد';
                      if (actual != null) {
                        if (status == 'matched') {
                          statusColor = AppColors.primary;
                          statusText = 'مطابق (0)';
                        } else if (status == 'surplus') {
                          statusColor = const Color(0xFF3B82F6);
                          statusText = 'زيادة (+${diff})';
                        } else if (status == 'deficit') {
                          statusColor = AppColors.danger;
                          statusText = 'عجز (${diff})';
                        }
                      }

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 44,
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name'] ?? '',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        'المسجل: ${systemQty == systemQty.roundToDouble() ? systemQty.toInt() : systemQty}',
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'الفعلي: ${actual ?? "—"}',
                                        style: TextStyle(
                                          color: actual != null ? Colors.white : AppColors.textMuted,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: statusColor.withValues(alpha: 0.6)),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // شريط أزرار الاعتماد وإعادة العد في الأسفل للمالك
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppColors.darkCard,
              border: Border(top: BorderSide(color: AppColors.darkBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _requestRecountAll,
                    icon: const Icon(Icons.replay_rounded, size: 16, color: AppColors.warning),
                    label: const Text('طلب إعادة عد 🔄', style: TextStyle(color: AppColors.warning, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.warning),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: isCompleted ? null : _approveSession,
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      isCompleted ? 'الجلسة معتمدة ✅' : 'اعتماد نتيجة الجرد 🏆',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBadge(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.darkCard,
      onSelected: (_) {
        setState(() => _selectedFilter = value);
        _loadData();
      },
    );
  }
}
