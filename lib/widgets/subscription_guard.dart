import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../providers/current_user_provider.dart';
import '../services/sync_service.dart';
import '../screens/assistant_pin_login_screen.dart';

class SubscriptionGuard extends StatefulWidget {
  final Widget child;
  const SubscriptionGuard({super.key, required this.child});

  @override
  State<SubscriptionGuard> createState() => _SubscriptionGuardState();
}

class _SubscriptionGuardState extends State<SubscriptionGuard> {
  Timer? _timer;
  StreamSubscription? _syncSubscription;
  bool _isLocking = false;

  @override
  void initState() {
    super.initState();
    // Check every 15 seconds
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _checkSubscription());
    // Also check on sync complete
    _syncSubscription = SyncService.instance.onSyncComplete.listen((_) => _checkSubscription());
    
    // Initial immediate check after build frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSubscription());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkSubscription() async {
    if (_isLocking || !mounted) return;

    final userProvider = context.read<CurrentUserProvider>();
    if (userProvider.isOwner || userProvider.currentUser == null) {
      return; // Only guard assistants
    }

    final assistant = userProvider.currentUser!;
    final assistantId = assistant.id;
    if (assistantId == null) return;

    try {
      final db = DatabaseHelper.instance;
      final localDb = await db.database;
      final results = await localDb.query(
        'assistants',
        where: 'id = ?',
        whereArgs: [assistantId],
      );

      bool shouldLock = false;
      String lockMessage = 'انتهى اشتراكك، يرجى التواصل مع الصيدلية لتجديد التفعيل';

      if (results.isEmpty) {
        // Assistant was deleted
        shouldLock = true;
        lockMessage = 'تم حذف حساب المساعد الخاص بك من قبل الصيدلية';
      } else {
        final currentData = Assistant.fromMap(results.first);
        if (!currentData.isActive) {
          // Assistant was deactivated
          shouldLock = true;
          lockMessage = 'تم إيقاف تفعيل حساب المساعد الخاص بك';
        } else if (currentData.isSubscriptionExpired) {
          // Assistant subscription expired
          shouldLock = true;
          lockMessage = 'انتهى اشتراكك، يرجى التواصل مع الصيدلية لتجديد التفعيل';
        }
      }

      if (shouldLock) {
        _isLocking = true;
        _timer?.cancel();
        _syncSubscription?.cancel();

        // Perform clean logout
        userProvider.logout();
        await db.clearAssistantSession();
        SyncService.instance.stopSync();

        if (!mounted) return;

        // Redirect to Login Screen and display premium warning dialog
        await Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => AssistantPinLoginScreen(
              initialErrorMessage: lockMessage,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error checking subscription guard: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
