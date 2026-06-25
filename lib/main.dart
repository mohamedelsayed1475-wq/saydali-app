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
import 'screens/assistant_pin_login_screen.dart';
import 'screens/activation_screen.dart';
import 'screens/cloud_setup_screen.dart';
import 'widgets/subscription_guard.dart';
import 'widgets/pharmacy_logo.dart';
import 'models/models.dart';
import 'database/database_helper.dart';
import 'utils/security_helper.dart';
import 'utils/env_config.dart';
import 'services/supabase_service.dart';
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

    final db = DatabaseHelper.instance;

    // ── 1. تحميل الإعدادات الديناميكية للسحابة ──
    try {
      await SupabaseService.instance.initializeDynamic();
    } catch (e) {
      debugPrint('⚠️ خطأ في تحميل إعدادات السحابة: $e');
    }

    // ── 2. فحص هل التطبيق مفعّل؟ ──
    String? isActivated = await db.getSetting('is_activated');

    if (isActivated != '1') {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ActivationScreen()),
      );
      return;
    }

    // ── 3. فحص هل تم إعداد السحابة؟ ──
    String? supabaseUrl = await db.getSetting('supabase_url');
    if (supabaseUrl == null || supabaseUrl.isEmpty) {
      // إذا كان الكود يحتوي على إعدادات سحابية افتراضية صالحة (وليست REPLACE)، نقوم بحفظها وتجاوز شاشة الإعداد
      final defaultUrl = EnvConfig.supabaseUrl;
      final defaultKey = EnvConfig.supabaseKey;
      if (defaultUrl.isNotEmpty && 
          !defaultUrl.contains('REPLACE') && 
          defaultKey.isNotEmpty && 
          !defaultKey.contains('REPLACE')) {
        await db.setSetting('supabase_url', defaultUrl);
        await db.setSetting('supabase_key', defaultKey);
        await db.setSetting('web_portal_url', EnvConfig.webPortalBaseUrl);
        supabaseUrl = defaultUrl;
        // إعادة تهيئة الخدمات بالقيم الجديدة المحفوظة
        try {
          await SupabaseService.instance.initializeDynamic();
        } catch (_) {}
      }
    }

    if (supabaseUrl == null || supabaseUrl.isEmpty) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CloudSetupScreen()),
      );
      return;
    }

    if (!mounted) return;

    // ── 4. فحص أمان الجهاز (Root Detection) ──
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

    // ── 5. التطبيق مفعّل والسحابة جاهزة → دخول مباشر ──
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
  }

  /// التحقق إذا كانت ميزة المساعدين مفعلة ثم التوجيه
  Future<void> _goToUserSelectionOrMain(BuildContext ctx) async {
    final db = DatabaseHelper.instance;
    final isAssistantDevice = await db.getSetting('is_assistant_device');

    if (!ctx.mounted) return;

    if (isAssistantDevice == '1') {
      // ── Assistant Device Flow ──
      final assistantIdStr = await db.getSetting('logged_in_assistant_id');
      final sessionToken = await db.getSetting('assistant_session_token');
      final sessionExpiryStr = await db.getSetting('assistant_session_expiry');

      if (assistantIdStr != null && sessionToken != null && sessionExpiryStr != null) {
        final sessionExpiry = DateTime.tryParse(sessionExpiryStr);
        if (sessionExpiry != null && DateTime.now().isBefore(sessionExpiry)) {
          final assistantId = int.tryParse(assistantIdStr);
          if (assistantId != null) {
            final localDb = await db.database;
            final result = await localDb.query('assistants', where: 'id = ?', whereArgs: [assistantId]);
            if (result.isNotEmpty) {
              final assistant = Assistant.fromMap(result.first);
              if (assistant.isActive && !assistant.isSubscriptionExpired) {
                // Auto login session matches and is valid!
                ctx.read<CurrentUserProvider>().loginAsAssistant(assistant);
                SyncService.instance.startPeriodicSync();
                ScheduledSyncService.registerDevice();
                Navigator.pushReplacement(
                  ctx,
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                );
                return;
              }
            }
          }
        }
      }

      // If no valid session, redirect to the password/PIN entry screen
      Navigator.pushReplacement(
        ctx,
        MaterialPageRoute(builder: (_) => const AssistantPinLoginScreen()),
      );
      return;
    }

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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 200,
                  height: 200,
                ),
                const SizedBox(height: 30),
                const SizedBox(
                  width: 40,
                  child: LinearProgressIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.darkBorder,
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
    (icon: Icons.medical_services_outlined, label: 'النواقص'),
    (icon: Icons.people_outline_rounded, label: 'المندوبون'),
    (icon: Icons.account_balance_wallet_outlined, label: 'الديون'),
    (icon: Icons.bar_chart_rounded, label: 'التقارير'),
    (icon: Icons.settings_outlined, label: 'الإعدادات'),
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
    return SubscriptionGuard(
      child: Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          backgroundColor: AppColors.darkCard,
          title: Row(
            children: [
              const PharmacyLogo(size: 24),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'صيدلي',
                        style: TextStyle(
                          color: AppColors.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.primary, width: 0.8),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _titles[_currentIndex],
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      height: 1.2,
                    ),
                  ),
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
    ),
  );
}

  /// قائمة خيارات المستخدم
  void _showUserMenu(CurrentUserProvider userProvider) async {
    final isAssistantDevice = await DatabaseHelper.instance.getSetting('is_assistant_device') == '1';
    if (!mounted) return;

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
            if (isAssistantDevice) ...[
              const SizedBox(height: 16),
              // تبديل المستخدم
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded,
                    color: AppColors.primary),
                title: const Text('تبديل المستخدم',
                    style: TextStyle(color: AppColors.textColor)),
                subtitle: const Text('الدخول بحساب مساعد آخر',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                tileColor: AppColors.dark,
                onTap: () async {
                  Navigator.pop(ctx);
                  userProvider.logout();
                  await DatabaseHelper.instance.clearAssistantSession();
                  SyncService.instance.stopSync();
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AssistantPinLoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                },
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
