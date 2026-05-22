import 'dart:async';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';
import 'expenses_screen.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<Map<String, dynamic>> _statsFuture;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _statsFuture = DatabaseHelper.instance.getStatisticsSummary();
    // تحديث تلقائي كل 4 ثوانٍ
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        setState(() {
          _statsFuture = DatabaseHelper.instance.getStatisticsSummary();
        });
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('الإحصائيات والأرباح 📊', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snapshot.hasError) {
            return const Center(child: Text('حدث خطأ أثناء تحميل الإحصائيات', style: TextStyle(color: AppColors.danger)));
          }

          final data = snapshot.data!;
          final totalSales = data['total_sales'] as double;
          final totalDebts = data['total_debts'] as double;
          final pendingShortages = data['pending_shortages_count'] as int;
          final topSelling = data['top_selling_items'] as List<Map<String, dynamic>>;
          final totalExpenses = (data['total_expenses'] as num?)?.toDouble() ?? 0.0;
          final netProfit = totalSales - totalExpenses;
          final expensesByCategory = data['expenses_by_category'] as List<Map<String, dynamic>>? ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // زر إدارة المصروفات
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ExpensesScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.payment_rounded, color: AppColors.primary),
                            SizedBox(width: 12),
                            Text(
                              'إدارة وتتبع المصروفات التشغيلية 💸',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 16),
                      ],
                    ),
                  ),
                ),

                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStatCard(
                        title: 'إجمالي المبيعات',
                        value: '${totalSales.toStringAsFixed(0)} ج.م',
                        icon: Icons.point_of_sale_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMiniStatCard(
                        title: 'إجمالي المصروفات',
                        value: '${totalExpenses.toStringAsFixed(0)} ج.م',
                        icon: Icons.payments_rounded,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _buildStatCard(
                  title: 'صافي الأرباح (المبيعات - المصروفات)',
                  value: '${netProfit.toStringAsFixed(2)} ج.م',
                  icon: Icons.trending_up_rounded,
                  color: netProfit >= 0 ? AppColors.primary : AppColors.danger,
                ),
                const SizedBox(height: 12),

                _buildStatCard(
                  title: 'أموالك في السوق (الديون المستحقة)',
                  value: '${totalDebts.toStringAsFixed(2)} ج.م',
                  icon: Icons.account_balance_wallet_rounded,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 12),

                _buildStatCard(
                  title: 'النواقص المطلوبة حالياً',
                  value: '$pendingShortages صنف',
                  icon: Icons.inventory_2_rounded,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 24),

                // تصنيف المصروفات
                if (expensesByCategory.isNotEmpty) ...[
                  const Text(
                    '📊 توزيع المصروفات التشغيلية',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Column(
                      children: expensesByCategory.map((item) {
                        final catName = item['category']?.toString() ?? 'أخرى';
                        final catTotal = item['total'] as double;
                        final percent = totalExpenses > 0 ? (catTotal / totalExpenses) : 0.0;
                        
                        Color catColor = Colors.grey;
                        if (catName == 'رواتب') catColor = Colors.blue;
                        else if (catName == 'إيجار') catColor = Colors.purple;
                        else if (catName == 'كهرباء ومياه') catColor = Colors.amber;
                        else if (catName == 'مشتريات ونواقص') catColor = Colors.teal;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(catName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  Text(
                                    '${catTotal.toStringAsFixed(0)} ج.م (${(percent * 100).toStringAsFixed(0)}%)',
                                    style: TextStyle(color: catColor, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percent,
                                  backgroundColor: AppColors.dark,
                                  valueColor: AlwaysStoppedAnimation<Color>(catColor),
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                const Text(
                  '🔥 الأصناف الأكثر مبيعاً (Top 5)',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (topSelling.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text('لا توجد مبيعات مسجلة بعد', style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                ...topSelling.map((item) => Card(
                  color: AppColors.darkCard,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.medication_liquid_rounded, color: Colors.white, size: 20),
                    ),
                    title: Text(item['name']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: Text('${item['qty']} علبة', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                )).toList(),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white60, fontSize: 11), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
