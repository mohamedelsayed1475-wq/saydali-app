import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';

class LocalSyncService {
  static final LocalSyncService instance = LocalSyncService._internal();
  LocalSyncService._internal();

  HttpServer? _server;
  bool _isServerRunning = false;
  String? _serverIpAddress;
  final int port = 8080;

  bool get isServerRunning => _isServerRunning;
  String? get serverIpAddress => _serverIpAddress;

  final StreamController<bool> _serverStateController = StreamController<bool>.broadcast();
  Stream<bool> get onServerStateChanged => _serverStateController.stream;

  final StreamController<void> _syncCompleteController = StreamController<void>.broadcast();
  Stream<void> get onSyncComplete => _syncCompleteController.stream;

  // ══════════════════════════════════════════════════════════════
  // تشغيل وإيقاف الخادم (يقوم به المالك)
  // ══════════════════════════════════════════════════════════════

  /// بدء تشغيل الخادم المحلي على جهاز المالك
  Future<bool> startServer() async {
    if (_isServerRunning) return true;

    try {
      _serverIpAddress = await _getLocalIpAddress();
      if (_serverIpAddress == null) {
        debugPrint('❌ لم يتم العثور على عنوان IP محلي. تأكد من الاتصال بـ Wi-Fi أو نقطة اتصال.');
        return false;
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isServerRunning = true;
      _serverStateController.add(true);
      debugPrint('📶 تم تشغيل خادم المزامنة المحلية على: http://$_serverIpAddress:$port');

      _listenForRequests();
      return true;
    } catch (e) {
      debugPrint('❌ فشل تشغيل خادم المزامنة المحلية: $e');
      _isServerRunning = false;
      _server = null;
      _serverStateController.add(false);
      return false;
    }
  }

  /// إيقاف تشغيل الخادم المحلي
  Future<void> stopServer() async {
    if (!_isServerRunning) return;
    try {
      await _server?.close(force: true);
    } catch (e) {
      debugPrint('⚠️ خطأ أثناء إغلاق الخادم: $e');
    }
    _server = null;
    _isServerRunning = false;
    _serverIpAddress = null;
    _serverStateController.add(false);
    debugPrint('⏹️ تم إيقاف خادم المزامنة المحلية');
  }

  /// الاستماع لطلبات المزامنة ومعالجتها
  void _listenForRequests() {
    _server?.listen((HttpRequest request) async {
      final response = request.response;
      
      // إعداد هيدرات CORS لتجنب أي مشاكل متصفح أو تطبيق
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      response.headers.add('Access-Control-Allow-Headers', 'content-type');

      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.ok;
        await response.close();
        return;
      }

      try {
        if (request.uri.path == '/ping') {
          response.statusCode = HttpStatus.ok;
          response.headers.contentType = ContentType.text;
          response.write('pong');
          await response.close();
        } 
        else if (request.uri.path == '/sync' && request.method == 'POST') {
          // قراءة البيانات المرسلة من العميل
          final bodyStr = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(bodyStr) as Map<String, dynamic>;

          final clientData = payload['data'] as Map<String, dynamic>;
          final clientLastSync = payload['last_sync_at'] as String?;

          debugPrint('📥 استلام طلب مزامنة محلي من جهاز مساعد...');

          // 1. دمج بيانات العميل في قاعدة بيانات المالك (الخادم)
          final db = DatabaseHelper.instance;
          await db.mergeLocalSyncData(clientData);

          // 2. جلب بيانات المالك لتحديث العميل (الأشياء التي تغيرت منذ آخر مزامنة للعميل)
          final serverUpdates = await db.getLocalSyncData(modifiedSince: clientLastSync);

          // 3. تعليم البيانات المحلية كـ "تمت مزامنتها"
          await db.markLocalDataAsSynced();

          // 4. إرسال الرد للعميل
          response.statusCode = HttpStatus.ok;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({
            'status': 'success',
            'updates': serverUpdates,
            'server_time': DateTime.now().toIso8601String()
          }));
          await response.close();
          
          debugPrint('📤 تم إرسال التحديثات وجواب المزامنة للعميل بنجاح.');
          _syncCompleteController.add(null);
        } 
        else {
          response.statusCode = HttpStatus.notFound;
          response.write('Not Found');
          await response.close();
        }
      } catch (e) {
        debugPrint('❌ خطأ أثناء معالجة الطلب بالخادم: $e');
        try {
          response.statusCode = HttpStatus.internalServerError;
          response.write(jsonEncode({'error': e.toString()}));
          await response.close();
        } catch (_) {}
      }
    });
  }

  // ══════════════════════════════════════════════════════════════
  // الاتصال وبدء المزامنة من جهاز المساعد (العميل)
  // ══════════════════════════════════════════════════════════════

  /// إجراء المزامنة الثنائية من جهاز المساعد إلى خادم المالك
  Future<({bool success, String? error})> performSync(String serverIp) async {
    final cleanIp = serverIp.trim();
    if (cleanIp.isEmpty) {
      return (success: false, error: 'عنوان IP الخادم فارغ');
    }

    final serverUrl = 'http://$cleanIp:$port';
    debugPrint('🔄 جاري بدء المزامنة المحلية مع: $serverUrl');

    try {
      // 1. تحقق من الاتصال بالخادم أولاً (Ping)
      final pingRes = await http.get(Uri.parse('$serverUrl/ping'))
          .timeout(const Duration(seconds: 4));

      if (pingRes.statusCode != 200 || pingRes.body != 'pong') {
        return (success: false, error: 'تعذر الاتصال بخادم الصيدلية، تأكد من إدخال IP الصحيح أو تشغيل الخادم على جهاز المالك.');
      }

      final db = DatabaseHelper.instance;

      // 2. جلب كافة البيانات المحلية التي لم تُزامن بعد لإرسالها
      final clientUnsynced = await db.getUnsyncedLocalData();
      final lastLocalSync = await db.getSetting('last_local_sync_at') ?? '';

      // 3. إرسال طلب المزامنة
      final res = await http.post(
        Uri.parse('$serverUrl/sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': clientUnsynced,
          'last_sync_at': lastLocalSync,
        }),
      ).timeout(const Duration(seconds: 25));

      if (res.statusCode != 200) {
        return (success: false, error: 'فشل إتمام المزامنة بالخادم (${res.statusCode})');
      }

      final responseBody = jsonDecode(res.body) as Map<String, dynamic>;
      if (responseBody['status'] != 'success') {
        return (success: false, error: responseBody['error']?.toString() ?? 'خطأ غير معروف في المزامنة');
      }

      // 4. دمج البيانات المستلمة من الخادم محلياً
      final serverUpdates = responseBody['updates'] as Map<String, dynamic>;
      await db.mergeLocalSyncData(serverUpdates);

      // 5. تعليم السجلات المحلية كـ "مزامنة"
      await db.markLocalDataAsSynced();

      // 6. حفظ وقت المزامنة الأخير
      final serverTime = responseBody['server_time'] as String;
      await db.setSetting('last_local_sync_at', serverTime);
      await db.setSetting('last_sync_at', serverTime); // لتحديث شاشة الإعدادات المشتركة

      debugPrint('✅ تمت المزامنة المحلية بنجاح!');
      _syncCompleteController.add(null);
      return (success: true, error: null);

    } catch (e) {
      debugPrint('❌ performSync error: $e');
      return (success: false, error: 'حدث خطأ أثناء الاتصال: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // أدوات مساعدة داخلية
  // ══════════════════════════════════════════════════════════════

  /// الحصول على عنوان الـ IP المحلي الفعلي للجهاز المتصل بالشبكة
  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            // تجاهل الواجهات الافتراضية للـ Emulator أو Docker إن وجدت
            if (interface.name.toLowerCase().contains('vbox') || 
                interface.name.toLowerCase().contains('virtual') ||
                interface.name.toLowerCase().contains('wlan') || 
                interface.name.toLowerCase().contains('eth') ||
                interface.name.toLowerCase().contains('ap') || // للـ hotspot
                Platform.isAndroid || Platform.isIOS) {
              return address.address;
            }
          }
        }
      }
      
      // Fallback لأول عنوان غير loopback
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            return address.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return null;
  }
}
