import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../providers/current_user_provider.dart';
import '../utils/app_theme.dart';

/// شاشة اختيار المستخدم (المالك أو المساعد)
/// تظهر بعد شاشة PIN أو مباشرة عند الدخول
class UserSelectionScreen extends StatefulWidget {
  final VoidCallback onOwnerSelected;
  final VoidCallback onAssistantSelected;

  const UserSelectionScreen({
    super.key,
    required this.onOwnerSelected,
    required this.onAssistantSelected,
  });

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen>
    with SingleTickerProviderStateMixin {
  List<Assistant> _assistants = [];
  bool _loading = true;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _animCtrl.forward();
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await DatabaseHelper.instance.getAssistants();
    if (mounted) {
      setState(() {
        _assistants = data
            .map(Assistant.fromMap)
            .where((a) => a.isActive)
            .toList();
        _loading = false;
      });
    }
  }

  void _loginAsOwner() {
    context.read<CurrentUserProvider>().loginAsOwner();
    // تسجيل نشاط دخول المالك
    DatabaseHelper.instance.logActivity(
      assistantName: 'المالك',
      action: 'تسجيل دخول',
      details: 'دخل المالك إلى التطبيق',
      screen: 'login',
    );
    widget.onOwnerSelected();
  }

  void _showAssistantPinDialog(Assistant assistant) {
    final pharmacyCodeCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String error = '';
    bool codeVerified = false; // خطوة 1: كود الصيدلية → خطوة 2: PIN

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.darkCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: codeVerified
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Center(
                    child: Text(assistant.name[0],
                        style: TextStyle(
                            color: codeVerified
                                ? AppColors.primary
                                : AppColors.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 18))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(assistant.name,
                        style: const TextStyle(
                            color: AppColors.textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    Text(
                        codeVerified
                            ? '2/2 أدخل رمز PIN'
                            : '1/2 أدخل كود الصيدلية',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // مؤشر الخطوات
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: codeVerified
                            ? AppColors.primary
                            : AppColors.darkBorder,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (!codeVerified) ...[
                // ── الخطوة 1: كود الصيدلية ──
                const Row(
                  children: [
                    Text('🔑', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 6),
                    Text('كود الصيدلية',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pharmacyCodeCtrl,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                      color: AppColors.textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6),
                  decoration: InputDecoration(
                    hintText: '• • • • • •',
                    hintStyle: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.5),
                        letterSpacing: 6),
                    counterText: '',
                    prefixIcon: const Icon(Icons.storefront_rounded,
                        color: Color(0xFFFFD700)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: error.isNotEmpty
                              ? AppColors.danger
                              : AppColors.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFFFFD700)),
                    ),
                  ),
                  onChanged: (val) {
                    if (error.isNotEmpty) setDlg(() => error = '');
                    if (val.length == 6) {
                      _verifyPharmacyCode(
                        val.toUpperCase(),
                        onSuccess: () =>
                            setDlg(() { codeVerified = true; error = ''; }),
                        onError: () {
                          setDlg(() => error = 'كود الصيدلية خاطئ!');
                          pharmacyCodeCtrl.clear();
                        },
                      );
                    }
                  },
                ),
              ] else ...[
                // ── الخطوة 2: رمز PIN ──
                const Row(
                  children: [
                    Text('🔐', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 6),
                    Text('رمز PIN الشخصي',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  style: const TextStyle(
                      color: AppColors.textColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 12),
                  decoration: InputDecoration(
                    hintText: '• • • •',
                    hintStyle: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.5),
                        letterSpacing: 8),
                    counterText: '',
                    prefixIcon: const Icon(Icons.lock_rounded,
                        color: AppColors.primary),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: error.isNotEmpty
                              ? AppColors.danger
                              : AppColors.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (val) {
                    if (error.isNotEmpty) setDlg(() => error = '');
                    if (val.length == 4) {
                      if (val == assistant.pin) {
                        Navigator.pop(ctx);
                        _loginAsAssistant(assistant);
                      } else {
                        setDlg(() => error = 'رمز PIN خاطئ!');
                        pinCtrl.clear();
                      }
                    }
                  },
                ),
              ],

              if (error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(error,
                    style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (codeVerified) {
                  // رجوع لخطوة الكود
                  setDlg(() {
                    codeVerified = false;
                    error = '';
                    pinCtrl.clear();
                  });
                } else {
                  Navigator.pop(ctx);
                }
              },
              child: Text(codeVerified ? 'رجوع' : 'إلغاء',
                  style: const TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                if (!codeVerified) {
                  _verifyPharmacyCode(
                    pharmacyCodeCtrl.text.toUpperCase(),
                    onSuccess: () =>
                        setDlg(() { codeVerified = true; error = ''; }),
                    onError: () {
                      setDlg(() => error = 'كود الصيدلية خاطئ!');
                      pharmacyCodeCtrl.clear();
                    },
                  );
                } else {
                  if (pinCtrl.text == assistant.pin) {
                    Navigator.pop(ctx);
                    _loginAsAssistant(assistant);
                  } else {
                    setDlg(() => error = 'رمز PIN خاطئ!');
                    pinCtrl.clear();
                  }
                }
              },
              child: Text(codeVerified ? 'دخول' : 'التالي'),
            ),
          ],
        ),
      ),
    );
  }

  /// التحقق من كود الصيدلية
  Future<void> _verifyPharmacyCode(String code,
      {required VoidCallback onSuccess,
      required VoidCallback onError}) async {
    final saved =
        await DatabaseHelper.instance.getSetting('pharmacy_code');
    if (saved != null && code == saved) {
      onSuccess();
    } else {
      onError();
    }
  }

  void _loginAsAssistant(Assistant assistant) {
    context.read<CurrentUserProvider>().loginAsAssistant(assistant);
    // تسجيل نشاط دخول المساعد
    DatabaseHelper.instance.logActivity(
      assistantId: assistant.id,
      assistantName: assistant.name,
      action: 'تسجيل دخول',
      details: 'دخل المساعد: ${assistant.name}',
      screen: 'login',
    );
    widget.onAssistantSelected();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      // الشعار
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 2)
                          ],
                        ),
                        child: const Center(
                            child:
                                Text('💊', style: TextStyle(fontSize: 40))),
                      ),
                      const SizedBox(height: 16),
                      const Text('من يستخدم التطبيق؟',
                          style: TextStyle(
                              color: AppColors.textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('اختر حسابك للدخول',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 30),

                      // ── زر المالك ──
                      _userCard(
                        emoji: '👑',
                        name: 'المالك',
                        subtitle: 'صلاحيات كاملة',
                        color: const Color(0xFFFFD700),
                        gradient: const [
                          Color(0xFF1A0A2E),
                          Color(0xFF16213E)
                        ],
                        onTap: _loginAsOwner,
                      ),
                      const SizedBox(height: 12),

                      // ── عنوان المساعدين ──
                      if (_assistants.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Divider(
                                      color: AppColors.darkBorder)),
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 12),
                                child: Text('👥 المساعدون',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Expanded(
                                  child: Divider(
                                      color: AppColors.darkBorder)),
                            ],
                          ),
                        ),

                        // ── قائمة المساعدين ──
                        Expanded(
                          child: ListView.builder(
                            itemCount: _assistants.length,
                            itemBuilder: (ctx, i) {
                              final assistant = _assistants[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _userCard(
                                  emoji: '👤',
                                  name: assistant.name,
                                  subtitle: assistant.permissionsSummary,
                                  color: AppColors.accent,
                                  gradient: const [
                                    Color(0xFF0D1B2A),
                                    Color(0xFF1B2838)
                                  ],
                                  onTap: () =>
                                      _showAssistantPinDialog(assistant),
                                  avatarLetter: assistant.name[0],
                                ),
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        const Spacer(),
                        const Text('لا يوجد مساعدون مضافون',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13)),
                        const Text('يمكنك إضافتهم من الإعدادات',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                        const Spacer(),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _userCard({
    required String emoji,
    required String name,
    required String subtitle,
    required Color color,
    required List<Color> gradient,
    required VoidCallback onTap,
    String? avatarLetter,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: avatarLetter != null
                    ? Text(avatarLetter,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 22))
                    : Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: AppColors.textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: color.withValues(alpha: 0.6), size: 18),
          ],
        ),
      ),
    );
  }
}
