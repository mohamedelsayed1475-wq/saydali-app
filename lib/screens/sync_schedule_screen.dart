import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../services/scheduled_sync_service.dart';
import '../widgets/common_widgets.dart';

class SyncScheduleScreen extends StatefulWidget {
  const SyncScheduleScreen({super.key});

  @override
  State<SyncScheduleScreen> createState() => _SyncScheduleScreenState();
}

class _SyncScheduleScreenState extends State<SyncScheduleScreen>
    with SingleTickerProviderStateMixin {
  List<TimeOfDay> _times = [];
  bool _loading = true;
  bool _saving = false;
  bool _syncing = false;
  String? _lastSyncAt;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final times = await ScheduledSyncService.getScheduleTimes();
    final lastSync = await DatabaseHelper.instance.getSetting('last_sync_at');
    if (mounted) {
      setState(() {
        _times = times.isEmpty
            ? [
                const TimeOfDay(hour: 8, minute: 0),
                const TimeOfDay(hour: 12, minute: 0),
                const TimeOfDay(hour: 16, minute: 0),
                const TimeOfDay(hour: 20, minute: 0),
                const TimeOfDay(hour: 23, minute: 0),
              ]
            : times;
        _lastSyncAt = lastSync;
        _loading = false;
      });
    }
  }

  Future<void> _addTime() async {
    if (_times.length >= 7) {
      showSnack(context, 'الحد الأقصى 7 مواعيد', isError: true);
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.darkCard,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _times.add(picked));
    }
  }

  Future<void> _editTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times[index],
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.darkCard,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _times[index] = picked);
    }
  }

  void _removeTime(int index) {
    if (_times.length <= 1) {
      showSnack(context, 'لازم موعد واحد على الأقل', isError: true);
      return;
    }
    setState(() => _times.removeAt(index));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // ترتيب المواعيد
    _times.sort((a, b) {
      final aMin = a.hour * 60 + a.minute;
      final bMin = b.hour * 60 + b.minute;
      return aMin.compareTo(bMin);
    });
    await ScheduledSyncService.setScheduleTimes(_times);
    await ScheduledSyncService.registerDevice();
    if (mounted) {
      setState(() => _saving = false);
      showSnack(context, 'تم حفظ المواعيد وتفعيل المزامنة التلقائية ✅');
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await ScheduledSyncService.syncNow();
      final lastSync = await DatabaseHelper.instance.getSetting('last_sync_at');
      if (mounted) {
        setState(() {
          _syncing = false;
          _lastSyncAt = lastSync;
        });
        showSnack(context, 'تمت المزامنة بنجاح ✅');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _syncing = false);
        showSnack(context, 'فشلت المزامنة: $e', isError: true);
      }
    }
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'ص' : 'م';
    return '$hour:$minute $period';
  }

  String _formatLastSync() {
    if (_lastSyncAt == null) return 'لم تتم بعد';
    final dt = DateTime.tryParse(_lastSyncAt!);
    if (dt == null) return _lastSyncAt!;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        backgroundColor: AppColors.darkCard,
        title: const Text('مواعيد المزامنة',
            style: TextStyle(
                color: AppColors.textColor,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo')),
        iconTheme: const IconThemeData(color: AppColors.textColor),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : FadeTransition(
              opacity: CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── بانر الشرح ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.15),
                          AppColors.accent.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Text('🔄', style: TextStyle(fontSize: 36)),
                        const SizedBox(height: 8),
                        const Text('مزامنة تلقائية في الخلفية',
                            style: TextStyle(
                                color: AppColors.textColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(
                          'حدد مواعيد المزامنة وكل الأجهزة هتتزامن تلقائياً بدون ما تفتح التطبيق. '
                          'البيانات بتترفع للسحابة مؤقتاً وبتتمسح بعد ما كل الأجهزة تسحبها.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textMuted.withValues(alpha: 0.8),
                              fontSize: 12,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── آخر مزامنة ──
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text('📡', style: TextStyle(fontSize: 22)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('آخر مزامنة',
                                  style: TextStyle(
                                      color: AppColors.textMuted, fontSize: 11)),
                              Text(_formatLastSync(),
                                  style: const TextStyle(
                                      color: AppColors.textColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                            ],
                          ),
                        ),
                        _syncing
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2.5),
                              )
                            : IconButton(
                                onPressed: _syncNow,
                                icon: const Icon(Icons.sync_rounded,
                                    color: AppColors.primary),
                                tooltip: 'مزامنة الآن',
                              ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── عنوان المواعيد ──
                  Row(
                    children: [
                      const Text('⏰', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('مواعيد المزامنة',
                            style: TextStyle(
                                color: AppColors.textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ),
                      Text('${_times.length}/7',
                          style: TextStyle(
                              color: _times.length >= 7
                                  ? AppColors.warning
                                  : AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── قائمة المواعيد ──
                  ...List.generate(_times.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_formatTime(_times[i]),
                                  style: const TextStyle(
                                      color: AppColors.textColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16)),
                            ),
                            IconButton(
                              onPressed: () => _editTime(i),
                              icon: const Icon(Icons.edit_rounded,
                                  color: AppColors.primary, size: 20),
                              tooltip: 'تعديل',
                            ),
                            IconButton(
                              onPressed: () => _removeTime(i),
                              icon: const Icon(Icons.delete_rounded,
                                  color: AppColors.danger, size: 20),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // ── زر إضافة موعد ──
                  if (_times.length < 7) ...[
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _addTime,
                      icon: const Icon(Icons.add_rounded, color: AppColors.primary),
                      label: const Text('إضافة موعد',
                          style: TextStyle(color: AppColors.primary, fontFamily: 'Cairo')),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── زر الحفظ ──
                  _saving
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : PrimaryButton(
                          text: 'حفظ وتفعيل المزامنة التلقائية',
                          onTap: _save,
                        ),

                  const SizedBox(height: 20),

                  // ── ملاحظة ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('💡', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لازم الموبايل يكون متوصل بالإنترنت في وقت الموعد عشان المزامنة تتم. '
                            'لو فاتك موعد، الموعد الجاي هينزّل كل اللي فاتك.',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
