import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'shortages_screen.dart';
import 'debts_screen.dart';
import 'rep_response_screen.dart';
import 'invoice_screen.dart';
import 'documents_screen.dart';
import 'statistics_screen.dart';
import 'rep_message_parser_screen.dart';

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
  String _currency = 'ج.م';
  List<Map<String, dynamic>> _alerts = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // تحديث تلقائي كل 30 ثانية
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadData();
    });
    if (!_adShown) {
      _adShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndShowAd());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkAndShowAd() async {
    // ── مزامنة الإعلانات من السحابة أولاً ──
    try {
      final cloudAds = await SupabaseService.instance.fetchAds();
      if (cloudAds.isNotEmpty) {
        await DatabaseHelper.instance.syncAdsFromCloud(cloudAds);
      }
    } catch (_) {}

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
    try {
      // Load all queries in parallel for better performance
      final results = await Future.wait([
        DatabaseHelper.instance.getShortageStats(),
        DatabaseHelper.instance.getTotalDebt(),
        DatabaseHelper.instance.getCurrency(),
      ]);

      final stats = results[0] as Map<String, int>;
      final debt = results[1] as double;
      final currency = results[2] as String;

      // بناء التنبيهات الذكية
      final alerts = <Map<String, dynamic>>[];

      // 1. نواقص معلقة > 12 ساعة
      final db = await DatabaseHelper.instance.database;
      final twelveHoursAgo =
          DateTime.now().subtract(const Duration(hours: 12)).toIso8601String();
      final oldPending = await db.query('shortages',
          where: "status = 'pending' AND created_at <= ?",
          whereArgs: [twelveHoursAgo]);
      if (oldPending.isNotEmpty) {
        alerts.add({
          'icon': '⏰',
          'title': '${oldPending.length} صنف قرب يبقى مستعصي!',
          'subtitle': 'معلق أكتر من 12 ساعة - تواصل مع المندوب',
          'color': AppColors.warning,
        });
      }

      // 2. ديون كبيرة
      final customers = await DatabaseHelper.instance.getCustomers();
      final highDebt = customers
          .where((c) => (c['total_debt'] as num) > 500)
          .toList();
      if (highDebt.isNotEmpty) {
        alerts.add({
          'icon': '💸',
          'title': '${highDebt.length} عميل عليه دين كبير',
          'subtitle': 'إجمالي: ${debt.toStringAsFixed(0)} $currency',
          'color': AppColors.danger,
        });
      }

      // 2.5 ديون مستحقة اليوم/غداً
      final dueDebts = await DatabaseHelper.instance.getDueDebts();
      if (dueDebts.isNotEmpty) {
        alerts.add({
          'icon': '📅',
          'title': '${dueDebts.length} عميل ميعاد سداده قرب!',
          'subtitle': 'تواصل معاهم لتحصيل الديون',
          'color': AppColors.warning,
        });
      }

      // 3. نواقص مستعصية
      final stubbornCount = stats['stubborn'] ?? 0;
      if (stubbornCount > 3) {
        alerts.add({
          'icon': '🔴',
          'title': '$stubbornCount صنف مستعصي',
          'subtitle': 'جرب مندوب تاني أو ابحث عن بدائل',
          'color': AppColors.danger,
        });
      }

      // 4. نسبة تغطية ضعيفة
      final total = stats['total'] ?? 0;
      final covered = stats['covered'] ?? 0;
      if (total > 5 && covered / total < 0.3) {
        alerts.add({
          'icon': '📉',
          'title': 'نسبة التغطية ضعيفة (${((covered / total) * 100).toStringAsFixed(0)}%)',
          'subtitle': 'حاول تتواصل مع المندوبين',
          'color': AppColors.warning,
        });
      }

      // 5. أخبار إيجابية
      if (alerts.isEmpty && total > 0) {
        alerts.add({
          'icon': '🎉',
          'title': 'كل حاجة تمام!',
          'subtitle': 'مفيش تنبيهات عاجلة - استمر!',
          'color': AppColors.primary,
        });
      }

      if (mounted) {
        setState(() {
          _stats = stats;
          _totalDebt = debt;
          _currency = currency;
          _alerts = alerts;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
          // Smart Alerts
          if (_alerts.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D2E1C), Color(0xFF0A3525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('🤖', style: TextStyle(fontSize: 20)),
                      SizedBox(width: 8),
                      Text('تنبيهات ذكية',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ..._alerts.map((a) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a['icon'], style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a['title'],
                                      style: TextStyle(
                                          color: a['color'] as Color,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                  Text(a['subtitle'],
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

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
          const SizedBox(height: 10),

          // Stats Row 3 - Pending & Offered
          Row(
            children: [
              StatCard(
                  icon: '⏳',
                  value: '$pending',
                  label: 'بانتظار الرد',
                  valueColor: AppColors.warning),
              const SizedBox(width: 10),
              StatCard(
                  icon: '🎁',
                  value: '$offered',
                  label: 'عروض متاحة',
                  valueColor: const Color(0xFF2563EB)),
            ],
          ),

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
                      '${_totalDebt.toStringAsFixed(2)} $_currency',
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
              _quickAction('📈', 'الإحصائيات', AppColors.warning, () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const StatisticsScreen()));
              }),
              _quickAction('🧾', 'فاتورة جديدة', const Color(0xFF8B5CF6), () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const InvoiceScreen()));
              }),
              _quickAction('📁', 'المستندات', const Color(0xFF10B981), () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DocumentsScreen()));
              }),
              _quickAction('🪄', 'تحليل رسائل', AppColors.accent, () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RepMessageParserScreen()));
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
