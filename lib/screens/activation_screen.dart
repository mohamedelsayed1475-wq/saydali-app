import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../utils/app_theme.dart';
import '../database/database_helper.dart';
import '../utils/activation_codes.dart';
import 'cloud_setup_screen.dart';
import 'assistant_pin_login_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasInput = false;

  // subtle entrance animation
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();

    _codeController.addListener(() {
      setState(() => _hasInput = _codeController.text.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── التحقق من الكود ────────────────────────────────────────────────────────

  Future<void> _handleActivation() async {
    final rawCode = _codeController.text.replaceAll('-', '').trim();
    if (rawCode.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كود التفعيل أولاً');
      return;
    }
    final enteredCode = _codeController.text.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // محاولة التحقق أونلاين أولاً
      final response = await http
          .get(Uri.parse(
              'https://raw.githubusercontent.com/mohamedelsayed1475-wq/saydali-app/main/activation_codes.txt'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final codes = response.body
            .split('\n')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();

        if (codes.contains(enteredCode) || kActivationCodes.contains(enteredCode)) {
          await _completeActivation(enteredCode);
        } else {
          setState(() => _errorMessage = 'كود التفعيل غير صالح. يرجى التأكد من الكود والمحاولة مجدداً.');
        }
      } else {
        // fallback: فحص محلي
        if (kActivationCodes.contains(enteredCode)) {
          await _completeActivation(enteredCode);
        } else {
          setState(() => _errorMessage = 'تعذّر الاتصال بالخادم (${response.statusCode}). يرجى المحاولة لاحقاً.');
        }
      }
    } catch (_) {
      // offline fallback
      if (kActivationCodes.contains(enteredCode)) {
        await _completeActivation(enteredCode);
      } else {
        setState(() => _errorMessage = 'خطأ في الاتصال بالإنترنت. يرجى التأكد من اتصالك والمحاولة مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeActivation(String code) async {
    await DatabaseHelper.instance.setSetting('is_activated', '1');
    await DatabaseHelper.instance.setSetting('activation_code', code);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 تم تفعيل التطبيق بنجاح!'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CloudSetupScreen()),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12151e),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Logo + PRO badge ─────────────────────────────────────
                    _buildLogo(),
                    const SizedBox(height: 32),

                    // ── Title ────────────────────────────────────────────────
                    const Text(
                      'تفعيل التطبيق',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل كود التفعيل للمتابعة',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // ── Code Input ───────────────────────────────────────────
                    _buildCodeField(),
                    const SizedBox(height: 14),

                    // ── Error message ────────────────────────────────────────
                    if (_errorMessage != null) ...[
                      _buildError(),
                      const SizedBox(height: 14),
                    ],

                    // ── Activate Button ──────────────────────────────────────
                    _buildActivateButton(),
                    const SizedBox(height: 16),

                    // ── Hint ─────────────────────────────────────────────────
                    const Text(
                      'كود التفعيل متاح عند الشراء من المطور',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),

                    // ── Divider ──────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Divider(color: Colors.white.withOpacity(0.08)),
                    ),

                    // ── Assistant login ──────────────────────────────────────
                    _buildAssistantButton(),
                    const SizedBox(height: 40),

                    // ── Contact link ─────────────────────────────────────────
                    _buildContactRow(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Glow ring
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withOpacity(0.25),
                  blurRadius: 32,
                  spreadRadius: 8),
            ],
          ),
        ),
        // Icon container
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF1DB97A), Color(0xFF00C896)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 2),
          ),
          child: const Icon(Icons.local_pharmacy_rounded,
              size: 42, color: Colors.white),
        ),
        // PRO badge
        Positioned(
          bottom: -4,
          right: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB800), Color(0xFFFF7A00)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.orange.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: const Text(
              'PRO',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: _hasInput
            ? [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4))
              ]
            : [],
      ),
      child: TextField(
        controller: _codeController,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        keyboardType: TextInputType.text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 6,
        ),
        decoration: InputDecoration(
          hintText: 'XXXX-XXXX-XXXX-XXXX',
          hintStyle: TextStyle(
            color: AppColors.textMuted.withOpacity(0.5),
            fontSize: 16,
            letterSpacing: 4,
            fontWeight: FontWeight.normal,
          ),
          filled: true,
          fillColor: const Color(0xFF1C2130),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.danger),
          ),
          suffixIcon: _hasInput
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded,
                      color: AppColors.textMuted, size: 18),
                  onPressed: () {
                    _codeController.clear();
                    setState(() => _errorMessage = null);
                  },
                )
              : null,
        ),
        inputFormatters: [
          TextInputFormatter.withFunction((oldVal, newVal) {
            String clean =
                newVal.text.replaceAll('-', '').toUpperCase();
            String formatted = '';
            for (int i = 0; i < clean.length && i < 16; i++) {
              if (i > 0 && i % 4 == 0) formatted += '-';
              formatted += clean[i];
            }
            return TextEditingValue(
              text: formatted,
              selection:
                  TextSelection.collapsed(offset: formatted.length),
            );
          }),
        ],
        onSubmitted: (_) => _handleActivation(),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                  color: AppColors.danger, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleActivation,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1DB97A),
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          shadowColor: AppColors.primary.withOpacity(0.4),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.vpn_key_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'تفعيل',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAssistantButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AssistantPinLoginScreen()),
        ),
        icon: const Icon(Icons.badge_rounded, size: 18),
        label: const Text('هل أنت مساعد صيدلي؟'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          side: BorderSide(color: Colors.white.withOpacity(0.12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildContactRow() {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.darkCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'الحصول على كود التفعيل',
            textAlign: TextAlign.right,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'للحصول على كود تفعيل يرجى التواصل مع المطور عبر تليجرام:\n\n@Mohamed07Elsayed',
            textDirection: TextDirection.rtl,
            style: TextStyle(color: AppColors.textLight, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
      child: RichText(
        text: const TextSpan(
          style: TextStyle(fontSize: 13),
          children: [
            TextSpan(
                text: 'كيف أحصل على الكود؟ ',
                style: TextStyle(color: AppColors.textMuted)),
            TextSpan(
              text: 'تواصل مع المطور',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
