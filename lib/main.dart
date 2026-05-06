import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'utils/app_theme.dart';
import 'providers/app_providers.dart';
import 'providers/chat_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/shortages_screen.dart';
import 'screens/reps_screen.dart';
import 'screens/debts_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/pin_lock_screen.dart';
import 'database/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // تهيئة قاعدة البيانات
    await DatabaseHelper.instance.database;
  } catch (e) {
    // في حالة فشل تهيئة قاعدة البيانات، نستمر comunque لتجنب تعطل التطبيق تمامًا
    debugPrint('خطأ في تهيئة قاعدة البيانات: $e');
  }
  try {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  } catch (e) {
    debugPrint('خطأ في إعداد واجهة النظام: $e');
  }
  runApp(const SaydaliApp());
}

class SaydaliApp extends StatelessWidget {
  const SaydaliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ShortagesProvider()..load()),
        ChangeNotifierProvider(create: (_) => CustomersProvider()..load()),
        ChangeNotifierProvider(create: (_) => RepsProvider()..load()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (ctx, themeProvider, _) => MaterialApp(
          title: 'صيدلي PRO',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.mode,
          debugShowCheckedModeBanner: false,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

// ── شاشة البداية ──────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _scaleAnim = Tween<double>(begin: 0.7, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    bool isValid = false;
    try {
      final expiryStr =
          await DatabaseHelper.instance.getSetting('subscription_expiry');
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry != null && expiry.isAfter(DateTime.now())) {
          isValid = true;
        }
      }
    } catch (e) {
      debugPrint('خطأ في قراءة إعدادات الاشتراك: $e');
      // في حالة الخطأ، نفترض أن الاشتراك غير صالح ونوجه المستخدم لشاشة الاشتراك
    }

    if (isValid) {
      final hasPIN = await PinLockScreen.isPinEnabled();
      if (hasPIN && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (ctx) => PinLockScreen(
              onSuccess: () => Navigator.pushReplacement(
                ctx,
                MaterialPageRoute(builder: (_) => const MainScreen()),
              ),
            ),
          ),
        );
      } else if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const MainScreen()));
      }
    } else {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 5)
                    ],
                  ),
                  child: const Center(
                      child: Text('💊', style: TextStyle(fontSize: 50))),
                ),
                const SizedBox(height: 20),
                const Text('صيدلي',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1)),
                const Text('PRO',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4)),
                const SizedBox(height: 40),
                const SizedBox(
                    width: 40,
                    child: LinearProgressIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.darkBorder)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── الشاشة الرئيسية مع Bottom Nav ──────────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final _screens = const [
    DashboardScreen(),
    ShortagesScreen(),
    RepsScreen(),
    DebtsScreen(),
    ReportsScreen(),
    ChatScreen(),
    SettingsScreen(),
  ];

  final _tabs = const [
    (icon: Icons.home_rounded, label: 'الرئيسية'),
    (icon: Icons.medication_rounded, label: 'النواقص'),
    (icon: Icons.people_rounded, label: 'المندوبون'),
    (icon: Icons.account_balance_wallet_rounded, label: 'الديون'),
    (icon: Icons.bar_chart_rounded, label: 'التقارير'),
    (icon: Icons.smart_toy_rounded, label: 'حكيم'),
    (icon: Icons.settings_rounded, label: 'الإعدادات'),
  ];

  final _titles = [
    'لوحة التحكم',
    'نواقص اليوم',
    'المندوبون',
    'ديون العملاء',
    'التقارير',
    'حكيم - المساعد الذكي',
    'الإعدادات',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        backgroundColor: AppColors.darkCard,
        title: Row(
          children: [
            const Text('💊', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('صيدلي',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2)),
                Text(_titles[_currentIndex],
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11, height: 1.2)),
              ],
            ),
          ],
        ),
        actions: [
          // زر إعدادات API للشات بوت
          if (_currentIndex == 5)
            IconButton(
              tooltip: 'إعدادات الذكاء الاصطناعي',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ApiSettingsDialog(),
              ),
              icon: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings_suggest_rounded,
                    color: AppColors.primary, size: 18),
              ),
            ),
          // Badge الاشتراك
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
            child: Container(
              margin: const EdgeInsets.only(left: 8, top: 10, bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('🥈 احترافي',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          // Avatar
          Container(
            margin:
                const EdgeInsets.only(left: 12, right: 4, top: 8, bottom: 8),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark]),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Center(
                child: Text('ص',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14))),
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.darkCard,
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabs.length, (i) {
                final isActive = _currentIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_tabs[i].icon,
                            color: isActive
                                ? AppColors.primary
                                : AppColors.textMuted,
                            size: 22),
                        const SizedBox(height: 2),
                        Text(
                          _tabs[i].label,
                          style: TextStyle(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.textMuted,
                            fontSize: 9,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
