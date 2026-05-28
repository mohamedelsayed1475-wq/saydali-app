import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/env_config.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

/// خدمة المزامنة متعددة الأجهزة عبر Supabase
/// تعمل بنظام Local-First: حفظ محلي أولاً ثم رفع للسحابة
class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  static const _url = EnvConfig.supabaseUrl;
  static const _key = EnvConfig.supabaseKey;

  Timer? _syncTimer;
  bool _isSyncing = false;
  String? _pharmacyCloudId; // UUID من Supabase

  WebSocket? _webSocket;
  Timer? _heartbeatTimer;
  bool _isConnectingRealtime = false;

  // بث انتهاء المزامنة لتحديث الواجهات تلقائياً
  final StreamController<void> _syncCompleteController = StreamController<void>.broadcast();
  Stream<void> get onSyncComplete => _syncCompleteController.stream;

  bool get isConfigured =>
      _url.isNotEmpty &&
      _key.isNotEmpty &&
      !_url.contains('REPLACE') &&
      !_key.contains('REPLACE');

  Map<String, String> get _headers {
    final h = <String, String>{
      'apikey': _key,
      'Authorization': 'Bearer $_key',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
    if (_pharmacyCloudId != null && _pharmacyCloudId!.isNotEmpty) {
      h['x-pharmacy-id'] = _pharmacyCloudId!;
    }
    return h;
  }

  // ══════════════════════════════════════════════════════════════
  // تسجيل الصيدلية (المالك فقط)
  // ══════════════════════════════════════════════════════════════

  /// تسجيل صيدلية جديدة في السحابة وربطها بالكود المحلي
  Future<bool> registerPharmacy() async {
    if (!isConfigured) return false;
    final db = DatabaseHelper.instance;

    // تحقق هل مسجل قبل كده
    final existingCloudId = await db.getSetting('pharmacy_cloud_id');
    if (existingCloudId != null && existingCloudId.isNotEmpty) {
      _pharmacyCloudId = existingCloudId;
      return true;
    }

    var pharmacyCode = await db.getSetting('pharmacy_code');
    if (pharmacyCode == null || pharmacyCode.isEmpty) {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rnd = Random.secure();
      pharmacyCode = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
      await db.setSetting('pharmacy_code', pharmacyCode);
      debugPrint('🆕 تم توليد كود صيدلية جديد: \$pharmacyCode');
    }
    
    final pharmacyName = await db.getSetting('pharmacy_name') ?? 'صيدليتي';

    try {
      // تحقق هل الكود مسجل بالفعل في السحابة
      final checkRes = await http
          .get(
            Uri.parse(
                '$_url/pharmacies?pharmacy_code=eq.$pharmacyCode&select=id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (checkRes.statusCode == 200) {
        final existing = jsonDecode(checkRes.body) as List;
        if (existing.isNotEmpty) {
          _pharmacyCloudId = existing[0]['id'];
          await db.setSetting('pharmacy_cloud_id', _pharmacyCloudId!);
          debugPrint('✅ الصيدلية مسجلة بالفعل: $_pharmacyCloudId');
          return true;
        }
      }

      // تسجيل جديد
      final res = await http
          .post(
            Uri.parse('$_url/pharmacies'),
            headers: _headers,
            body: jsonEncode({
              'pharmacy_code': pharmacyCode,
              'name': pharmacyName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 201 || res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final id = data is List ? data[0]['id'] : data['id'];
        _pharmacyCloudId = id;
        await db.setSetting('pharmacy_cloud_id', id);
        debugPrint('✅ تم تسجيل الصيدلية: $id');
        return true;
      }
      debugPrint('❌ فشل تسجيل الصيدلية: ${res.statusCode} ${res.body}');
      return false;
    } catch (e) {
      debugPrint('❌ registerPharmacy error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // انضمام مساعد من جهاز آخر
  // ══════════════════════════════════════════════════════════════

  /// المساعد يدخل كود الصيدلية → نجلب pharmacy_cloud_id + المساعدين
  Future<({bool success, String? error, List<Map<String, dynamic>> assistants})>
      joinPharmacy(String pharmacyCode) async {
    if (!isConfigured) {
      return (
        success: false,
        error: 'إعدادات الاتصال غير مكتملة',
        assistants: <Map<String, dynamic>>[]
      );
    }

    try {
      final res = await http
          .get(
            Uri.parse(
                '$_url/pharmacies?pharmacy_code=eq.${pharmacyCode.toUpperCase()}&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        return (
          success: false,
          error: 'خطأ في الاتصال (${res.statusCode})',
          assistants: <Map<String, dynamic>>[]
        );
      }

      final pharmacies = jsonDecode(res.body) as List;
      if (pharmacies.isEmpty) {
        return (
          success: false,
          error: 'كود الصيدلية غير موجود',
          assistants: <Map<String, dynamic>>[]
        );
      }

      final pharmacy = pharmacies[0];
      _pharmacyCloudId = pharmacy['id'];

      // حفظ بيانات الصيدلية محلياً
      final db = DatabaseHelper.instance;
      await db.setSetting('pharmacy_cloud_id', _pharmacyCloudId!);
      await db.setSetting('pharmacy_code', pharmacyCode.toUpperCase());
      await db.setSetting('pharmacy_name', pharmacy['name'] ?? 'صيدليتي');
      await db.setSetting('is_assistant_device', '1');

      // ══ جلب المساعدين من السحابة وحفظهم محلياً ══
      await pullAssistantsFromServer();

      // جلب المساعدين بعد التحديث
      final localAssistants = await db.getAssistants();
      return (success: true, error: null, assistants: localAssistants);
    } catch (e) {
      debugPrint('❌ joinPharmacy error: $e');
      return (
        success: false,
        error: 'خطأ في الاتصال: $e',
        assistants: <Map<String, dynamic>>[]
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // المزامنة الدورية
  // ══════════════════════════════════════════════════════════════

  /// بدء المزامنة المجدولة (الاحتياطية كل 30 ثانية) والمزامنة الفورية (WebSockets)
  void startPeriodicSync() {
    if (!isConfigured) {
      debugPrint('⚠️ المزامنة غير مفعلة - Supabase غير مُعدّ');
      return;
    }
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncAll();
    });
    _connectRealtime();
    debugPrint('🔄 بدء المزامنة الدورية الاحتياطية + الفورية عبر WebSockets');
  }

  /// إيقاف المزامنة
  void stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _disconnectRealtime();
    debugPrint('⏹️ إيقاف المزامنة');
  }

  /// الاتصال بـ Supabase Realtime WebSocket لتلقي التحديثات فوراً (مثل الواتساب)
  Future<void> _connectRealtime() async {
    if (_webSocket != null || _isConnectingRealtime || !isConfigured) return;
    _isConnectingRealtime = true;

    if (_pharmacyCloudId == null) {
      _pharmacyCloudId = await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
    }

    try {
      final uri = Uri.parse(_url);
      final wsProtocol = uri.scheme == 'https' ? 'wss' : 'ws';
      final wsUrl = '$wsProtocol://${uri.host}/realtime/v1/websocket?apikey=$_key&vsn=1.0.0';

      debugPrint('🔌 جاري الاتصال بـ Supabase Realtime: $wsUrl');
      _webSocket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 10));
      _isConnectingRealtime = false;
      debugPrint('⚡ تم الاتصال بـ Supabase Realtime بنجاح!');

      // إرسال رسالة الاشتراك في قناة التغييرات (postgres_changes) لجميع الجداول بالـ public schema
      final joinPayload = {
        "topic": "realtime:public",
        "event": "phx_join",
        "payload": {
          "config": {
            "postgres_changes": [
              {
                "event": "*",
                "schema": "public",
              }
            ]
          }
        },
        "ref": "1"
      };
      
      _webSocket!.add(jsonEncode(joinPayload));

      // إرسال heartbeat كل 30 ثانية للحفاظ على استقرار الاتصال ومنع إغلاقه
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (_webSocket != null) {
          _webSocket!.add(jsonEncode({
            "topic": "phoenix",
            "event": "heartbeat",
            "payload": {},
            "ref": "hb_${timer.tick}"
          }));
        }
      });

      // الاستماع للرسائل الواردة وتفعيل المزامنة عند رصد أي تحديث
      _webSocket!.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            final event = data['event'];
            final payload = data['payload'];

            if (event == 'postgres_changes') {
              final record = payload['record'] ?? payload['old_record'];
              if (record != null) {
                final recordPharmacyId = record['pharmacy_id']?.toString();
                // المزامنة فوراً إذا كان التغيير يخص الصيدلية الحالية، أو إذا كان مجهولاً (كما في الحذف)
                if (recordPharmacyId == null || recordPharmacyId == _pharmacyCloudId) {
                  debugPrint('🔔 تم رصد تغيير في قاعدة البيانات السحابية لجدول: ${payload['table']}! جاري المزامنة الفورية...');
                  syncAll();
                }
              }
            }
          } catch (e) {
            debugPrint('⚠️ خطأ في معالجة رسالة Realtime: $e');
          }
        },
        onError: (err) {
          debugPrint('❌ خطأ في اتصال Realtime: $err');
          _reconnectRealtime();
        },
        onDone: () {
          debugPrint('🔌 تم إغلاق اتصال Realtime');
          _reconnectRealtime();
        },
        cancelOnError: true,
      );

    } catch (e) {
      debugPrint('⚠️ فشل الاتصال بـ Realtime: $e');
      _isConnectingRealtime = false;
      _reconnectRealtime();
    }
  }

  /// قطع الاتصال بالـ Realtime
  void _disconnectRealtime() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _webSocket?.close();
    _webSocket = null;
    _isConnectingRealtime = false;
  }

  /// محاولة إعادة الاتصال التلقائي بعد 5 ثوانٍ
  void _reconnectRealtime() {
    _disconnectRealtime();
    Timer(const Duration(seconds: 5), () {
      if (_syncTimer != null) { // إذا كانت المزامنة ما زالت مفعلة بالتطبيق
        _connectRealtime();
      }
    });
  }

  /// مزامنة شاملة (رفع + سحب)
  Future<void> syncAll() async {
    if (_isSyncing || !isConfigured) return;

    final isAssistantDevice = await DatabaseHelper.instance.getSetting('is_assistant_device');
    if (isAssistantDevice == '1') {
      final assistantIdStr = await DatabaseHelper.instance.getSetting('logged_in_assistant_id');
      if (assistantIdStr != null && assistantIdStr.isNotEmpty) {
        final assistantId = int.tryParse(assistantIdStr);
        if (assistantId != null) {
          final db = await DatabaseHelper.instance.database;
          final result = await db.query('assistants', where: 'id = ?', whereArgs: [assistantId]);
          if (result.isNotEmpty) {
            final assistant = Assistant.fromMap(result.first);
            if (assistant.isSubscriptionExpired || !assistant.isActive) {
              debugPrint('🛑 Sync blocked: assistant is expired or inactive');
              await DatabaseHelper.instance.clearAssistantSession();
              stopSync();
              return;
            }
          } else {
            await DatabaseHelper.instance.clearAssistantSession();
            stopSync();
            return;
          }
        }
      } else {
        return;
      }
    }

    // تحميل pharmacy_cloud_id لو مش محمل
    if (_pharmacyCloudId == null) {
      _pharmacyCloudId =
          await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
      if (_pharmacyCloudId == null || _pharmacyCloudId!.isEmpty) return;
    }

    _isSyncing = true;
    try {
      await _pushShortages();
      await _pullShortages();
      await _pushCustomers();
      await _pullCustomers();
      await _pushDebtTransactions();
      await _pullDebtTransactions();
      await _pushInvoices();
      await _pullInvoices();
      await _syncAssistants();
      await _pullAssistants();
      await _pushMedicationExpiries();
      await _pullMedicationExpiries();

      // تحديث وقت آخر مزامنة
      await DatabaseHelper.instance.setSetting(
          'last_sync_at', DateTime.now().toIso8601String());

      // إرسال إشارة بنجاح المزامنة لتحديث الواجهات تلقائياً
      _syncCompleteController.add(null);
    } catch (e) {
      debugPrint('❌ syncAll error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// مزامنة كاملة أولية (عند أول دخول)
  Future<void> fullSync() async {
    if (!isConfigured || _pharmacyCloudId == null) return;
    debugPrint('🔄 بدء المزامنة الكاملة...');
    await syncAll();
    debugPrint('✅ تمت المزامنة الكاملة');
  }

  // ══════════════════════════════════════════════════════════════
  // مزامنة النواقص
  // ══════════════════════════════════════════════════════════════

  Future<void> _pushShortages() async {
    final db = await DatabaseHelper.instance.database;
    final unsynced = await db.query('shortages',
        where: 'is_synced = 0 OR is_synced IS NULL');

    for (final item in unsynced) {
      try {
        final cloudId = item['cloud_id']?.toString();
        final data = {
          'pharmacy_id': _pharmacyCloudId,
          'local_id': item['id'],
          'name': item['name'],
          'company': item['company'],
          'quantity': item['quantity'],
          'status': item['status'],
          'is_urgent': item['is_urgent'],
          'notes': item['notes'],
          'created_by': item['created_by'] ?? 'المالك',
          'created_at': item['created_at'],
          'updated_at': item['updated_at'],
        };

        http.Response res;
        if (cloudId != null && cloudId.isNotEmpty) {
          // تحديث
          res = await http
              .patch(
                Uri.parse('$_url/pharmacy_shortages?id=eq.$cloudId'),
                headers: _headers,
                body: jsonEncode(data),
              )
              .timeout(const Duration(seconds: 10));
        } else {
          // إنشاء جديد
          res = await http
              .post(
                Uri.parse('$_url/pharmacy_shortages'),
                headers: _headers,
                body: jsonEncode(data),
              )
              .timeout(const Duration(seconds: 10));
        }

        if (res.statusCode == 200 || res.statusCode == 201) {
          final resData = jsonDecode(res.body);
          final newCloudId =
              resData is List ? resData[0]['id'] : resData['id'];
          await db.update(
              'shortages', {'cloud_id': newCloudId, 'is_synced': 1},
              where: 'id = ?', whereArgs: [item['id']]);
        }
      } catch (e) {
        debugPrint('⚠️ push shortage error: $e');
      }
    }
  }

  Future<void> _pullShortages() async {
    final db = await DatabaseHelper.instance.database;
    final lastSync =
        await DatabaseHelper.instance.getSetting('last_sync_at') ?? '';

    try {
      String url =
          '$_url/pharmacy_shortages?pharmacy_id=eq.$_pharmacyCloudId&select=*';
      if (lastSync.isNotEmpty) {
        url += '&updated_at=gt.$lastSync';
      }

      final res = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;
      final items = jsonDecode(res.body) as List;

      for (final item in items) {
        final cloudId = item['id'];
        // تحقق هل موجود محلياً
        final local = await db.query('shortages',
            where: 'cloud_id = ?', whereArgs: [cloudId]);

        if (local.isEmpty) {
          // إضافة جديدة
          await db.insert('shortages', {
            'cloud_id': cloudId,
            'name': item['name'],
            'company': item['company'] ?? 'غير محدد',
            'quantity': item['quantity'] ?? 1,
            'status': item['status'] ?? 'pending',
            'is_urgent': item['is_urgent'] ?? 0,
            'notes': item['notes'],
            'created_by': item['created_by'],
            'created_at': item['created_at'],
            'updated_at': item['updated_at'],
            'is_synced': 1,
          });
        } else {
          // تحديث إذا السحابة أحدث
          final cloudUpdated = item['updated_at'] ?? '';
          final localUpdated = local.first['updated_at']?.toString() ?? '';
          if (cloudUpdated.compareTo(localUpdated) > 0) {
            await db.update(
                'shortages',
                {
                  'name': item['name'],
                  'company': item['company'],
                  'quantity': item['quantity'],
                  'status': item['status'],
                  'is_urgent': item['is_urgent'],
                  'notes': item['notes'],
                  'updated_at': item['updated_at'],
                  'is_synced': 1,
                },
                where: 'cloud_id = ?',
                whereArgs: [cloudId]);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ pull shortages error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // مزامنة العملاء
  // ══════════════════════════════════════════════════════════════

  Future<void> _pushCustomers() async {
    final db = await DatabaseHelper.instance.database;
    final unsynced = await db.query('customers',
        where: 'is_synced = 0 OR is_synced IS NULL');

    for (final item in unsynced) {
      try {
        final cloudId = item['cloud_id']?.toString();
        final data = {
          'pharmacy_id': _pharmacyCloudId,
          'local_id': item['id'],
          'name': item['name'],
          'phone': item['phone'],
          'address': item['address'],
          'due_date': item['due_date'],
          'photo_url': item['photo_url'],
          'created_at': item['created_at'],
        };

        http.Response res;
        if (cloudId != null && cloudId.isNotEmpty) {
          res = await http
              .patch(
                Uri.parse('$_url/pharmacy_customers?id=eq.$cloudId'),
                headers: _headers,
                body: jsonEncode(data),
              )
              .timeout(const Duration(seconds: 10));
        } else {
          res = await http
              .post(
                Uri.parse('$_url/pharmacy_customers'),
                headers: _headers,
                body: jsonEncode(data),
              )
              .timeout(const Duration(seconds: 10));
        }

        if (res.statusCode == 200 || res.statusCode == 201) {
          final resData = jsonDecode(res.body);
          final newCloudId =
              resData is List ? resData[0]['id'] : resData['id'];
          await db.update(
              'customers', {'cloud_id': newCloudId, 'is_synced': 1},
              where: 'id = ?', whereArgs: [item['id']]);
        }
      } catch (e) {
        debugPrint('⚠️ push customer error: $e');
      }
    }
  }

  Future<void> _pullCustomers() async {
    final db = await DatabaseHelper.instance.database;
    final lastSync =
        await DatabaseHelper.instance.getSetting('last_sync_at') ?? '';

    try {
      String url =
          '$_url/pharmacy_customers?pharmacy_id=eq.$_pharmacyCloudId&select=*';
      if (lastSync.isNotEmpty) {
        url += '&created_at=gt.$lastSync';
      }

      final res = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;
      final items = jsonDecode(res.body) as List;

      for (final item in items) {
        final cloudId = item['id'];
        final local = await db.query('customers',
            where: 'cloud_id = ?', whereArgs: [cloudId]);

        if (local.isEmpty) {
          await db.insert('customers', {
            'cloud_id': cloudId,
            'name': item['name'],
            'phone': item['phone'],
            'address': item['address'],
            'due_date': item['due_date'],
            'photo_url': item['photo_url'],
            'total_debt': 0,
            'created_at': item['created_at'],
            'is_synced': 1,
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ pull customers error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // مزامنة معاملات الديون
  // ══════════════════════════════════════════════════════════════

  Future<void> _pushDebtTransactions() async {
    final db = await DatabaseHelper.instance.database;
    final unsynced = await db.query('debt_transactions',
        where: 'is_synced = 0 OR is_synced IS NULL');

    for (final item in unsynced) {
      try {
        final cloudId = item['cloud_id']?.toString();
        if (cloudId != null && cloudId.isNotEmpty) {
          // المعاملات لا تتحدث، فقط تُنشأ
          await db.update('debt_transactions', {'is_synced': 1},
              where: 'id = ?', whereArgs: [item['id']]);
          continue;
        }

        // نحتاج local_id للعميل
        final customerLocalId = item['customer_id'];

        final res = await http
            .post(
              Uri.parse('$_url/pharmacy_debt_transactions'),
              headers: _headers,
              body: jsonEncode({
                'pharmacy_id': _pharmacyCloudId,
                'customer_local_id': customerLocalId,
                'amount': item['amount'],
                'type': item['type'],
                'description': item['description'],
                'receipt_url': item['receipt_url'],
                'created_by': item['created_by'] ?? 'المالك',
                'transaction_date': item['transaction_date'],
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200 || res.statusCode == 201) {
          final resData = jsonDecode(res.body);
          final newCloudId =
              resData is List ? resData[0]['id'] : resData['id'];
          await db.update(
              'debt_transactions', {'cloud_id': newCloudId, 'is_synced': 1},
              where: 'id = ?', whereArgs: [item['id']]);
        }
      } catch (e) {
        debugPrint('⚠️ push debt transaction error: $e');
      }
    }
  }

  Future<void> _pullDebtTransactions() async {
    final db = await DatabaseHelper.instance.database;
    final lastSync =
        await DatabaseHelper.instance.getSetting('last_sync_at') ?? '';

    try {
      String url =
          '$_url/pharmacy_debt_transactions?pharmacy_id=eq.$_pharmacyCloudId&select=*';
      if (lastSync.isNotEmpty) {
        url += '&transaction_date=gt.$lastSync';
      }

      final res = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;
      final items = jsonDecode(res.body) as List;

      for (final item in items) {
        final cloudId = item['id'];
        final local = await db.query('debt_transactions',
            where: 'cloud_id = ?', whereArgs: [cloudId]);

        if (local.isEmpty) {
          final customerLocalId = item['customer_local_id'];
          // تحقق إن العميل موجود محلياً
          final customerExists = await db.query('customers',
              where: 'id = ?', whereArgs: [customerLocalId]);
          if (customerExists.isEmpty) continue;

          await DatabaseHelper.instance.addDebtTransaction({
            'cloud_id': cloudId,
            'customer_id': customerLocalId,
            'amount': (item['amount'] as num).toDouble(),
            'type': item['type'],
            'description': item['description'],
            'receipt_url': item['receipt_url'],
            'created_by': item['created_by'],
            'is_synced': 1,
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ pull debt transactions error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // مزامنة الفواتير
  // ══════════════════════════════════════════════════════════════

  Future<void> _pushInvoices() async {
    final db = await DatabaseHelper.instance.database;
    final unsynced = await db.query('invoices',
        where: 'is_synced = 0 OR is_synced IS NULL');

    for (final item in unsynced) {
      try {
        final cloudId = item['cloud_id']?.toString();
        if (cloudId != null && cloudId.isNotEmpty) {
          await db.update('invoices', {'is_synced': 1},
              where: 'id = ?', whereArgs: [item['id']]);
          continue;
        }

        final res = await http
            .post(
              Uri.parse('$_url/pharmacy_invoices'),
              headers: _headers,
              body: jsonEncode({
                'pharmacy_id': _pharmacyCloudId,
                'local_id': item['id'],
                'customer_name': item['customer_name'],
                'items': item['items'],
                'subtotal': item['subtotal'],
                'discount': item['discount'],
                'total': item['total'],
                'notes': item['notes'],
                'created_by': item['created_by'] ?? 'المالك',
                'created_at': item['created_at'],
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200 || res.statusCode == 201) {
          final resData = jsonDecode(res.body);
          final newCloudId =
              resData is List ? resData[0]['id'] : resData['id'];
          await db.update(
              'invoices', {'cloud_id': newCloudId, 'is_synced': 1},
              where: 'id = ?', whereArgs: [item['id']]);
        }
      } catch (e) {
        debugPrint('⚠️ push invoice error: $e');
      }
    }
  }

  Future<void> _pullInvoices() async {
    final db = await DatabaseHelper.instance.database;
    final lastSync =
        await DatabaseHelper.instance.getSetting('last_sync_at') ?? '';

    try {
      String url =
          '$_url/pharmacy_invoices?pharmacy_id=eq.$_pharmacyCloudId&select=*';
      if (lastSync.isNotEmpty) {
        url += '&created_at=gt.$lastSync';
      }

      final res = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;
      final items = jsonDecode(res.body) as List;

      for (final item in items) {
        final cloudId = item['id'];
        final local = await db.query('invoices',
            where: 'cloud_id = ?', whereArgs: [cloudId]);

        if (local.isEmpty) {
          await db.insert('invoices', {
            'cloud_id': cloudId,
            'customer_id': item['customer_id'],
            'customer_name': item['customer_name'],
            'items': item['items'],
            'subtotal': item['subtotal'],
            'discount': item['discount'] ?? 0,
            'total': item['total'],
            'notes': item['notes'],
            'created_at': item['created_at'],
            'is_synced': 1,
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ pull invoices error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // مزامنة المساعدين (من المالك للسحابة فقط)
  // ══════════════════════════════════════════════════════════════

  Future<void> _syncAssistants() async {
    final isAssistantDevice =
        await DatabaseHelper.instance.getSetting('is_assistant_device');
    if (isAssistantDevice == '1') return; // المساعد لا يرفع مساعدين

    final db = await DatabaseHelper.instance.database;
    final assistants = await db.query('assistants');

    for (final a in assistants) {
      try {
        // تحقق هل موجود في السحابة
        final checkRes = await http
            .get(
              Uri.parse(
                  '$_url/pharmacy_assistants?pharmacy_id=eq.$_pharmacyCloudId&name=eq.${Uri.encodeComponent(a['name'].toString())}&select=id'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10));

        if (checkRes.statusCode == 200) {
          final existing = jsonDecode(checkRes.body) as List;
          final data = {
            'pharmacy_id': _pharmacyCloudId,
            'name': a['name'],
            'phone': a['phone'],
            'pin': a['pin'],
            'role': a['role'],
            'can_add_debt': a['can_add_debt'] == 1,
            'can_edit_debt': a['can_edit_debt'] == 1,
            'can_delete': a['can_delete'] == 1,
            'can_view_reports': a['can_view_reports'] == 1,
            'can_manage_invoices': a['can_manage_invoices'] == 1,
            'can_manage_shortages': a['can_manage_shortages'] == 1,
            'can_manage_reps': a['can_manage_reps'] == 1,
            'is_active': a['is_active'] == 1,
            'subscription_expiry': a['subscription_expiry'],
            'subscription_duration_days': a['subscription_duration_days'],
          };

          if (existing.isEmpty) {
            final res = await http
                .post(
                  Uri.parse('$_url/pharmacy_assistants'),
                  headers: _headers,
                  body: jsonEncode(data),
                )
                .timeout(const Duration(seconds: 10));
            if (res.statusCode == 400) {
              debugPrint('⚠️ Schema mismatch on post. Retrying assistant sync without subscription fields.');
              final fallbackData = Map<String, dynamic>.from(data)
                ..remove('subscription_expiry')
                ..remove('subscription_duration_days');
              final resFallback = await http
                  .post(
                    Uri.parse('$_url/pharmacy_assistants'),
                    headers: _headers,
                    body: jsonEncode(fallbackData),
                  )
                  .timeout(const Duration(seconds: 10));
              if (resFallback.statusCode != 200 && resFallback.statusCode != 201) {
                debugPrint('❌ Fallback assistant post failed: ${resFallback.statusCode} ${resFallback.body}');
              }
            } else if (res.statusCode != 200 && res.statusCode != 201) {
              debugPrint('❌ Assistant post failed: ${res.statusCode} ${res.body}');
            }
          } else {
            final res = await http
                .patch(
                  Uri.parse(
                      '$_url/pharmacy_assistants?id=eq.${existing[0]['id']}'),
                  headers: _headers,
                  body: jsonEncode(data),
                )
                .timeout(const Duration(seconds: 10));
            if (res.statusCode == 400) {
              debugPrint('⚠️ Schema mismatch on patch. Retrying assistant sync without subscription fields.');
              final fallbackData = Map<String, dynamic>.from(data)
                ..remove('subscription_expiry')
                ..remove('subscription_duration_days');
              final resFallback = await http
                  .patch(
                    Uri.parse(
                        '$_url/pharmacy_assistants?id=eq.${existing[0]['id']}'),
                    headers: _headers,
                    body: jsonEncode(fallbackData),
                  )
                  .timeout(const Duration(seconds: 10));
              if (resFallback.statusCode != 200 && resFallback.statusCode != 204) {
                debugPrint('❌ Fallback assistant patch failed: ${resFallback.statusCode} ${resFallback.body}');
              }
            } else if (res.statusCode != 200 && res.statusCode != 204) {
              debugPrint('❌ Assistant patch failed: ${res.statusCode} ${res.body}');
            }
          }
        } else {
          debugPrint('❌ Assistant check failed: ${checkRes.statusCode} ${checkRes.body}');
        }
      } catch (e) {
        debugPrint('⚠️ sync assistant error: $e');
      }
    }
  }

  Future<void> deleteAssistantFromCloud(String name) async {
    if (!isConfigured) return;
    if (_pharmacyCloudId == null || _pharmacyCloudId!.isEmpty) {
      _pharmacyCloudId = await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
      if (_pharmacyCloudId == null || _pharmacyCloudId!.isEmpty) return;
    }
    try {
      final res = await http.delete(
        Uri.parse('$_url/pharmacy_assistants?pharmacy_id=eq.$_pharmacyCloudId&name=eq.${Uri.encodeComponent(name)}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 204) {
        debugPrint('✅ تم حذف المساعد من السحابة: $name');
      } else {
        debugPrint('⚠️ فشل حذف المساعد من السحابة (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      debugPrint('⚠️ فشل حذف المساعد من السحابة: $e');
    }
  }

  Future<void> _pullAssistants() async {
    final isAssistantDevice = await DatabaseHelper.instance.getSetting('is_assistant_device');
    if (isAssistantDevice != '1') return; // المالك لا يسحب المساعدين لأنهم عنده الأصل
    await pullAssistantsFromServer();
  }

  Future<void> pullAssistantsFromServer() async {
    if (!isConfigured) return;
    if (_pharmacyCloudId == null || _pharmacyCloudId!.isEmpty) {
      _pharmacyCloudId = await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
      if (_pharmacyCloudId == null || _pharmacyCloudId!.isEmpty) return;
    }

    final db = await DatabaseHelper.instance.database;
    try {
      final res = await http
          .get(
            Uri.parse('$_url/pharmacy_assistants?pharmacy_id=eq.$_pharmacyCloudId\u0026select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final items = jsonDecode(res.body) as List;
        for (final item in items) {
          final cloudId = item['id']?.toString();
          final cloudName = item['name']?.toString().trim();
          if (cloudId == null || cloudName == null || cloudName.isEmpty) continue;

          // تحديث البيانات الكاملة للمساعد
          final Map<String, dynamic> updateData = {
            'cloud_id': cloudId,
            'name': cloudName,
            'phone': item['phone']?.toString() ?? '',
            'role': item['role']?.toString() ?? 'assistant',
            'pin': item['pin']?.toString() ?? '',
            'can_add_debt': item['can_add_debt'] == true ? 1 : 0,
            'can_edit_debt': item['can_edit_debt'] == true ? 1 : 0,
            'can_delete': item['can_delete'] == true ? 1 : 0,
            'can_view_reports': item['can_view_reports'] == true ? 1 : 0,
            'can_manage_invoices': item['can_manage_invoices'] == true ? 1 : 0,
            'can_manage_shortages': item['can_manage_shortages'] == true ? 1 : 0,
            'can_manage_reps': item['can_manage_reps'] == true ? 1 : 0,
            'is_active': item['is_active'] == true ? 1 : 0,
            'subscription_expiry': item['subscription_expiry'],
            'subscription_duration_days': item['subscription_duration_days'] ?? 30,
          };

          // نبحث بالـ cloud_id أولاً (أكثر دقة)
          final existingByCloudId = await db.query('assistants', where: 'cloud_id = ?', whereArgs: [cloudId]);
          if (existingByCloudId.isNotEmpty) {
            // تحديث الموجود بالـ cloud_id
            await db.update('assistants', updateData, where: 'cloud_id = ?', whereArgs: [cloudId]);
            continue;
          }

          // لو مش موجود بـ cloud_id، نبحث بالاسم (backward compatibility)
          final existingByName = await db.query('assistants', where: 'name = ?', whereArgs: [cloudName]);
          if (existingByName.isEmpty) {
            // إضافة مساعد جديد من السحابة
            final insertData = {
              'created_at': item['created_at'] ?? DateTime.now().toIso8601String(),
              ...updateData,
            };
            insertData['subscription_expiry'] ??= DateTime.now().add(const Duration(days: 30)).toIso8601String();
            insertData['subscription_duration_days'] ??= 30;
            await db.insert('assistants', insertData);
          } else {
            // تحديث الموجود بالاسم ونضيف cloud_id
            await db.update('assistants', updateData, where: 'name = ?', whereArgs: [cloudName]);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ pullAssistantsFromServer error: $e');
    }
  }

  Future<Map<String, dynamic>?> checkAssistantLoginByPin(String pin) async {
    if (!isConfigured) return null;
    if (_pharmacyCloudId == null || _pharmacyCloudId!.isEmpty) {
      _pharmacyCloudId = await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
      if (_pharmacyCloudId == null || _pharmacyCloudId!.isEmpty) return null;
    }
    try {
      final res = await http
          .get(
            Uri.parse('$_url/pharmacy_assistants?pharmacy_id=eq.$_pharmacyCloudId&pin=eq.$pin&is_active=eq.true&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final items = jsonDecode(res.body) as List;
        if (items.isNotEmpty) {
          final item = items.first;
          final cloudId = item['id']?.toString();
          final cloudName = item['name']?.toString().trim() ?? '';
          
          // حفظ/تحديث المساعد محلياً
          final db = await DatabaseHelper.instance.database;
          final Map<String, dynamic> localData = {
            'cloud_id': cloudId,
            'name': cloudName,
            'phone': item['phone']?.toString() ?? '',
            'role': item['role']?.toString() ?? 'assistant',
            'pin': item['pin']?.toString() ?? '',
            'can_add_debt': item['can_add_debt'] == true ? 1 : 0,
            'can_edit_debt': item['can_edit_debt'] == true ? 1 : 0,
            'can_delete': item['can_delete'] == true ? 1 : 0,
            'can_view_reports': item['can_view_reports'] == true ? 1 : 0,
            'can_manage_invoices': item['can_manage_invoices'] == true ? 1 : 0,
            'can_manage_shortages': item['can_manage_shortages'] == true ? 1 : 0,
            'can_manage_reps': item['can_manage_reps'] == true ? 1 : 0,
            'is_active': item['is_active'] == true ? 1 : 0,
            'subscription_expiry': item['subscription_expiry'] ?? DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'subscription_duration_days': item['subscription_duration_days'] ?? 30,
          };
          
          // نبحث بالـ cloud_id أولاً (أكثر دقة)
          final existingByCloudId = await db.query('assistants', where: 'cloud_id = ?', whereArgs: [cloudId]);
          if (existingByCloudId.isNotEmpty) {
            await db.update('assistants', localData, where: 'cloud_id = ?', whereArgs: [cloudId]);
            final Map<String, dynamic> result = Map<String, dynamic>.from(existingByCloudId.first);
            result.addAll(localData);
            return result;
          }

          // لو مش موجود بـ cloud_id، نبحث بالاسم (backward compatibility)
          final existingByName = await db.query('assistants', where: 'name = ?', whereArgs: [cloudName]);
          if (existingByName.isEmpty) {
            final insertData = {
              'created_at': item['created_at'] ?? DateTime.now().toIso8601String(),
              ...localData,
            };
            final id = await db.insert('assistants', insertData);
            final Map<String, dynamic> result = Map<String, dynamic>.from(insertData);
            result['id'] = id;
            return result;
          } else {
            await db.update('assistants', localData, where: 'name = ?', whereArgs: [cloudName]);
            final Map<String, dynamic> result = Map<String, dynamic>.from(existingByName.first);
            result.addAll(localData);
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ checkAssistantLoginByPin error: $e');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // مزامنة صلاحيات الأدوية
  // ══════════════════════════════════════════════════════════════

  Future<void> _pushMedicationExpiries() async {
    final db = await DatabaseHelper.instance.database;
    final unsynced = await db.query('medication_expiries',
        where: 'is_synced = 0 OR is_synced IS NULL');

    for (final item in unsynced) {
      try {
        final cloudId = item['cloud_id']?.toString();
        final data = {
          'pharmacy_id': _pharmacyCloudId,
          'local_id': item['id'],
          'name': item['name'],
          'quantity': item['quantity'],
          'expiry_date': item['expiry_date'],
          'supplier_name': item['supplier_name'],
          'notes': item['notes'],
          'created_by': item['created_by'] ?? 'المالك',
          'created_at': item['created_at'],
        };

        http.Response res;
        if (cloudId != null && cloudId.isNotEmpty) {
          res = await http
              .patch(
                Uri.parse('$_url/pharmacy_medication_expiries?id=eq.$cloudId'),
                headers: _headers,
                body: jsonEncode(data),
              )
              .timeout(const Duration(seconds: 10));
        } else {
          res = await http
              .post(
                Uri.parse('$_url/pharmacy_medication_expiries'),
                headers: _headers,
                body: jsonEncode(data),
              )
              .timeout(const Duration(seconds: 10));
        }

        if (res.statusCode == 200 || res.statusCode == 201) {
          final resData = jsonDecode(res.body);
          final newCloudId =
              resData is List ? resData[0]['id'] : resData['id'];
          await db.update(
              'medication_expiries', {'cloud_id': newCloudId, 'is_synced': 1},
              where: 'id = ?', whereArgs: [item['id']]);
        }
      } catch (e) {
        debugPrint('⚠️ push medication expiry error: $e');
      }
    }
  }

  Future<void> _pullMedicationExpiries() async {
    final db = await DatabaseHelper.instance.database;
    final lastSync =
        await DatabaseHelper.instance.getSetting('last_sync_at') ?? '';

    try {
      String url =
          '$_url/pharmacy_medication_expiries?pharmacy_id=eq.$_pharmacyCloudId&select=*';
      if (lastSync.isNotEmpty) {
        url += '&created_at=gt.$lastSync';
      }

      final res = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;
      final items = jsonDecode(res.body) as List;

      for (final item in items) {
        final cloudId = item['id'];
        final local = await db.query('medication_expiries',
            where: 'cloud_id = ?', whereArgs: [cloudId]);

        if (local.isEmpty) {
          await db.insert('medication_expiries', {
            'cloud_id': cloudId,
            'name': item['name'],
            'quantity': item['quantity'] ?? 1,
            'expiry_date': item['expiry_date'],
            'supplier_name': item['supplier_name'],
            'notes': item['notes'],
            'created_by': item['created_by'],
            'created_at': item['created_at'],
            'is_synced': 1,
          });
        } else {
          await db.update(
              'medication_expiries',
              {
                'name': item['name'],
                'quantity': item['quantity'],
                'expiry_date': item['expiry_date'],
                'supplier_name': item['supplier_name'],
                'notes': item['notes'],
                'is_synced': 1,
              },
              where: 'cloud_id = ?',
              whereArgs: [cloudId]);
        }
      }
    } catch (e) {
      debugPrint('⚠️ pull medication expiries error: $e');
    }
  }

  Future<void> deleteMedicationExpiryFromCloud(String cloudId) async {
    if (!isConfigured) return;
    try {
      final res = await http.delete(
        Uri.parse('$_url/pharmacy_medication_expiries?id=eq.$cloudId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 204) {
        debugPrint('✅ تم حذف تاريخ الصلاحية من السحابة: $cloudId');
      } else {
        debugPrint('⚠️ فشل حذف تاريخ الصلاحية من السحابة (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      debugPrint('⚠️ فشل حذف تاريخ الصلاحية من السحابة: $e');
    }
  }
}
