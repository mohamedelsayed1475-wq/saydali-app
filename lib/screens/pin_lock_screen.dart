import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../utils/app_theme.dart';

class PinLockScreen extends StatefulWidget {
  final bool isSetup; // true = إنشاء PIN جديد, false = التحقق
  final VoidCallback onSuccess;
  const PinLockScreen({super.key, this.isSetup = false, required this.onSuccess});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();

  /// تحقق إذا كان PIN مفعل
  static Future<bool> isPinEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('app_pin_hash') != null;
  }

  /// حذف PIN
  static Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_pin_hash');
  }
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  String _error = '';
  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin + 'saydali_salt_2024');
    return sha256.convert(bytes).toString();
  }

  Future<void> _onPinComplete(String pin) async {
    final prefs = await SharedPreferences.getInstance();

    if (widget.isSetup) {
      // إنشاء PIN جديد
      if (!_isConfirming) {
        setState(() {
          _confirmPin = pin;
          _isConfirming = true;
          _pin = '';
          _error = '';
        });
        return;
      }
      // تأكيد PIN
      if (pin == _confirmPin) {
        await prefs.setString('app_pin_hash', _hashPin(pin));
        widget.onSuccess();
      } else {
        _shakeCtrl.forward(from: 0);
        setState(() {
          _pin = '';
          _isConfirming = false;
          _confirmPin = '';
          _error = 'الرقم غير متطابق! حاول مرة تانية';
        });
      }
    } else {
      // التحقق
      final saved = prefs.getString('app_pin_hash') ?? '';
      if (_hashPin(pin) == saved) {
        widget.onSuccess();
      } else {
        _shakeCtrl.forward(from: 0);
        setState(() {
          _pin = '';
          _error = 'رقم خاطئ! حاول تاني';
        });
      }
    }
  }

  void _onKey(String key) {
    if (key == 'delete') {
      if (_pin.isNotEmpty) {
        setState(() {
          _pin = _pin.substring(0, _pin.length - 1);
          _error = '';
        });
      }
      return;
    }
    if (_pin.length < 4) {
      final newPin = _pin + key;
      setState(() {
        _pin = newPin;
        _error = '';
      });
      if (newPin.length == 4) {
        Future.delayed(const Duration(milliseconds: 200), () {
          _onPinComplete(newPin);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // أيقونة القفل
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.45),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.lock_rounded, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.isSetup
                  ? (_isConfirming ? 'أعد إدخال الرقم للتأكيد' : 'أنشئ رقم سري من 4 أرقام')
                  : 'أدخل الرقم السري',
              style: const TextStyle(
                color: AppColors.textColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'صيدلي PRO',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 30),

            // نقاط PIN
            AnimatedBuilder(
              animation: _shakeCtrl,
              builder: (_, child) {
                final offset = _shakeCtrl.isAnimating
                    ? (10 * (0.5 - _shakeCtrl.value) * 2)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: filled ? 18 : 14,
                    height: filled ? 18 : 14,
                    decoration: BoxDecoration(
                      color: filled ? AppColors.primary : Colors.transparent,
                      border: Border.all(
                        color: _error.isNotEmpty
                            ? AppColors.danger
                            : AppColors.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: filled
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
            ),

            // رسالة خطأ
            const SizedBox(height: 16),
            SizedBox(
              height: 20,
              child: _error.isNotEmpty
                  ? Text(_error,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 13))
                  : null,
            ),
            const Spacer(),

            // لوحة الأرقام
            _buildKeypad(),
            const SizedBox(height: 20),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'delete'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50),
      child: Column(
        children: keys.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) return const SizedBox(width: 70, height: 70);
              return _KeyButton(
                label: key,
                onTap: () => _onKey(key),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _KeyButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDelete = label == 'delete';
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(35),
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 8,
              ),
            ],
          ),
          child: Center(
            child: isDelete
                ? const Icon(Icons.backspace_outlined,
                    color: AppColors.textMuted, size: 22)
                : Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
