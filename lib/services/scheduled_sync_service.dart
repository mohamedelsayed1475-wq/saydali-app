import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import '../utils/env_config.dart';
import 'sync_service.dart';

/// اسم المهمة الأساسية للمزامنة في الخلفية
const String kSyncTaskName = 'com.saydali.scheduledSync';
const String kSyncTaskUniqueName = 'saydaliScheduledSync';
const String kCleanupTaskName = 'com.saydali.cleanupSync';

/// Callback عالمي — لازم يكون top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('🔄 [Background] تشغيل مهمة: $task');

      // تهيئة قاعدة البيانات
      await DatabaseHelper.instance.database;

      if (task == kSyncTaskName || task == Workmanager.iOSBackgroundTask) {
        // مزامنة كاملة (رفع + سحب)
        await SyncService.instance.registerPharmacy();
        await SyncService.instance.syncAll();

        // تأكيد المزامنة
        final deviceId = await _getDeviceId();
        await _confirmDeviceSync(deviceId);

        // محاولة تنظيف لو كل الأجهزة سحبت
        await _tryCleanupCloud();

        debugPrint('✅ [Background] المزامنة تمت بنجاح');
      } else if (task == kCleanupTaskName) {
        await _tryCleanupCloud();
      }

      return true;
    } catch (e) {
      debugPrint('❌ [Background] خطأ: $e');
      return false;
    }
  });
}

/// جلب device ID محلي
Future<String> _getDeviceId() async {
  var id = await DatabaseHelper.instance.getSetting('device_id');
  if (id == null || id.isEmpty) {
    id = 'dev_${DateTime.now().millisecondsSinceEpoch}';
    await DatabaseHelper.instance.setSetting('device_id', id);
  }
  return id;
}

/// تأكيد إن الجهاز سحب البيانات
Future<void> _confirmDeviceSync(String deviceId) async {
  final pharmacyId = await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
  if (pharmacyId == null) return;

  final url = '${EnvConfig.supabaseUrl}/sync_confirmations';
  final headers = {
    'apikey': EnvConfig.supabaseKey,
    'Authorization': 'Bearer ${EnvConfig.supabaseKey}',
    'Content-Type': 'application/json',
    'Prefer': 'return=minimal',
  };

  try {
    await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({
        'pharmacy_id': pharmacyId,
        'device_id': deviceId,
        'sync_batch_id': DateTime.now().toIso8601String().substring(0, 13), // ساعة واحدة
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      }),
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('⚠️ تأكيد المزامنة فشل: $e');
  }
}

/// تنظيف البيانات من السحابة بعد ما كل الأجهزة سحبت
Future<void> _tryCleanupCloud() async {
  final pharmacyId = await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
  if (pharmacyId == null) return;

  final headers = {
    'apikey': EnvConfig.supabaseKey,
    'Authorization': 'Bearer ${EnvConfig.supabaseKey}',
    'Content-Type': 'application/json',
  };

  try {
    // عدد الأجهزة المسجلة
    final devicesRes = await http.get(
      Uri.parse('${EnvConfig.supabaseUrl}/sync_devices?pharmacy_id=eq.$pharmacyId&select=device_id'),
      headers: headers,
    ).timeout(const Duration(seconds: 8));

    if (devicesRes.statusCode != 200) return;
    final devices = jsonDecode(devicesRes.body) as List;
    if (devices.isEmpty) return;
    final totalDevices = devices.length;

    // عدد التأكيدات لآخر batch
    final batchId = DateTime.now().toIso8601String().substring(0, 13);
    final confirmRes = await http.get(
      Uri.parse(
        '${EnvConfig.supabaseUrl}/sync_confirmations?pharmacy_id=eq.$pharmacyId&sync_batch_id=eq.$batchId&select=device_id',
      ),
      headers: headers,
    ).timeout(const Duration(seconds: 8));

    if (confirmRes.statusCode != 200) return;
    final confirmations = jsonDecode(confirmRes.body) as List;

    // لو كل الأجهزة سحبت → امسح البيانات
    if (confirmations.length >= totalDevices) {
      debugPrint('🗑️ كل الأجهزة سحبت! بنمسح البيانات المؤقتة...');

      // مسح البيانات من السحابة (نواقص + عملاء + ديون + فواتير)
      final tables = [
        'cloud_shortages',
        'cloud_customers',
        'cloud_debt_transactions',
        'cloud_invoices',
      ];

      for (final table in tables) {
        try {
          await http.delete(
            Uri.parse('${EnvConfig.supabaseUrl}/$table?pharmacy_id=eq.$pharmacyId'),
            headers: {...headers, 'Prefer': 'return=minimal'},
          ).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }

      // مسح صور العملاء والإيصالات من Storage
      // (الصور بتتخزن مؤقتاً، وكل جهاز بينزلها محلياً)
      // ملاحظة: مسح الـ Storage objects محتاج endpoint مختلف

      // مسح التأكيدات القديمة
      await http.delete(
        Uri.parse('${EnvConfig.supabaseUrl}/sync_confirmations?pharmacy_id=eq.$pharmacyId&sync_batch_id=eq.$batchId'),
        headers: {...headers, 'Prefer': 'return=minimal'},
      ).timeout(const Duration(seconds: 5));

      debugPrint('✅ تم تنظيف السحابة بنجاح!');
    } else {
      debugPrint('⏳ ${confirmations.length}/$totalDevices أجهزة سحبت، مستنيين الباقي...');
    }
  } catch (e) {
    debugPrint('⚠️ تنظيف السحابة فشل: $e');
  }
}

// ══════════════════════════════════════════════════════════════
// الخدمة الرئيسية — ScheduledSyncService
// ══════════════════════════════════════════════════════════════

class ScheduledSyncService {
  static final ScheduledSyncService instance = ScheduledSyncService._();
  ScheduledSyncService._();

  /// تهيئة WorkManager
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    debugPrint('✅ WorkManager initialized');
  }

  /// حفظ مواعيد المزامنة (من 1 لـ 7)
  static Future<void> setScheduleTimes(List<TimeOfDay> times) async {
    final encoded = times.map((t) => '${t.hour}:${t.minute}').join(',');
    await DatabaseHelper.instance.setSetting('sync_schedule_times', encoded);
    // إعادة جدولة المهام
    await _scheduleAllTasks(times);
  }

  /// جلب المواعيد المحفوظة
  static Future<List<TimeOfDay>> getScheduleTimes() async {
    final raw = await DatabaseHelper.instance.getSetting('sync_schedule_times');
    if (raw == null || raw.isEmpty) return [];
    return raw.split(',').map((s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }).toList();
  }

  /// تسجيل الجهاز في السحابة
  static Future<void> registerDevice() async {
    final pharmacyId = await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
    if (pharmacyId == null) return;

    final deviceId = await _getDeviceId();
    final headers = {
      'apikey': EnvConfig.supabaseKey,
      'Authorization': 'Bearer ${EnvConfig.supabaseKey}',
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal',
    };

    try {
      // تحقق هل الجهاز مسجل
      final checkRes = await http.get(
        Uri.parse(
          '${EnvConfig.supabaseUrl}/sync_devices?pharmacy_id=eq.$pharmacyId&device_id=eq.$deviceId&select=id',
        ),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (checkRes.statusCode == 200) {
        final existing = jsonDecode(checkRes.body) as List;
        if (existing.isNotEmpty) {
          // تحديث آخر مزامنة
          await http.patch(
            Uri.parse(
              '${EnvConfig.supabaseUrl}/sync_devices?pharmacy_id=eq.$pharmacyId&device_id=eq.$deviceId',
            ),
            headers: headers,
            body: jsonEncode({'last_synced_at': DateTime.now().toUtc().toIso8601String()}),
          );
          return;
        }
      }

      // تسجيل جهاز جديد
      await http.post(
        Uri.parse('${EnvConfig.supabaseUrl}/sync_devices'),
        headers: headers,
        body: jsonEncode({
          'pharmacy_id': pharmacyId,
          'device_id': deviceId,
          'device_name': 'جهاز ${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        }),
      ).timeout(const Duration(seconds: 8));

      debugPrint('✅ تم تسجيل الجهاز: $deviceId');
    } catch (e) {
      debugPrint('⚠️ فشل تسجيل الجهاز: $e');
    }
  }

  /// جدولة كل المهام بناءً على المواعيد
  static Future<void> _scheduleAllTasks(List<TimeOfDay> times) async {
    // إلغاء كل المهام السابقة
    await Workmanager().cancelAll();

    for (int i = 0; i < times.length; i++) {
      final delay = _calculateDelay(times[i]);
      await Workmanager().registerOneOffTask(
        '${kSyncTaskUniqueName}_$i',
        kSyncTaskName,
        initialDelay: delay,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 5),
        tag: 'saydali_sync',
      );
      debugPrint('📅 مهمة $i مجدولة بعد ${delay.inMinutes} دقيقة (${times[i].hour}:${times[i].minute.toString().padLeft(2, '0')})');
    }

    // جدولة مهمة متكررة احتياطية (كل 15 دقيقة — الحد الأدنى لـ WorkManager)
    // تعمل كـ fallback لو المهام المحددة مشتغلتش
    await Workmanager().registerPeriodicTask(
      kSyncTaskUniqueName,
      kSyncTaskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      tag: 'saydali_sync_periodic',
    );
  }

  /// حساب المدة لحد الموعد الجاي
  static Duration _calculateDelay(TimeOfDay time) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, time.hour, time.minute);

    // لو الموعد فات النهاردة، اجدوله بكرة
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled.difference(now);
  }

  /// مزامنة فورية يدوية (من زر في الإعدادات)
  static Future<void> syncNow() async {
    await SyncService.instance.registerPharmacy();
    await SyncService.instance.syncAll();
    final deviceId = await _getDeviceId();
    await _confirmDeviceSync(deviceId);
    await _tryCleanupCloud();
  }

  /// إيقاف كل المهام
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
    debugPrint('⏹️ تم إلغاء كل مهام المزامنة');
  }
}
