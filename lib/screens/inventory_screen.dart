import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../providers/current_user_provider.dart';
import 'new_inventory_session_screen.dart';
import 'fast_count_screen.dart';
import 'inventory_review_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    final sessions = await DatabaseHelper.instance.getInventorySessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  Future<void> _deleteSession(int id, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 24),
            SizedBox(width: 8),
            Text('حذف جلسة الجرد', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف جلسة "$title" وجميع نتائج العد الخاصة بها؟',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteInventorySession(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الجلسة بنجاح 🗑️')),
        );
        _loadSessions();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<CurrentUserProvider>();
    final isOwner = userProvider.isOwner;

    final activeSessionsCount = _sessions.where((s) => s['status'] == 'in_progress' || s['status'] == 'recount_requested').length;
    final completedSessionsCount = _sessions.where((s) => s['status'] == 'completed').length;
    final totalItemsCount = _sessions.fold<int>(0, (sum, s) => sum + ((s['total_items'] as num?)?.toInt() ?? 0));

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.darkCard,
        onRefresh: _loadSessions,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // بطاقات إحصائيات سريعة
                  Row(
                    children: [
                      _buildStatCard('جلسات نشطة', '$activeSessionsCount', Icons.timelapse_rounded, const Color(0xFF00D4B4)),
                      const SizedBox(width: 10),
                      _buildStatCard('جلسات مكتملة', '$completedSessionsCount', Icons.verified_rounded, AppColors.primary),
                      const SizedBox(width: 10),
                      _buildStatCard('إجمالي الأصناف', '$totalItemsCount', Icons.inventory_2_outlined, const Color(0xFF3B82F6)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ترويسة الجلسات وزر البدء
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.format_list_bulleted_rounded, color: AppColors.primary, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'جلسات الجرد السابقة والحالية',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NewInventorySessionScreen()),
                          ).then((_) => _loadSessions());
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('جرد جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // قائمة الجلسات
                  if (_sessions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.textMuted),
                          const SizedBox(height: 14),
                          const Text(
                            'لا توجد أي جلسات جرد بعد',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'ابدأ جلسة جرد لمطابقة المخزون الفعلي مع المسجل بالسيستم وكشف الفروق بدقة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NewInventorySessionScreen()),
                              ).then((_) => _loadSessions());
                            },
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                            label: const Text('بدء أول جلسة جرد 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._sessions.map((session) => _buildSessionCard(session, isOwner)),
                ],
              ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, bool isOwner) {
    final id = session['id'] as int;
    final title = session['title'] ?? 'جلسة #$id';
    final status = session['status'] ?? 'in_progress';
    final total = (session['total_items'] as num?)?.toInt() ?? 0;
    final counted = (session['counted_items'] as num?)?.toInt() ?? 0;
    final matched = (session['matched_items'] as num?)?.toInt() ?? 0;
    final surplus = (session['surplus_items'] as num?)?.toInt() ?? 0;
    final deficit = (session['deficit_items'] as num?)?.toInt() ?? 0;
    final createdBy = session['created_by'] ?? '';
    final createdAt = session['created_at']?.toString().substring(0, 10) ?? '';

    final progress = total > 0 ? (counted / total) : 0.0;

    Color statusColor = AppColors.warning;
    String statusText = 'قيد الجرد';
    if (status == 'completed') {
      statusColor = AppColors.primary;
      statusText = 'معتمدة ومكتملة';
    } else if (status == 'recount_requested') {
      statusColor = const Color(0xFFFF6B35);
      statusText = 'إعادة عد مطلوبة';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
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
              const Icon(Icons.person_outline, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(createdBy, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(width: 14),
              const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(createdAt, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),

          const SizedBox(height: 12),

          // شريط نسبة العد
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('نسبة الإنجاز: $counted من $total صنف', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text('${(progress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.dark,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 12),

          // إحصائيات سريعة للنتائج
          Row(
            children: [
              _resultBadge('🟢 مطابق: $matched', AppColors.primary),
              const SizedBox(width: 8),
              _resultBadge('🔵 زيادة: $surplus', const Color(0xFF3B82F6)),
              const SizedBox(width: 8),
              _resultBadge('🔴 عجز: $deficit', AppColors.danger),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(color: AppColors.darkBorder, height: 1),
          const SizedBox(height: 10),

          // أزرار العمليات
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FastCountScreen(
                          sessionId: id,
                          sessionTitle: title,
                        ),
                      ),
                    ).then((_) => _loadSessions());
                  },
                  icon: const Icon(Icons.flash_on_rounded, size: 16),
                  label: const Text('العد السريع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              if (isOwner) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InventoryReviewScreen(sessionId: id),
                        ),
                      ).then((_) => _loadSessions());
                    },
                    icon: const Icon(Icons.rate_review_outlined, size: 16),
                    label: const Text('المراجعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                tooltip: 'حذف الجلسة',
                onPressed: () => _deleteSession(id, title),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
