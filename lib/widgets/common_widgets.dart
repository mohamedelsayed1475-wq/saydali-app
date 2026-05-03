import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

// ── شارة الحالة ──────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final map = {
      'pending': (label: 'بانتظار رد', color: AppColors.warning, bg: const Color(0xFFFEF3C7)),
      'offered': (label: 'عرض موصول', color: const Color(0xFF2563EB), bg: const Color(0xFFDBEAFE)),
      'covered': (label: 'تمت التغطية', color: AppColors.primary, bg: AppColors.primaryLight),
      'stubborn': (label: 'مستعصي', color: AppColors.danger, bg: const Color(0xFFFEE2E2)),
    };
    final s = map[status] ?? (label: status, color: AppColors.textMuted, bg: AppColors.darkBorder);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(s.label, style: TextStyle(color: s.color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ── تقييم النجوم ──────────────────────────────────────────────────
class StarRating extends StatelessWidget {
  final int count;
  final double size;
  const StarRating({super.key, required this.count, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) => Icon(
        i < count ? Icons.star_rounded : Icons.star_outline_rounded,
        color: AppColors.warning,
        size: size,
      )),
    );
  }
}

// ── بطاقة إحصائية ──────────────────────────────────────────────────
class StatCard extends StatelessWidget {
  final String icon;
  final String value;
  final String label;
  final Color? valueColor;
  final String? sub;

  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0, right: 0,
              child: Text(icon, style: const TextStyle(fontSize: 28)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(value, style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800,
                  color: valueColor ?? AppColors.textColor,
                )),
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                if (sub != null) ...[
                  const SizedBox(height: 4),
                  Text(sub!, style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── شريط تقدم ──────────────────────────────────────────────────
class GradientProgressBar extends StatelessWidget {
  final double value; // 0.0 to 1.0
  final double height;

  const GradientProgressBar({super.key, required this.value, this.height = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.darkBorder,
        borderRadius: BorderRadius.circular(99),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerRight,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

// ── حقل نص مخصص ──────────────────────────────────────────────────
class AppTextField extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final int maxLines;
  final Widget? prefix;
  final Widget? suffix;
  final void Function(String)? onChanged;

  const AppTextField({
    super.key,
    required this.hint,
    this.controller,
    this.keyboardType,
    this.maxLines = 1,
    this.prefix,
    this.suffix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textColor),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
      ),
    );
  }
}

// ── زرار رئيسي ──────────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool isLoading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onTap,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        child: isLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Text(text),
                ],
              ),
      ),
    );
  }
}

// ── حوار تأكيد الحذف ──────────────────────────────────────────────────
Future<bool?> showDeleteDialog(BuildContext context, String itemName) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('تأكيد الحذف', style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700)),
      content: Text('هل تريد حذف "$itemName"؟', style: const TextStyle(color: AppColors.textLight)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
}

// ── Snackbar ──────────────────────────────────────────────────
void showSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
    backgroundColor: isError ? AppColors.danger : AppColors.primary,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.all(16),
  ));
}

// ── شاشة فارغة ──────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String? buttonText;
  final VoidCallback? onButton;

  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.buttonText,
    this.onButton,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textColor)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
            if (buttonText != null && onButton != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onButton, child: Text(buttonText!)),
            ],
          ],
        ),
      ),
    );
  }
}
