import 'dart:async';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';

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
    // تحديث تلقائي كل 30 ثانية
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatCard(
                  title: 'إجمالي المبيعات',
                  value: '${totalSales.toStringAsFixed(2)} ج.م',
                  icon: Icons.point_of_sale_rounded,
                  color: AppColors.primary,
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
                const SizedBox(height: 32),
                const Text(
                  '🔥 الأصناف الأكثر مبيعاً (Top 5)',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
}
