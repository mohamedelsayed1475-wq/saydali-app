import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';
import 'expenses_screen.dart';

// ─────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────

const List<String> _kArabicDays = ['إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد'];

String _dayLabel(String isoDate) {
  try {
    final d = DateTime.parse(isoDate);
    // weekday: 1=Mon … 7=Sun
    return _kArabicDays[(d.weekday - 1) % 7];
  } catch (_) {
    return isoDate;
  }
}

// ─────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  Map<String, dynamic> _statsData = {};
  List<Map<String, dynamic>> _dailySales = [];
  Timer? _refreshTimer;
  String _currency = 'ج.م';
  int _filterIndex = 0; // 0=اليوم 1=أسبوع 2=شهر 3=سنة
  final List<String> _filters = ['اليوم', 'الأسبوع', 'الشهر', 'السنة'];

  // micro-animation for trend line
  late AnimationController _lineCtrl;
  late Animation<double> _lineAnim;

  @override
  void initState() {
    super.initState();
    _lineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _lineAnim = CurvedAnimation(parent: _lineCtrl, curve: Curves.easeOut);
    _loadCurrency();
    _loadAll(isRefresh: false);
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _loadAll(isRefresh: true));
  }

  Future<void> _loadCurrency() async {
    final c = await DatabaseHelper.instance.getCurrency();
    if (mounted) setState(() => _currency = c);
  }

  Future<void> _loadAll({required bool isRefresh}) async {
    if (!isRefresh && mounted) setState(() => _loading = true);
    try {
      final data = await DatabaseHelper.instance.getStatisticsSummary();
      final daily = await DatabaseHelper.instance.getDailySalesLastWeek();
      if (mounted) {
        setState(() {
          _statsData = data;
          _dailySales = daily;
          _loading = false;
        });
        _lineCtrl.forward(from: 0);
      }
    } catch (e) {
      debugPrint('Statistics load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _lineCtrl.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilterBar(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary))
                  : _statsData.isEmpty
                      ? const Center(
                          child: Text('حدث خطأ في التحميل',
                              style: TextStyle(color: AppColors.danger)))
                      : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Custom Header ──────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        border: Border(
            bottom: BorderSide(color: AppColors.darkBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Back
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          const Expanded(
            child: Text(
              '📊 الإحصائيات والأرباح',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Actions
          Row(
            children: [
              _headerAction(Icons.notifications_outlined, () {}),
              const SizedBox(width: 8),
              _headerAction(Icons.settings_outlined, () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerAction(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  // ── Filter Bar ─────────────────────────────────────────

  Widget _buildFilterBar() {
    return Container(
      color: AppColors.darkCard,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: List.generate(_filters.length, (i) {
          final selected = i == _filterIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _filterIndex = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : AppColors.dark,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _filters[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textMuted,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────

  Widget _buildBody() {
    final data = _statsData;
    final totalSales = (data['total_sales'] as num?)?.toDouble() ?? 0;
    final totalCost = (data['total_cost'] as num?)?.toDouble() ?? 0;
    final grossProfit = (data['gross_profit'] as num?)?.toDouble() ?? 0;
    final netProfit = (data['net_profit'] as num?)?.toDouble() ?? 0;
    final totalDebts = (data['total_debts'] as num?)?.toDouble() ?? 0;
    final pendingShortages = (data['pending_shortages_count'] as num?)?.toInt() ?? 0;
    final totalExpenses = (data['total_expenses'] as num?)?.toDouble() ?? 0;
    final expensesByCategory =
        data['expenses_by_category'] as List<Map<String, dynamic>>? ?? [];
    final topSelling =
        data['top_selling_items'] as List<Map<String, dynamic>>? ?? [];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ① Big net profit card
            _buildNetProfitCard(netProfit),
            const SizedBox(height: 14),

            // ② 2-col grid: مبيعات + تكلفة
            Row(
              children: [
                Expanded(
                    child: _buildMiniCard(
                  title: 'إجمالي المبيعات',
                  value: totalSales.toStringAsFixed(0),
                  subtitle: '▲ 18% عن أمس',
                  subtitleColor: AppColors.primary,
                  icon: Icons.shopping_bag_rounded,
                  iconBg: const Color(0xFF0F3460),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _buildMiniCard(
                  title: 'تكلفة المشتريات',
                  value: totalCost.toStringAsFixed(0),
                  subtitle: totalCost == 0 ? '— لا توجد مشتريات' : '',
                  subtitleColor: AppColors.textMuted,
                  icon: Icons.store_mall_directory_rounded,
                  iconBg: const Color(0xFF3D2A1E),
                )),
              ],
            ),
            const SizedBox(height: 10),

            // ③ 2-col grid: مكسب + مصروفات
            Row(
              children: [
                Expanded(
                    child: _buildMiniCard(
                  title: 'المكسب الإجمالي\n(المبيعات - التكلفة)',
                  value: grossProfit.toStringAsFixed(0),
                  subtitle: '▲ 18% عن أمس',
                  subtitleColor: AppColors.primary,
                  icon: Icons.monetization_on_rounded,
                  iconBg: const Color(0xFF1B3A2A),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _buildMiniCard(
                  title: 'أموالك في السوق\n(الديون المستحقة)',
                  value: totalDebts.toStringAsFixed(0),
                  subtitle: '— بدون تغيير',
                  subtitleColor: AppColors.textMuted,
                  icon: Icons.account_balance_wallet_rounded,
                  iconBg: const Color(0xFF3B2F08),
                )),
              ],
            ),
            const SizedBox(height: 10),

            // ④ 2-col grid: مصروفات + نواقص
            Row(
              children: [
                Expanded(
                    child: _buildMiniCard(
                  title: 'المصروفات التشغيلية',
                  value: totalExpenses.toStringAsFixed(0),
                  subtitle: '▼ 8% عن أمس',
                  subtitleColor: AppColors.danger,
                  icon: Icons.payments_rounded,
                  iconBg: const Color(0xFF3B1010),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _buildMiniCard(
                  title: 'النواقص المطلوبة',
                  value: '$pendingShortages صنف',
                  subtitle: pendingShortages == 0 ? '— لا توجد نواقص' : '',
                  subtitleColor: AppColors.textMuted,
                  icon: Icons.inventory_2_rounded,
                  iconBg: const Color(0xFF2A1040),
                  isValueLarge: false,
                )),
              ],
            ),
            const SizedBox(height: 22),

            // ⑤ Bar chart: مبيعات آخر 7 أيام
            _buildSalesBarChart(),
            const SizedBox(height: 22),

            // ⑥ Expenses donut
            if (expensesByCategory.isNotEmpty) ...[
              _buildExpensesDonut(expensesByCategory, totalExpenses),
              const SizedBox(height: 22),
            ],

            // ⑦ Top 5 list
            _buildTop5(topSelling),

            // ⑧ Expenses management button
            const SizedBox(height: 16),
            _buildExpensesButton(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ── Big Net Profit Card ────────────────────────────────

  Widget _buildNetProfitCard(double netProfit) {
    final isPositive = netProfit >= 0;
    final color = isPositive ? AppColors.primary : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.darkCard,
            color.withOpacity(0.12),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: icon + info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                          isPositive
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          color: color,
                          size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'صافي الأرباح',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.info_outline_rounded,
                        color: Colors.white30, size: 14),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${netProfit.toStringAsFixed(2)} $_currency',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isPositive
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: color,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPositive ? '21% مقارنة باليوم بالأمس' : 'أقل من الأمس',
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Right: mini trend line
          SizedBox(
            width: 90,
            height: 60,
            child: AnimatedBuilder(
              animation: _lineAnim,
              builder: (_, __) => CustomPaint(
                painter: _TrendLinePainter(
                  progress: _lineAnim.value,
                  color: color,
                  data: _dailySales.isEmpty
                      ? [0, 20, 40, 30, 70, 60, 90]
                      : _dailySales
                          .map((e) => (e['total'] as double))
                          .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mini Stat Card ─────────────────────────────────────

  Widget _buildMiniCard({
    required String title,
    required String value,
    required String subtitle,
    required Color subtitleColor,
    required IconData icon,
    required Color iconBg,
    bool isValueLarge = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white70, size: 18),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
            maxLines: 2,
          ),
          const SizedBox(height: 4),
          Text(
            '$value $_currency',
            style: TextStyle(
              color: Colors.white,
              fontSize: isValueLarge ? 18 : 16,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                  color: subtitleColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  // ── Bar Chart ──────────────────────────────────────────

  Widget _buildSalesBarChart() {
    return Container(
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
              const Text(
                'المبيعات خلال الأيام الماضية',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () {},
                child: const Row(
                  children: [
                    Text('عرض التفاصيل',
                        style: TextStyle(
                            color: AppColors.primary, fontSize: 12)),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_left_rounded,
                        color: AppColors.primary, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _lineAnim,
            builder: (_, __) => SizedBox(
              height: 130,
              child: CustomPaint(
                painter: _BarChartPainter(
                  data: _dailySales,
                  progress: _lineAnim.value,
                  barColor: AppColors.primary,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Day labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _dailySales.map((d) {
              return Text(
                _dayLabel(d['day'] as String),
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Expenses Donut ─────────────────────────────────────

  Widget _buildExpensesDonut(
      List<Map<String, dynamic>> categories, double total) {
    final colors = [
      Colors.purple,
      Colors.blue,
      Colors.teal,
      Colors.amber,
      Colors.orange,
    ];

    return Container(
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
              const Text(
                'توزيع المصروفات التشغيلية',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ExpensesScreen()));
                },
                child: const Row(
                  children: [
                    Text('عرض التفاصيل',
                        style: TextStyle(
                            color: AppColors.primary, fontSize: 12)),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_left_rounded,
                        color: AppColors.primary, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Donut
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      painter: _DonutPainter(
                        data: categories,
                        total: total,
                        colors: colors,
                      ),
                      child: const SizedBox(width: 120, height: 120),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          total.toStringAsFixed(0),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _currency,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Legend
              Expanded(
                child: Column(
                  children: List.generate(
                      math.min(categories.length, colors.length), (i) {
                    final cat = categories[i];
                    final name = cat['category']?.toString() ?? 'أخرى';
                    final amt = (cat['total'] as num?)?.toDouble() ?? 0;
                    final pct = total > 0 ? (amt / total * 100).toInt() : 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colors[i % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(name,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ),
                          Text('$pct%',
                              style: TextStyle(
                                  color: colors[i % colors.length],
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Top 5 ──────────────────────────────────────────────

  Widget _buildTop5(List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🔥 الأصناف الأكثر مبيعاً (Top 5)',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Center(
              child: Text('لا توجد مبيعات مسجلة بعد',
                  style: TextStyle(color: Colors.white38)),
            ),
          ),
        ...List.generate(items.length, (i) {
          final item = items[i];
          final name = item['name']?.toString() ?? '';
          final qty = item['qty'] ?? 0;
          final rankColor = i == 0
              ? const Color(0xFFFFD700)
              : i == 1
                  ? const Color(0xFFC0C0C0)
                  : i == 2
                      ? const Color(0xFFCD7F32)
                      : AppColors.primary;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Rank circle
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: rankColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: rankColor.withOpacity(0.4)),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                          color: rankColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Name + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'إجمالي المبيعات',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Qty badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Text(
                    '$qty علبة',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
                // Medication icon
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.darkBorder,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.medication_rounded,
                      color: Colors.white54, size: 18),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── Expenses button ────────────────────────────────────

  Widget _buildExpensesButton() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ExpensesScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          border: Border.all(color: AppColors.primary.withOpacity(0.35)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.payment_rounded, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Text(
                  'إدارة وتتبع المصروفات التشغيلية 💸',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ],
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.primary, size: 14),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  CustomPainters
// ─────────────────────────────────────────────────────────

/// Mini trend line inside the net profit card
class _TrendLinePainter extends CustomPainter {
  final double progress;
  final Color color;
  final List<double> data;

  _TrendLinePainter(
      {required this.progress, required this.color, required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxVal = data.reduce(math.max);
    if (maxVal == 0) return;

    final paint = Paint()
      ..color = color.withOpacity(0.9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final pts = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = size.height - (data[i] / maxVal) * size.height * 0.85;
      pts.add(Offset(x, y));
    }

    // clip to progress
    final clipW = size.width * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clipW, size.height));

    // fill
    final fillPath = Path();
    fillPath.moveTo(pts.first.dx, size.height);
    for (final p in pts) fillPath.lineTo(p.dx, p.dy);
    fillPath.lineTo(pts.last.dx, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // line
    final path = Path();
    path.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, paint);
    canvas.restore();

    // dot at last point
    if (progress >= 0.95) {
      canvas.drawCircle(
          pts.last, 4, Paint()..color = color..style = PaintingStyle.fill);
      canvas.drawCircle(
          pts.last,
          4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_TrendLinePainter old) =>
      old.progress != progress || old.data != data;
}

/// Bar chart for last 7 days
class _BarChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final double progress;
  final Color barColor;

  _BarChartPainter(
      {required this.data, required this.progress, required this.barColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final values = data.map((d) => (d['total'] as double)).toList();
    final maxVal = values.reduce(math.max);

    final barW = size.width / data.length * 0.55;
    final gap = size.width / data.length * 0.45;

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    for (int g = 1; g <= 4; g++) {
      final y = size.height * (1 - g / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (int i = 0; i < data.length; i++) {
      final val = values[i];
      final frac = maxVal > 0 ? val / maxVal : 0.0;
      final barH = frac * size.height * 0.88 * progress;

      final x = i * (barW + gap) + gap / 2;
      final y = size.height - barH;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, y, barW, barH),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );

      // gradient bar
      final gradient = LinearGradient(
        colors: [
          barColor.withOpacity(0.5),
          barColor,
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      );

      final barPaint = Paint()
        ..shader =
            gradient.createShader(Rect.fromLTWH(x, y, barW, barH));

      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.progress != progress || old.data != data;
}

/// Donut chart for expenses
class _DonutPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final double total;
  final List<Color> colors;

  _DonutPainter(
      {required this.data, required this.total, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * 0.9;
    const strokeW = 18.0;

    double startAngle = -math.pi / 2;

    for (int i = 0; i < data.length && i < colors.length; i++) {
      final val = (data[i]['total'] as num?)?.toDouble() ?? 0;
      final sweep = (val / total) * 2 * math.pi;

      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeW / 2),
        startAngle,
        sweep - 0.04,
        false,
        paint,
      );
      startAngle += sweep;
    }

    // center hole fill
    canvas.drawCircle(
      center,
      radius - strokeW,
      Paint()..color = AppColors.darkCard,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.data != data;
}
