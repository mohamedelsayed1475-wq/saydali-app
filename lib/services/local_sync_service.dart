import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
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

  // ── Auth state ──
  String? _pairingPin;
  String? _pairedToken;

  final StreamController<bool> _serverStateController = StreamController<bool>.broadcast();
  Stream<bool> get onServerStateChanged => _serverStateController.stream;

  final StreamController<void> _syncCompleteController = StreamController<void>.broadcast();
  Stream<void> get onSyncComplete => _syncCompleteController.stream;

  String? get pairingPin => _pairingPin;

  // ══════════════════════════════════════════════════════════════
  // تشغيل وإيقاف الخادم (يقوم به المالك)
  // ══════════════════════════════════════════════════════════════

  Future<bool> startServer() async {
    if (_isServerRunning) return true;

    try {
      _serverIpAddress = await _getLocalIpAddress();
      if (_serverIpAddress == null) {
        debugPrint('❌ لم يتم العثور على عنوان IP محلي.');
        return false;
      }

      // Generate 6-digit pairing PIN
      _pairingPin = List.generate(6, (_) => Random.secure().nextInt(10)).join();
      _pairedToken = null;

      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isServerRunning = true;
      _serverStateController.add(true);
      debugPrint('📶 تم تشغيل خادم المزامنة على: http://$_serverIpAddress:$port');
      debugPrint('🔑 رمز الربط: $_pairingPin');

      _listenForRequests();
      return true;
    } catch (e) {
      debugPrint('❌ فشل تشغيل الخادم: $e');
      _isServerRunning = false;
      _server = null;
      _serverStateController.add(false);
      return false;
    }
  }

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
    _pairingPin = null;
    _pairedToken = null;
    _serverStateController.add(false);
    debugPrint('⏹️ تم إيقاف خادم المزامنة');
  }

  /// Generate a token from PIN + server secret
  String _generateToken(String pin) {
    final secret = 'saydali_local_sync_${_pairingPin}_${_serverIpAddress}';
    final bytes = utf8.encode('$pin$secret');
    return base64.encode(sha256.convert(bytes).bytes);
  }

  bool _isAuthorized(String authHeader) {
    if (!authHeader.startsWith('Bearer ')) return false;
    final token = authHeader.substring(7);
    return _pairedToken != null && token == _pairedToken;
  }

  void _listenForRequests() {
    _server?.listen((HttpRequest request) async {
      final response = request.response;

      response.headers.add('Access-Control-Allow-Origin', '*');
      response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      response.headers.add('Access-Control-Allow-Headers', 'content-type, authorization');

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
        else if (request.uri.path == '/pair' && request.method == 'POST') {
          final bodyStr = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(bodyStr) as Map<String, dynamic>;
          final pin = payload['pin']?.toString() ?? '';

          if (pin != _pairingPin) {
            response.statusCode = HttpStatus.forbidden;
            response.headers.contentType = ContentType.json;
            response.write(jsonEncode({'error': 'Invalid pairing PIN'}));
            await response.close();
            return;
          }

          _pairedToken = _generateToken(pin);
          response.statusCode = HttpStatus.ok;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'token': _pairedToken}));
          await response.close();
          debugPrint('✅ تم الربط مع جهاز مساعد بنجاح');
        }
        else if (request.uri.path == '/sync' && request.method == 'POST') {
          // Authenticate
          final authHeader = request.headers['authorization']?.first ?? '';
          if (!_isAuthorized(authHeader)) {
            response.statusCode = _pairedToken == null ? HttpStatus.unauthorized : HttpStatus.forbidden;
            response.headers.contentType = ContentType.json;
            response.write(jsonEncode({'error': _pairedToken == null ? 'Not paired' : 'Invalid token'}));
            await response.close();
            return;
          }

          final bodyStr = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(bodyStr) as Map<String, dynamic>;

          final clientData = payload['data'] as Map<String, dynamic>;
          final clientLastSync = payload['last_sync_at'] as String?;

          debugPrint('📥 استلام طلب مزامنة محلي من جهاز مساعد...');

          final db = DatabaseHelper.instance;
          await db.mergeLocalSyncData(clientData);
          final serverUpdates = await db.getLocalSyncData(modifiedSince: clientLastSync);
          await db.markLocalDataAsSynced();

          response.statusCode = HttpStatus.ok;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({
            'status': 'success',
            'updates': serverUpdates,
            'server_time': DateTime.now().toIso8601String()
          }));
          await response.close();

          debugPrint('📤 تم إرسال التحديثات بنجاح.');
          _syncCompleteController.add(null);
        }
        else {
          response.statusCode = HttpStatus.notFound;
          response.write('Not Found');
          await response.close();
        }
      } catch (e) {
        debugPrint('❌ خطأ أثناء معالجة الطلب: $e');
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

  /// Pair with the host server using a PIN
  Future<({bool success, String? error, String? token})> pairWithServer(String serverIp, String pin) async {
    final cleanIp = serverIp.trim();
    if (cleanIp.isEmpty) return (success: false, error: 'عنوان IP فارغ', token: null);
    if (pin.length != 6) return (success: false, error: 'رمز الربوط يجب أن يكون 6 أرقام', token: null);

    final serverUrl = 'http://$cleanIp:$port';
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['token']?.toString();
        if (token != null) {
          // Save token locally
          final db = DatabaseHelper.instance;
          await db.setSetting('local_sync_token', token);
          await db.setSetting('last_saved_server_ip', cleanIp);
          return (success: true, error: null, token: token);
        }
      }
      return (success: false, error: 'رمز الربوط غير صحيح أو الخادم غير جاهز', token: null);
    } catch (e) {
      return (success: false, error: 'تعذر الاتصال بالخادم: $e', token: null);
    }
  }

  Future<({bool success, String? error})> performSync(String serverIp) async {
    final cleanIp = serverIp.trim();
    if (cleanIp.isEmpty) {
      return (success: false, error: 'عنوان IP الخادم فارغ');
    }

    final serverUrl = 'http://$cleanIp:$port';
    debugPrint('🔄 جاري بدء المزامنة المحلية مع: $serverUrl');

    try {
      // 1. Ping
      final pingRes = await http.get(Uri.parse('$serverUrl/ping'))
          .timeout(const Duration(seconds: 4));

      if (pingRes.statusCode != 200 || pingRes.body != 'pong') {
        return (success: false, error: 'تعذر الاتصال بخادم الصيدلية.');
      }

      // 2. Get token
      final db = DatabaseHelper.instance;
      var token = await db.getSetting('local_sync_token');
      if (token == null || token.isEmpty) {
        return (success: false, error: 'لم تتم بعد عملية الربط. أدخل رمز الربوط أولاً.');
      }

      // 3. Sync with auth
      final clientUnsynced = await db.getUnsyncedLocalData();
      final lastLocalSync = await db.getSetting('last_local_sync_at') ?? '';

      final res = await http.post(
        Uri.parse('$serverUrl/sync'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'data': clientUnsynced,
          'last_sync_at': lastLocalSync,
        }),
      ).timeout(const Duration(seconds: 25));

      if (res.statusCode == 401 || res.statusCode == 403) {
        // Token rejected — clear it so user must re-pair
        await db.setSetting('local_sync_token', '');
        return (success: false, error: 'تم رفض الاتصال. أعد الربط بالخادم.');
      }

      if (res.statusCode != 200) {
        return (success: false, error: 'فشل إتمام المزامنة (${res.statusCode})');
      }

      final responseBody = jsonDecode(res.body) as Map<String, dynamic>;
      if (responseBody['status'] != 'success') {
        return (success: false, error: responseBody['error']?.toString() ?? 'خطأ غير معروف');
      }

      final serverUpdates = responseBody['updates'] as Map<String, dynamic>;
      await db.mergeLocalSyncData(serverUpdates);
      await db.markLocalDataAsSynced();

      final serverTime = responseBody['server_time'] as String;
      await db.setSetting('last_local_sync_at', serverTime);
      await db.setSetting('last_sync_at', serverTime);

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
            if (interface.name.toLowerCase().contains('vbox') ||
                interface.name.toLowerCase().contains('virtual') ||
                interface.name.toLowerCase().contains('wlan') ||
                interface.name.toLowerCase().contains('eth') ||
                interface.name.toLowerCase().contains('ap') ||
                Platform.isAndroid || Platform.isIOS) {
              return address.address;
            }
          }
        }
      }

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
