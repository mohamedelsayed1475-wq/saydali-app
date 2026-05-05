import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'shortages_screen.dart';
import 'debts_screen.dart';
import 'rep_response_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, int> _stats = {};
  double _totalDebt = 0;
  bool _loading = true;
  static bool _adShown = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    if (!_adShown) {
      _adShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndShowAd());
    }
  }

  Future<void> _checkAndShowAd() async {
    final ad = await DatabaseHelper.instance.getActiveAd('home');
    if (ad == null) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AdDialog(ad: ad),
    );
  }

  Future<void> _loadData() async {
    final stats = await DatabaseHelper.instance.getShortageStats();
    final debt = await DatabaseHelper.instance.getTotalDebt();

    if (mounted) {
      setState(() {
        _stats = stats;
        _totalDebt = debt;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    final total = _stats['total'] ?? 0;
    final covered = _stats['covered'] ?? 0;
    final stubborn = _stats['stubborn'] ?? 0;
    final pending = _stats['pending'] ?? 0;
    final offered = _stats['offered'] ?? 0;
    final rate = total > 0 ? (covered / total) : 0.0;

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.darkCard,
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D2E1C), Color(0xFF0A3525)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primaryDark),
            ),
            child: Row(
              children: [
                const Text('🤖', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تنبيه ذكي',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        total == 0
                            ? 'لا توجد نواقص اليوم 🎉'
                            : 'لديك $total صنف ناقص، $pending في انتظار رد المندوبين',
                        style: const TextStyle(
                            color: AppColors.textLight, fontSize: 12),
                      ),
                      if (pending > 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: AppColors.danger.withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            '⚠️ تنبيه: سيتم تحويل الأصناف المعلقة منذ 24 ساعة إلى مستعصية تلقائياً',
                            style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Stats Row 1
          Row(
            children: [
              StatCard(icon: '💊', value: '$total', label: 'إجمالي النواقص'),
              const SizedBox(width: 10),
              StatCard(
                  icon: '✅',
                  value: '$covered',
                  label: 'تمت التغطية',
                  valueColor: AppColors.primary),
            ],
          ),
          const SizedBox(height: 10),

          // Stats Row 2
          Row(
            children: [
              StatCard(
                  icon: '⚠️',
                  value: '$stubborn',
                  label: 'مستعصية',
                  valueColor: AppColors.danger),
              const SizedBox(width: 10),
              StatCard(
                icon: '📈',
                value: '${(rate * 100).toStringAsFixed(0)}%',
                label: 'معدل التغطية',
                valueColor: AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Coverage Bar
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('معدل التغطية اليوم',
                        style: TextStyle(
                            color: AppColors.textLight,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    Text('${(rate * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 10),
                GradientProgressBar(value: rate),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _legendItem(AppColors.primary, 'تمت ($covered)'),
                    _legendItem(const Color(0xFF2563EB), 'عروض ($offered)'),
                    _legendItem(AppColors.warning, 'انتظار ($pending)'),
                    _legendItem(AppColors.danger, 'مستعصي ($stubborn)'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Debt Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.danger.withValues(alpha: 0.15),
                  AppColors.darkCard
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Text('💰', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('إجمالي ديون العملاء',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                    Text(
                      '${_totalDebt.toStringAsFixed(2)} جنيه',
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Quick Actions
          const Text('⚡ وصول سريع',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.5,
            children: [
              _quickAction('➕', 'ناقص جديد', AppColors.primary, () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ShortagesScreen()));
              }),
              _quickAction('👤', 'عميل جديد', AppColors.accent, () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DebtsScreen()));
              }),
              _quickAction('📤', 'رد المندوب', const Color(0xFF2563EB), () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RepResponseScreen()));
              }),
              _quickAction('📊', 'التقارير', AppColors.warning, () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ReportsScreen()));
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _quickAction(
      String emoji, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class AdDialog extends StatefulWidget {
  final Map<String, dynamic> ad;
  const AdDialog({super.key, required this.ad});

  @override
  State<AdDialog> createState() => _AdDialogState();
}

class _AdDialogState extends State<AdDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.ad['skip_duration'] ?? 0;
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _remaining--;
          if (_remaining <= 0) {
            timer.cancel();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.ad['image_url'] != null &&
        widget.ad['image_url'].toString().isNotEmpty;
    final hasLink =
        widget.ad['link'] != null && widget.ad['link'].toString().isNotEmpty;

    return PopScope(
      canPop: _remaining <= 0,
      child: Dialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasImage)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.file(
                  File(widget.ad['image_url']),
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => const SizedBox(
                      height: 100,
                      child: Center(
                          child: Icon(Icons.broken_image,
                              color: AppColors.textMuted, size: 40))),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(widget.ad['title'],
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(widget.ad['body'],
                      style: const TextStyle(
                          color: AppColors.textColor, fontSize: 14),
                      textAlign: TextAlign.center),
                  if (hasLink) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        final url = Uri.tryParse(widget.ad['link']);
                        if (url != null)
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent),
                      child: Text(widget.ad['button_text'] ?? 'التفاصيل',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(color: AppColors.darkBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: _remaining > 0
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('يمكنك التخطي بعد $_remaining ثانية',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                          textAlign: TextAlign.center),
                    )
                  : TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('تخطي الإعلان',
                          style: TextStyle(color: AppColors.textMuted)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
