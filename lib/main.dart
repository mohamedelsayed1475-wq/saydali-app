import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'utils/app_theme.dart';
import 'providers/app_providers.dart';
import 'providers/current_user_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/shortages_screen.dart';
import 'screens/reps_screen.dart';
import 'screens/debts_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/pin_lock_screen.dart';
import 'screens/user_selection_screen.dart';
import 'database/database_helper.dart';
import 'utils/security_helper.dart';
import 'services/sync_service.dart';
import 'services/scheduled_sync_service.dart';
import 'services/notification_service.dart';

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
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('خطأ في تهيئة الإشعارات: $e');
  }
  try {
    await ScheduledSyncService.initialize();
  } catch (e) {
    debugPrint('خطأ في تهيئة WorkManager: $e');
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
        ChangeNotifierProvider(create: (_) => CurrentUserProvider()),
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

    // ── فحص أمان الجهاز (Root Detection) ──
    final warnings = await SecurityHelper.runSecurityChecks();
    if (warnings.isNotEmpty && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            textDirection: TextDirection.rtl,
            children: [
              Text('⚠️', style: TextStyle(fontSize: 24)),
              SizedBox(width: 8),
              Text('تحذير أمني', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: warnings.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                w,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            )).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('فهمت، متابعة', style: TextStyle(color: Color(0xFF00C896))),
            ),
          ],
        ),
      );
    }

    if (!mounted) return;

    bool isValid = false;
    try {
      // ── فحص أمني محلي (HMAC + server time) ──
      isValid = await SecurityHelper.isSubscriptionValid();

      // ── تحقق سحابي (لو فيه إنترنت) ──
      if (isValid) {
        final cloudResult = await SecurityHelper.verifySubscriptionCloud();
        if (cloudResult == false) {
          isValid = false;
        }
      }
    } catch (e) {
      debugPrint('خطأ في قراءة إعدادات الاشتراك: $e');
    }

    if (isValid) {
      final hasPIN = await PinLockScreen.isPinEnabled();
      if (hasPIN && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (ctx) => PinLockScreen(
              onSuccess: () => _goToUserSelectionOrMain(ctx),
            ),
          ),
        );
      } else if (mounted) {
        await _goToUserSelectionOrMain(context);
      }
    } else {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
    }
  }

  /// التحقق إذا كانت ميزة المساعدين مفعلة ثم التوجيه
  Future<void> _goToUserSelectionOrMain(BuildContext ctx) async {
    final activated = await DatabaseHelper.instance.getSetting('assistants_activated');
    final assistants = await DatabaseHelper.instance.getAssistants();
    final hasActiveAssistants = assistants.any((a) => (a['is_active'] ?? 1) == 1);

    if (!ctx.mounted) return;

    if (activated == '1' && hasActiveAssistants) {
      // عرض شاشة اختيار المستخدم
      Navigator.pushReplacement(
        ctx,
        MaterialPageRoute(
          builder: (navCtx) => UserSelectionScreen(
            onOwnerSelected: () {
              // تسجيل الصيدلية وبدء المزامنة
              SyncService.instance.registerPharmacy().then((_) {
                SyncService.instance.startPeriodicSync();
                ScheduledSyncService.registerDevice();
              });
              Navigator.pushReplacement(
                navCtx,
                MaterialPageRoute(builder: (_) => const MainScreen()),
              );
            },
            onAssistantSelected: () {
              // بدء المزامنة للمساعد
              SyncService.instance.startPeriodicSync();
              Navigator.pushReplacement(
                navCtx,
                MaterialPageRoute(builder: (_) => const MainScreen()),
              );
            },
          ),
        ),
      );
    } else {
      // دخول مباشر كمالك
      if (ctx.mounted) {
        ctx.read<CurrentUserProvider>().loginAsOwner();
        // تسجيل الصيدلية وبدء المزامنة
        SyncService.instance.registerPharmacy().then((_) {
          SyncService.instance.startPeriodicSync();
          ScheduledSyncService.registerDevice();
        });
        Navigator.pushReplacement(
          ctx,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
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
    SettingsScreen(),
  ];

  final _tabs = const [
    (icon: Icons.home_rounded, label: 'الرئيسية'),
    (icon: Icons.medication_rounded, label: 'النواقص'),
    (icon: Icons.people_rounded, label: 'المندوبون'),
    (icon: Icons.account_balance_wallet_rounded, label: 'الديون'),
    (icon: Icons.bar_chart_rounded, label: 'التقارير'),
    (icon: Icons.settings_rounded, label: 'الإعدادات'),
  ];

  final _titles = [
    'لوحة التحكم',
    'نواقص اليوم',
    'المندوبون',
    'ديون العملاء',
    'التقارير',
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
          // معلومات المستخدم الحالي + تبديل
          Consumer<CurrentUserProvider>(
            builder: (ctx, userProvider, _) {
              final name = userProvider.currentName;
              final isOwner = userProvider.isOwner;
              return GestureDetector(
                onTap: () => _showUserMenu(userProvider),
                child: Container(
                  margin: const EdgeInsets.only(
                      left: 12, right: 4, top: 8, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isOwner
                          ? [const Color(0xFFFFD700), const Color(0xFFFFA500)]
                          : [AppColors.accent, AppColors.primary],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(isOwner ? '👑' : '👤',
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              );
            },
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

  /// قائمة خيارات المستخدم
  void _showUserMenu(CurrentUserProvider userProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.darkBorder,
                    borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 16),
            // معلومات المستخدم الحالي
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: userProvider.isOwner
                        ? const Color(0xFFFFD700).withValues(alpha: 0.3)
                        : AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: userProvider.isOwner
                          ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                          : AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                        child: Text(
                            userProvider.isOwner ? '👑' : '👤',
                            style: const TextStyle(fontSize: 24))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userProvider.currentName,
                            style: const TextStyle(
                                color: AppColors.textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        Text(
                            userProvider.isOwner
                                ? 'صلاحيات كاملة'
                                : userProvider.currentUser?.permissionsSummary ?? '',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // تبديل المستخدم
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded,
                  color: AppColors.primary),
              title: const Text('تبديل المستخدم',
                  style: TextStyle(color: AppColors.textColor)),
              subtitle: const Text('الدخول بحساب آخر',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              tileColor: AppColors.dark,
              onTap: () {
                Navigator.pop(ctx);
                userProvider.logout();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (navCtx) => UserSelectionScreen(
                      onOwnerSelected: () {
                        SyncService.instance.registerPharmacy().then((_) {
                          SyncService.instance.startPeriodicSync();
                          ScheduledSyncService.registerDevice();
                        });
                        Navigator.pushReplacement(
                          navCtx,
                          MaterialPageRoute(builder: (_) => const MainScreen()),
                        );
                      },
                      onAssistantSelected: () {
                        SyncService.instance.startPeriodicSync();
                        Navigator.pushReplacement(
                          navCtx,
                          MaterialPageRoute(builder: (_) => const MainScreen()),
                        );
                      },
                    ),
                  ),
                  (route) => false,
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
