import 'package:flutter/material.dart';
import 'reps_screen.dart';

/// الشاشة المتوافقة مع الإصدارات السابقة (Backwards Compatible Wrapper)
/// تقوم بالتوجيه مباشرة إلى تاب "ردود المندوبين" داخل الشاشة الموحدة `RepsScreen`
class RepResponseScreen extends StatelessWidget {
  final String? initialCode;

  const RepResponseScreen({super.key, this.initialCode});

  @override
  Widget build(BuildContext context) {
    return RepsScreen(
      initialTab: 1,
      initialCode: initialCode,
    );
  }
}
