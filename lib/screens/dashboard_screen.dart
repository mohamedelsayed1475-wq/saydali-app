import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../utils/app_theme.dart';
import 'package:provider/provider.dart';
import '../providers/app_providers.dart';
import 'rep_response_screen.dart';
import 'invoice_screen.dart';
import 'documents_screen.dart';
import 'statistics_screen.dart';
import 'rep_message_parser_screen.dart';
import 'medication_expiry_screen.dart';
import 'community_screen.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int tabIndex)? onTabChange;

  const DashboardScreen({super.key, this.onTabChange});

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
  StreamSubscription<void>? _syncSubscription;

  void _switchToTab(int tabIndex) {
    if (widget.onTabChange != null) {
      widget.onTabChange!(tabIndex);
    } else {
      try {
        context.read<NavigationProvider>().setTab(tabIndex);
      } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncSubscription = SyncService.instance.onSyncComplete.listen((_) {
      _loadData();
    });
    if (!_adShown) {
      _adShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndShowAd());
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkAndShowAd() async {
    // ── مزامنة الإعلانات من السحابة أولاً ──
    try {
      final cloudAds = await SupabaseService.instance.fetchAds();
      if (cloudAds != null) {
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
        DatabaseHelper.instance.getExpiringCount(3),
      ]);

      final stats = results[0] as Map<String, int>;
      final debt = results[1] as double;
      final currency = results[2] as String;
      final expiringCount = results[3] as int;

      // بناء التنبيهات الذكية
      final alerts = <Map<String, dynamic>>[];

      // صلاحية الأدوية
      if (expiringCount > 0) {
        alerts.add({
          'icon': '⚠️',
          'title': 'يوجد $expiringCount صنف قارب على انتهاء الصلاحية!',
          'subtitle': 'خلال 3 أشهر - يرجى مراجعة مرتجعات الشركات.',
          'color': AppColors.danger,
        });
      }

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

  List<FlSpot> _generateSpots(double currentRatePct) {
    return [
      FlSpot(0, currentRatePct * 0.1),
      FlSpot(1, currentRatePct * 0.25),
      FlSpot(2, currentRatePct * 0.45),
      FlSpot(3, currentRatePct * 0.65),
      FlSpot(4, currentRatePct * 0.8),
      FlSpot(5, currentRatePct * 0.9),
      FlSpot(6, currentRatePct),
    ];
  }

  Widget _buildCoverageChart(double rate) {
    final ratePct = rate * 100;
    final spots = _generateSpots(ratePct);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F223A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3347), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'معدل التغطية اليوم',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF132A4A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E3347), width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'اليوم',
                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${ratePct.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Color(0xFF00D4B4),
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFF1E3347).withValues(alpha: 0.3),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 25,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            '${value.toInt()}%',
                            style: const TextStyle(
                              color: Color(0xFF7A9BB5),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                      reservedSize: 32,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        const labels = ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '24:00'];
                        final index = value.toInt();
                        if (index >= 0 && index < labels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              labels[index],
                              style: const TextStyle(
                                color: Color(0xFF7A9BB5),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                      reservedSize: 20,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D4B4), Color(0xFF00A07A)],
                    ),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: const Color(0xFF00D4B4),
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00D4B4).withValues(alpha: 0.15),
                          const Color(0xFF00D4B4).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _chartLegendItem(const Color(0xFF00C896), 'تحت التغطية'),
              _chartLegendItem(const Color(0xFF3B82F6), 'عروض'),
              _chartLegendItem(const Color(0xFFF59E0B), 'بانتظار'),
              _chartLegendItem(const Color(0xFFEF4444), 'مستحقة'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7A9BB5),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _quickActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F223A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E3347), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: color,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
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

            // KPI Grid - Row 1 (Right to Left: مستحقة, تحت التغطية, إجمالي النواقص)
            Row(
              children: [
                _KPICard(
                  label: 'مستحقة',
                  value: '$stubborn',
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFEF4444),
                  onTap: () => _switchToTab(1),
                ),
                const SizedBox(width: 10),
                _KPICard(
                  label: 'تحت التغطية',
                  value: '$covered',
                  icon: Icons.shield_outlined,
                  color: const Color(0xFF00C896),
                  onTap: () => _switchToTab(1),
                ),
                const SizedBox(width: 10),
                _KPICard(
                  label: 'إجمالي النواقص',
                  value: '$total',
                  icon: Icons.medical_services_outlined,
                  color: const Color(0xFF00D4B4),
                  onTap: () => _switchToTab(1),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // KPI Grid - Row 2 (Right to Left: عروض متاحة, بانتظار الرد, معدل التغطية)
            Row(
              children: [
                _KPICard(
                  label: 'عروض متاحة',
                  value: '$offered',
                  icon: Icons.card_giftcard_rounded,
                  color: const Color(0xFF8B5CF6),
                  onTap: () => _switchToTab(1),
                ),
                const SizedBox(width: 10),
                _KPICard(
                  label: 'بانتظار الرد',
                  value: '$pending',
                  icon: Icons.hourglass_empty_rounded,
                  color: const Color(0xFF3B82F6),
                  onTap: () => _switchToTab(1),
                ),
                const SizedBox(width: 10),
                _KPICard(
                  label: 'معدل التغطية',
                  value: '${(rate * 100).toStringAsFixed(0)}%',
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFFF59E0B),
                  onTap: () => _switchToTab(1),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Coverage Line Chart Card
            InkWell(
              onTap: () => _switchToTab(1),
              borderRadius: BorderRadius.circular(16),
              child: _buildCoverageChart(rate),
            ),
            const SizedBox(height: 12),

            // Debt Summary Card
            InkWell(
              onTap: () => _switchToTab(4),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F223A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E3347), width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D4B4).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00D4B4).withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D4B4).withValues(alpha: 0.15),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.account_balance_wallet_outlined,
                          color: Color(0xFF00D4B4),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'هذا الشهر',
                          style: TextStyle(
                            color: Color(0xFF7A9BB5),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.trending_up_rounded,
                              color: Color(0xFF00C896),
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '0.00',
                              style: TextStyle(
                                color: AppColors.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'إجمالي ديون العملاء',
                          style: TextStyle(
                            color: Color(0xFF7A9BB5),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_totalDebt.toStringAsFixed(2)} $_currency',
                          style: const TextStyle(
                            color: Color(0xFF00D4B4),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Quick Actions Header
            const Text(
              'عمليات سريعة',
              style: TextStyle(
                color: Color(0xFF7A9BB5),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),

            // Quick Actions Grid (4 Columns)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: [
                _quickActionItem(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'عميل جديد',
                  color: const Color(0xFF00C896),
                  onTap: () => _switchToTab(4),
                ),
                _quickActionItem(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'ناقص جديد',
                  color: const Color(0xFF00D4B4),
                  onTap: () => _switchToTab(1),
                ),
                _quickActionItem(
                  icon: Icons.send_rounded,
                  label: 'رد مندوب',
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RepResponseScreen()));
                  },
                ),
                _quickActionItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'الإحصائيات',
                  color: const Color(0xFFF59E0B),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const StatisticsScreen()));
                  },
                ),
                _quickActionItem(
                  icon: Icons.folder_outlined,
                  label: 'المستندات',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentsScreen()));
                  },
                ),
                _quickActionItem(
                  icon: Icons.monetization_on_outlined,
                  label: 'فاتورة جديدة',
                  color: const Color(0xFF8B5CF6),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceScreen()));
                  },
                ),
                _quickActionItem(
                  icon: Icons.pie_chart_outline_rounded,
                  label: 'تحليل رسائل',
                  color: const Color(0xFFFF6B35),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RepMessageParserScreen()));
                  },
                ),
                _quickActionItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'الأدوية القادمة',
                  color: const Color(0xFFEC4899),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicationExpiryScreen()));
                  },
                ),
                _quickActionItem(
                  icon: Icons.forum_outlined,
                  label: 'المجتمع',
                  color: const Color(0xFF06B6D4),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityScreen()));
                  },
                ),
              ],
            ),
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
                child: widget.ad['image_url'].toString().startsWith('http')
                    ? Image.network(
                        widget.ad['image_url'],
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, st) => const SizedBox(
                            height: 100,
                            child: Center(
                                child: Icon(Icons.broken_image,
                                    color: AppColors.textMuted, size: 40))),
                      )
                    : Image.file(
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

// ── بطاقة إحصائية مخصصة للوحة التحكم ──────────────────────────────────────────────────
class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _KPICard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFF0F223A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E3347), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 3,
                    color: color,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            icon,
                            color: color,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              value,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF7A9BB5),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
