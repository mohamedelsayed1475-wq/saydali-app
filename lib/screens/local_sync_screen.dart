import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/app_theme.dart';
import '../providers/current_user_provider.dart';
import '../services/local_sync_service.dart';
import '../database/database_helper.dart';
import 'scanner_screen.dart';

class LocalSyncScreen extends StatefulWidget {
  const LocalSyncScreen({super.key});

  @override
  State<LocalSyncScreen> createState() => _LocalSyncScreenState();
}

class _LocalSyncScreenState extends State<LocalSyncScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _ipController = TextEditingController();
  
  bool _isLoading = false;
  String? _syncError;
  bool _syncSuccess = false;
  String _lastLocalSyncTime = 'لم تتم المزامنة بعد';

  @override
  void initState() {
    super.initState();
    final userProvider = Provider.of<CurrentUserProvider>(context, listen: false);
    // إذا كان المالك، يفتح على تبويب الخادم (الرئيسي)، وإذا كان مساعد يفتح على تبويب العميل
    _tabController = TabController(
      length: 2, 
      vsync: this, 
      initialIndex: userProvider.isOwner ? 0 : 1
    );

    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = DatabaseHelper.instance;
    final lastTime = await db.getSetting('last_local_sync_at');
    final savedIp = await db.getSetting('last_saved_server_ip');
    
    if (mounted) {
      setState(() {
        if (lastTime != null && lastTime.isNotEmpty) {
          final dt = DateTime.tryParse(lastTime);
          if (dt != null) {
            _lastLocalSyncTime = '${dt.hour}:${dt.minute.toString().padLeft(2, '0')} - ${dt.day}/${dt.month}/${dt.year}';
          } else {
            _lastLocalSyncTime = lastTime;
          }
        }
        if (savedIp != null) {
          _ipController.text = savedIp;
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  /// فتح الكاميرا لمسح كود QR
  Future<void> _scanQRCode() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final String? scannedValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );

    if (scannedValue != null && scannedValue.isNotEmpty && mounted) {
      setState(() {
        _ipController.text = scannedValue;
        _syncError = null;
        _syncSuccess = false;
      });
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('تم قراءة عنوان IP الخادم: $scannedValue', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  /// بدء المزامنة كجهاز عميل (مساعد)
  Future<void> _startSync() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _syncError = 'يرجى إدخال عنوان IP للجهاز الرئيسي أولاً أو مسح كود الـ QR الخاص به.';
        _syncSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _syncError = null;
      _syncSuccess = false;
    });

    // حفظ الـ IP لاستخدامه لاحقاً تسهيلاً للمستخدم
    await DatabaseHelper.instance.setSetting('last_saved_server_ip', ip);

    final result = await LocalSyncService.instance.performSync(ip);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.success) {
          _syncSuccess = true;
          _loadSettings(); // تحديث تاريخ آخر مزامنة
        } else {
          _syncError = result.error ?? 'فشلت المزامنة المحلية لسبب غير معروف.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncService = LocalSyncService.instance;

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        backgroundColor: AppColors.darkCard,
        elevation: 0,
        title: const Text(
          'المزامنة المحلية (Wi-Fi)',
          style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
          tabs: const [
            Tab(text: 'استقبال البيانات (الجهاز الرئيسي 👑)'),
            Tab(text: 'إرسال ومزامنة (الأجهزة المساعدة 👤)'),
          ],
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: TabBarView(
          controller: _tabController,
          children: [
            // ─── تبويب الخادم (المالك / الرئيسي) ───
            _buildHostTab(syncService),
            
            // ─── تبويب العميل (المساعد) ───
            _buildClientTab(),
          ],
        ),
      ),
    );
  }

  /// بناء واجهة تبويب خادم المزامنة المحلية (الجهاز الرئيسي)
  Widget _buildHostTab(LocalSyncService syncService) {
    return StreamBuilder<bool>(
      stream: syncService.onServerStateChanged,
      initialData: syncService.isServerRunning,
      builder: (context, snapshot) {
        final isRunning = snapshot.data ?? false;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // حالة الخادم
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isRunning ? AppColors.primary.withValues(alpha: 0.3) : AppColors.darkBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isRunning ? AppColors.primary : Colors.grey,
                        shape: BoxShape.circle,
                        boxShadow: isRunning ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.6),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ] : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isRunning ? 'استقبال الاتصالات نشط' : 'استقبال الاتصالات متوقف',
                            style: const TextStyle(
                              color: AppColors.textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          Text(
                            isRunning 
                                ? 'يمكن للأجهزة المساعدة المزامنة معك الآن.' 
                                : 'قم بتفعيل الخدمة ليتمكن المساعدون من الاتصال بجهازك.',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isRunning,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) async {
                        if (val) {
                          final success = await syncService.startServer();
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('فشل تشغيل الخادم، تأكد من اتصالك بالـ Wi-Fi أو نقطة الاتصال.', style: TextStyle(fontFamily: 'Cairo')),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        } else {
                          await syncService.stopServer();
                        }
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              if (isRunning && syncService.serverIpAddress != null) ...[
                // معلومات الاتصال وكود الـ QR
                Card(
                  color: AppColors.darkCard,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Text(
                          'مسح كود الاتصال السريع 📲',
                          style: TextStyle(
                            color: AppColors.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'اجعل الأجهزة المساعدة تفتح كاميرا المزامنة وتمسح هذا الكود للربط الفوري:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 24),
                        // توليد كود الـ QR لعنوان الـ IP
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data: syncService.serverIpAddress!,
                            version: QrVersions.auto,
                            size: 200.0,
                            gapless: false,
                            errorStateBuilder: (cxt, err) {
                              return const Center(child: Text('خطأ في توليد الكود ⚠️'));
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        // عرض عنوان الـ IP والمنفذ كتابة
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.dark.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('IP: ', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
                              SelectableText(
                                syncService.serverIpAddress!,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Text('المنفذ: ', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
                              Text(
                                '${syncService.port}',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // تنبيه
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.orangeAccent, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تأكد من بقاء هذه الشاشة مفتوحة وجهازك نشطاً أثناء قيام المساعدين بعملية المزامنة.',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontFamily: 'Cairo'),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // واجهة الخادم المغلق
                const SizedBox(height: 60),
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 100,
                  color: AppColors.darkBorder,
                ),
                const SizedBox(height: 16),
                const Text(
                  'استقبال البيانات مغلق حالياً',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'لتفعيل استقبال ومزامنة البيانات من أجهزة المساعدين، قم بتفعيل مفتاح "استقبال الاتصالات" بالأعلى.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// بناء واجهة تبويب عميل المزامنة المحلية (الأجهزة المساعدة)
  Widget _buildClientTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // كارت حالة آخر مزامنة
          Card(
            color: AppColors.darkCard,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sync_rounded, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'آخر مزامنة محلية:',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Cairo'),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _lastLocalSyncTime,
                          style: const TextStyle(
                            color: AppColors.textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          const Text(
            'الاتصال بالجهاز الرئيسي (المالك) 🖥️',
            style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          const Text(
            'تأكد من تفعيل "استقبال البيانات" على جهاز المالك، واتصال كلا الجهازين بنفس شبكة الـ Wi-Fi أو الـ Hotspot.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'Cairo'),
          ),
          
          const SizedBox(height: 16),
          
          // حقل إدخال IP مع زر مسح الكود
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  keyboardType: TextInputType.values[3], // text/number with dots
                  style: const TextStyle(color: Colors.white, letterSpacing: 1.0, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    hintText: 'مثال: 192.168.1.15',
                    labelText: 'عنوان IP لجهاز المالك',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: Icon(Icons.laptop_windows_rounded, color: AppColors.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _isLoading ? null : _scanQRCode,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 28),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 30),
          
          // حالات النجاح والفشل
          if (_syncSuccess) ...[
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'تمت المزامنة بنجاح! تم نقل البيانات وتحديث التطبيق محلياً.',
                      style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (_syncError != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _syncError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // زر المزامنة
          ElevatedButton(
            onPressed: _isLoading ? null : _startSync,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primary,
            ),
            child: _isLoading 
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.sync_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'بدء المزامنة الفورية الآن',
                        style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 15),
                      ),
                    ],
                  ),
          ),
          
          const SizedBox(height: 24),
          
          // خطوات المساعدة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 كيف أقوم بالمزامنة؟',
                  style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo'),
                ),
                SizedBox(height: 12),
                _StepItem(number: '1', text: 'افتح شاشة المزامنة على جهاز المالك (الرئيسي).'),
                _StepItem(number: '2', text: 'شغّل خيار "استقبال الاتصالات" على جهاز المالك.'),
                _StepItem(number: '3', text: 'اضغط على زر الكاميرا الأخضر على هذا الجهاز وامسح كود الـ QR المعروض على شاشة المالك (أو اكتب الـ IP يدوياً).'),
                _StepItem(number: '4', text: 'اضغط على "بدء المزامنة الفورية الآن".'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// عنصر خطوة شرح المزامنة
class _StepItem extends StatelessWidget {
  final String number;
  final String text;

  const _StepItem({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textLight, fontSize: 12, fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
  }
}
