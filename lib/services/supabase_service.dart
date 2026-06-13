import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/env_config.dart';
import '../database/database_helper.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  static const _url = EnvConfig.supabaseUrl;
  static const _key = EnvConfig.supabaseKey;

  String? _pharmacyCloudId;

  Future<void> _ensurePharmacyId() async {
    if (_pharmacyCloudId == null || _pharmacyCloudId!.isEmpty) {
      try {
        _pharmacyCloudId = await DatabaseHelper.instance.getSetting('pharmacy_cloud_id');
      } catch (e) {
        debugPrint('⚠️ Error loading pharmacy_cloud_id in SupabaseService: $e');
      }
    }
  }

  bool get isConfigured =>
      _url.isNotEmpty &&
      _key.isNotEmpty &&
      !_url.contains('REPLACE') &&
      !_key.contains('REPLACE');

  String? lastError;

  String get configDiagnostic {
    if (_url.isEmpty) return 'SUPABASE_URL فارغ - أضف --dart-define=SUPABASE_URL=...';
    if (_key.isEmpty) return 'SUPABASE_KEY فارغ - أضف --dart-define=SUPABASE_KEY=...';
    return 'الإعدادات تبدو سليمة';
  }

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

  // ── إنشاء جلسة جديدة ──────────────────────────────────────────────────
  Future<String?> createSession({
    required String repName,
    required String repPhone,
    required String pharmacyName,
    required List<Map<String, dynamic>> items,
    String currency = 'ج.م',
  }) async {
    lastError = null;
    await _ensurePharmacyId();
    if (!isConfigured) {
      debugPrint('⚠️ Supabase مش مضبوط: $configDiagnostic. سيتم استخدام وضع المحاكاة (Mock Mode)');
      await Future.delayed(const Duration(seconds: 1));
      return 'MOCK${Random().nextInt(9000) + 1000}';
    }

    await autoCleanupBeforeCreate();

    try {
      final sessionCode = _generateCode(8);

      // 1. إنشاء الجلسة
      final sessionRes = await http
          .post(
            Uri.parse('$_url/rep_sessions'),
            headers: _headers,
            body: jsonEncode({
              'session_code': sessionCode,
              'rep_name': repName,
              'rep_phone': repPhone,
              'pharmacy_name': pharmacyName,
              'currency': currency,
              'status': 'pending',
              'expires_at': DateTime.now()
                  .add(const Duration(hours: 2))
                  .toIso8601String(),
              if (_pharmacyCloudId != null && _pharmacyCloudId!.isNotEmpty)
                'pharmacy_id': _pharmacyCloudId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (sessionRes.statusCode != 201) {
        lastError = 'فشل إنشاء جلسة المندوب (${sessionRes.statusCode}): ${sessionRes.body}';
        debugPrint('❌ $lastError');
        return null;
      }

      final sessionData = jsonDecode(sessionRes.body);
      final sessionId =
          sessionData is List ? sessionData[0]['id'] : sessionData['id'];

      // 2. إضافة الأصناف
      for (final item in items) {
        final itemRes = await http
            .post(
              Uri.parse('$_url/session_items'),
              headers: _headers,
              body: jsonEncode({
                'session_id': sessionId,
                'drug_name': item['name'],
                'company': item['company']?.toString().isEmpty ?? true
                    ? ''
                    : item['company'],
                'quantity': item['quantity'] ?? 1,
                'is_private': item['is_private'] ?? 0,
                'is_available': 0,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (itemRes.statusCode != 201) {
          debugPrint('⚠️ خطأ في إضافة صنف: ${item['name']} - ${itemRes.body}');
        }
      }

      // ✅ تم حذف حفظ response_code هنا عمداً
      // الكود الصحيح يتولد فقط من الموقع عند رد المندوب
      // ويُحفظ في جدول response_codes تلقائياً عبر الموقع

      debugPrint('✅ تم إنشاء الجلسة: $sessionCode (id: $sessionId)');
      return sessionCode;
    } catch (e) {
      lastError = 'خطأ اتصال بالشبكة: $e';
      debugPrint('❌ createSession error: $e');
      return null;
    }
  }

  // ── استقبال رد المندوب بالكود ──────────────────────────────────────────────────
  Future<({RepResponse? response, String? error})> fetchResponseByCode(
      String responseCode) async {
    await _ensurePharmacyId();
    if (!isConfigured) {
      if (responseCode.toUpperCase().startsWith('MOCK')) {
        await Future.delayed(const Duration(seconds: 1));
        return (
          response: RepResponse(
            sessionId: 'mock_session_id',
            repName: 'مندوب تجريبي',
            repPhone: '01000000000',
            pharmacyName: 'صيدليتي',
            respondedAt: DateTime.now(),
            availableItems: [
              ResponseItem(
                id: '1',
                drugName: 'Congestal',
                company: 'Sigma',
                quantity: 5,
                price: 20.0,
                discount: 5.0,
                notes: 'متوفر',
              ),
            ],
            unavailableItems: [
              ResponseItem(
                id: '2',
                drugName: 'Panadol',
                company: 'GSK',
                quantity: 2,
                price: 0,
                discount: 0,
                notes: 'ناقص',
              ),
            ],
          ),
          error: null
        );
      }
      debugPrint('❌ Supabase key غير مضبوط');
      return (response: null, error: 'إعدادات الاتصال غير مكتملة');
    }

    try {
      final formattedCode = responseCode.trim().toUpperCase();

      // 1. جلب الجلسة من جدول response_codes
      final codeRes = await http
          .get(
            Uri.parse(
                '$_url/response_codes?response_code=eq.$formattedCode&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (codeRes.statusCode != 200) {
        debugPrint('❌ خطأ في جلب الكود: ${codeRes.statusCode}');
        return (
          response: null,
          error: 'خطأ من السيرفر (${codeRes.statusCode})'
        );
      }

      final codes = jsonDecode(codeRes.body) as List;
      String? sessionId;

      if (codes.isNotEmpty) {
        sessionId = codes[0]['session_id']?.toString();
      } else {
        // Fallback: البحث في rep_sessions عن session_code مباشرة (لدعم الجلسات القديمة أيضاً)
        final sessionByCodeRes = await http
            .get(
              Uri.parse(
                  '$_url/rep_sessions?session_code=eq.$formattedCode&select=id'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10));

        if (sessionByCodeRes.statusCode == 200) {
          final sessions = jsonDecode(sessionByCodeRes.body) as List;
          if (sessions.isNotEmpty) {
            sessionId = sessions[0]['id']?.toString();
          }
        }
      }

      if (sessionId == null) {
        return (response: null, error: 'كود غير صحيح أو منتهي الصلاحية');
      }

      // 2. جلب بيانات الجلسة
      final sessionRes = await http
          .get(
            Uri.parse('$_url/rep_sessions?id=eq.$sessionId&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (sessionRes.statusCode != 200) {
        return (response: null, error: 'خطأ في جلب بيانات الجلسة');
      }

      final sessions = jsonDecode(sessionRes.body) as List;
      if (sessions.isEmpty) {
        return (response: null, error: 'لم يتم العثور على الجلسة');
      }

      final session = sessions[0];

      // التحقق من أن الجلسة تم الرد عليها فعلاً
      if (session['status'] != 'responded') {
        return (response: null, error: 'لم يرد المندوب بعد على هذا الطلب');
      }

      // 3. جلب الأصناف
      final itemsRes = await http
          .get(
            Uri.parse('$_url/session_items?session_id=eq.$sessionId&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (itemsRes.statusCode != 200) {
        return (response: null, error: 'خطأ في جلب الأصناف');
      }

      final items = jsonDecode(itemsRes.body) as List;

      // تصفية مرنة تدعم Integer وBoolean
      final availableList = items.where((i) {
        final val = i['is_available'];
        return val == 1 || val == true || val == '1' || val == 'true';
      }).map((i) => ResponseItem.fromMap(i)).toList();

      final unavailableList = items.where((i) {
        final val = i['is_available'];
        return val == 0 ||
            val == false ||
            val == '0' ||
            val == 'false' ||
            val == null;
      }).map((i) => ResponseItem.fromMap(i)).toList();

      return (
        response: RepResponse(
          sessionId: session['id'].toString(),
          repName: session['rep_name']?.toString() ?? 'غير معروف',
          repPhone: session['rep_phone']?.toString() ?? '',
          pharmacyName: session['pharmacy_name']?.toString() ?? '',
          respondedAt: session['responded_at'] != null
              ? DateTime.parse(session['responded_at'])
              : DateTime.now(),
          availableItems: availableList,
          unavailableItems: unavailableList,
        ),
        error: null
      );
    } on TimeoutException {
      debugPrint('❌ fetchResponseByCode timeout');
      return (response: null, error: 'انتهت مهلة الاتصال - تحقق من الإنترنت');
    } on SocketException {
      debugPrint('❌ fetchResponseByCode no internet');
      return (response: null, error: 'لا يوجد اتصال بالإنترنت');
    } catch (e) {
      debugPrint('❌ fetchResponseByCode error: $e');
      return (response: null, error: 'حدث خطأ غير متوقع: $e');
    }
  }

  // ── جلب كل الجلسات النشطة للصيدلية ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchPharmacySessions(
      String pharmacyName) async {
    await _ensurePharmacyId();
    if (!isConfigured) return [];
    try {
      final res = await http
          .get(
            Uri.parse(
                '$_url/rep_sessions?pharmacy_name=eq.${Uri.encodeComponent(pharmacyName)}&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('❌ fetchPharmacySessions error: $e');
      return [];
    }
  }

  // ── تجديد جلسة منتهية ──────────────────────────────────────────────────
  Future<String?> renewSession(
    String oldSessionCode, {
    required String repName,
    required String repPhone,
    required String pharmacyName,
    required List<Map<String, dynamic>> items,
    String currency = 'ج.م',
  }) async {
    await _ensurePharmacyId();
    if (!isConfigured) {
      await Future.delayed(const Duration(seconds: 1));
      return 'MOCK${Random().nextInt(9000) + 1000}';
    }
    try {
      final sessionRes = await http
          .get(
            Uri.parse(
                '$_url/rep_sessions?session_code=eq.${oldSessionCode.toUpperCase()}&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (sessionRes.statusCode == 200) {
        final sessions = jsonDecode(sessionRes.body) as List;
        if (sessions.isNotEmpty) {
          final sessionId = sessions[0]['id'];
          await http
              .patch(
                Uri.parse('$_url/rep_sessions?id=eq.$sessionId'),
                headers: _headers,
                body: jsonEncode({
                  'expires_at': DateTime.now()
                      .add(const Duration(hours: 2))
                      .toIso8601String(),
                  'status': 'pending',
                }),
              )
              .timeout(const Duration(seconds: 10));
          debugPrint('✅ تم تجديد الجلسة: $oldSessionCode');
          return oldSessionCode;
        }
      }

      return createSession(
        repName: repName,
        repPhone: repPhone,
        pharmacyName: pharmacyName,
        items: items,
        currency: currency,
      );
    } catch (e) {
      debugPrint('❌ renewSession error: $e');
      return createSession(
        repName: repName,
        repPhone: repPhone,
        pharmacyName: pharmacyName,
        items: items,
        currency: currency,
      );
    }
  }

  // ── حذف الجلسة وبياناتها من السحابة ──────────────────
  Future<void> deleteSession(String sessionId) async {
    await _ensurePharmacyId();
    if (!isConfigured) return;
    try {
      await http
          .delete(
            Uri.parse('$_url/session_items?session_id=eq.$sessionId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      await http
          .delete(
            Uri.parse('$_url/response_codes?session_id=eq.$sessionId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      await http
          .delete(
            Uri.parse('$_url/rep_sessions?id=eq.$sessionId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('✅ تم حذف الجلسة وبياناتها: $sessionId');
    } catch (e) {
      debugPrint('❌ deleteSession error: $e');
    }
  }

  // ── توليد كود عشوائي ──────────────────────────────────────────────────
  String _generateCode(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }

  // ── التحقق من كود الاشتراك ──────────────────────────────────────────────────
  Future<Map<String, dynamic>?> checkSubscriptionCode(String code) async {
    if (!isConfigured) return null;
    try {
      final res = await http
          .get(
            Uri.parse(
                '$_url/subscription_codes?code=eq.${code.toUpperCase()}&select=*'),
            headers: {..._headers, 'x-subscription-code': code.toUpperCase()},
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) return null;
      return data[0] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ checkSubscriptionCode error: $e');
      return null;
    }
  }

  // ── إضافة كود اشتراك ──────────────────────────────────────────────────
  Future<({bool ok, String error})> insertSubscriptionCode(
      Map<String, dynamic> data) async {
    if (!isConfigured) {
      return (ok: false, error: 'إعدادات السحابة غير مكتملة:\n$configDiagnostic');
    }

    try {
      final payload = Map<String, dynamic>.from(data);
      if (payload.containsKey('is_active')) {
        payload['is_active'] =
            payload['is_active'] == 1 || payload['is_active'] == true;
      }

      final res = await http
          .post(
            Uri.parse('$_url/rpc/add_subscription_code_rpc'),
            headers: _headers,
            body: jsonEncode({
              'p_code': payload['code'],
              'p_plan': payload['plan'],
              'p_duration_days': payload['duration_days'] ?? 0,
              'p_discount_percent': payload['discount_percent'] ?? 0.0,
              'p_max_uses': payload['max_uses'] ?? 1,
              'p_is_active': payload['is_active'] ?? true,
              'p_secret_pass': EnvConfig.devPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return (ok: true, error: '');
      } else {
        String errorMsg = 'رمز الاستجابة ${res.statusCode}';
        try {
          final parsed = jsonDecode(res.body);
          if (parsed is Map && parsed.containsKey('message')) {
            errorMsg = '${parsed['message']} (${res.statusCode})';
          }
        } catch (_) {}
        debugPrint(
            '❌ insertSubscriptionCode failed: ${res.statusCode} - ${res.body}');
        return (ok: false, error: errorMsg);
      }
    } catch (e) {
      debugPrint('❌ insertSubscriptionCode error: $e');
      return (ok: false, error: 'حدث خطأ أثناء الاتصال: $e');
    }
  }

  // ── تحديث الاستخدام ──────────────────────────────────────────────────
  Future<bool> updateSubscriptionCodeUsage(String code, int usedCount) async {
    if (!isConfigured) return false;
    try {
      final res = await http
          .patch(
            Uri.parse(
                '$_url/subscription_codes?code=eq.${code.toUpperCase()}'),
            headers: {..._headers, 'x-subscription-code': code.toUpperCase()},
            body: jsonEncode({'is_used': usedCount > 0}),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      debugPrint('❌ updateSubscriptionCodeUsage error: $e');
      return false;
    }
  }

  // ── إضافة إعلان ──────────────────────────────────────────────────
  Future<({bool ok, String error})> insertAd(
      Map<String, dynamic> data) async {
    if (!isConfigured) {
      return (ok: false, error: 'إعدادات السحابة غير مكتملة:\n$configDiagnostic');
    }
    try {
      final payload = Map<String, dynamic>.from(data);
      if (payload.containsKey('is_active')) {
        payload['is_active'] =
            payload['is_active'] == 1 || payload['is_active'] == true;
      }

      final res = await http
          .post(
            Uri.parse('$_url/rpc/add_ad_rpc'),
            headers: _headers,
            body: jsonEncode({
              'p_title': payload['title'],
              'p_body': payload['body'] ?? '',
              'p_image_url': payload['image_url'],
              'p_link_url': payload['link'] ?? payload['link_url'] ?? '',
              'p_button_text': payload['button_text'] ?? 'التفاصيل',
              'p_is_active': payload['is_active'] ?? true,
              'p_screen': payload['screen'] ?? 'home',
              'p_skip_duration': payload['skip_duration'] ?? 0,
              'p_expires_at': payload['expires_at'] ?? '',
              'p_target_country': payload['target_country'] ?? '',
              'p_display_order': payload['display_order'] ?? 0,
              'p_secret_pass': EnvConfig.devPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return (ok: true, error: '');
      } else {
        String errorMsg = 'رمز الاستجابة ${res.statusCode}';
        try {
          final parsed = jsonDecode(res.body);
          if (parsed is Map && parsed.containsKey('message')) {
            errorMsg = '${parsed['message']} (${res.statusCode})';
          }
        } catch (_) {}
        debugPrint('❌ insertAd failed: ${res.statusCode} - ${res.body}');
        return (ok: false, error: errorMsg);
      }
    } catch (e) {
      debugPrint('❌ insertAd error: $e');
      return (ok: false, error: 'حدث خطأ أثناء الاتصال: $e');
    }
  }

  // ── رفع صورة الإعلان ──────────────────────────────────────────────────
  Future<String?> uploadAdImage(String filePath) async {
    if (!isConfigured) return null;
    try {
      final file = File(filePath);
      final fileName = 'ad_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await file.readAsBytes();

      final res = await http
          .post(
            Uri.parse(
                '${EnvConfig.supabaseUrl.replaceAll('/rest/v1', '')}/storage/v1/object/ads-images/$fileName'),
            headers: {
              'apikey': EnvConfig.supabaseKey,
              'Authorization': 'Bearer ${EnvConfig.supabaseKey}',
              'Content-Type': 'image/jpeg',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return '${EnvConfig.supabaseUrl.replaceAll('/rest/v1', '')}/storage/v1/object/public/ads-images/$fileName';
      }
      debugPrint('❌ uploadAdImage failed: ${res.statusCode} - ${res.body}');
      return null;
    } catch (e) {
      debugPrint('❌ uploadAdImage error: $e');
      return null;
    }
  }

  // ── رفع صورة العميل ──────────────────────────────────────────────────
  Future<String?> uploadCustomerPhoto(
      String filePath, String customerId) async {
    if (!isConfigured) return null;
    try {
      final file = File(filePath);
      final fileName =
          'customer_${customerId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await file.readAsBytes();

      final res = await http
          .post(
            Uri.parse(
                '${EnvConfig.supabaseUrl.replaceAll('/rest/v1', '')}/storage/v1/object/customer-photos/$fileName'),
            headers: {
              'apikey': EnvConfig.supabaseKey,
              'Authorization': 'Bearer ${EnvConfig.supabaseKey}',
              'Content-Type': 'image/jpeg',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return '${EnvConfig.supabaseUrl.replaceAll('/rest/v1', '')}/storage/v1/object/public/customer-photos/$fileName';
      }
      debugPrint(
          '❌ uploadCustomerPhoto failed: ${res.statusCode} - ${res.body}');
      return null;
    } catch (e) {
      debugPrint('❌ uploadCustomerPhoto error: $e');
      return null;
    }
  }

  // ── رفع إيصال الدين ──────────────────────────────────────────────────
  Future<String?> uploadReceiptPhoto(
      String filePath, String transactionId) async {
    if (!isConfigured) return null;
    try {
      final file = File(filePath);
      final fileName =
          'receipt_${transactionId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await file.readAsBytes();

      final res = await http
          .post(
            Uri.parse(
                '${EnvConfig.supabaseUrl.replaceAll('/rest/v1', '')}/storage/v1/object/debt-receipts/$fileName'),
            headers: {
              'apikey': EnvConfig.supabaseKey,
              'Authorization': 'Bearer ${EnvConfig.supabaseKey}',
              'Content-Type': 'image/jpeg',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return '${EnvConfig.supabaseUrl.replaceAll('/rest/v1', '')}/storage/v1/object/public/debt-receipts/$fileName';
      }
      debugPrint(
          '❌ uploadReceiptPhoto failed: ${res.statusCode} - ${res.body}');
      return null;
    } catch (e) {
      debugPrint('❌ uploadReceiptPhoto error: $e');
      return null;
    }
  }

  // ── رابط الصفحة الويب (الكود فقط — بدون تمرير المفاتيح) ──────────────
  // كل صيدلية تضيف السحابة الخاصة بها وتستضيف الصفحة بشكل مستقل
  String buildRepLink(String sessionCode) {
    const fallback = 'https://mohamedelsayed1475-wq.github.io/saydali-app';
    final baseUrl = EnvConfig.webPortalBaseUrl.isNotEmpty
        ? EnvConfig.webPortalBaseUrl
        : fallback;

    final separator = baseUrl.endsWith('/') ? '' : '/';
    final link = '$baseUrl$separator?code=$sessionCode';
    debugPrint('🔗 رابط المندوب: $link');
    return link;
  }

  // ── حذف الجلسات المنتهية تلقائياً (تنظيف) ──────────────────────────────
  Future<int> cleanupExpiredSessions() async {
    await _ensurePharmacyId();
    if (!isConfigured) return 0;
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));

      final sessionsRes = await http
          .get(
            Uri.parse(
                '$_url/rep_sessions?expires_at=lt.${cutoff.toIso8601String()}&select=id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));

      if (sessionsRes.statusCode != 200) return 0;
      final sessions = jsonDecode(sessionsRes.body) as List;

      if (sessions.isEmpty) {
        debugPrint('✅ لا توجد جلسات منتهية للحذف');
        return 0;
      }

      int deletedCount = 0;
      for (final session in sessions) {
        final sessionId = session['id'];
        await deleteSession(sessionId.toString());
        deletedCount++;
      }

      debugPrint('✅ تم حذف $deletedCount جلسة منتهية');
      return deletedCount;
    } catch (e) {
      debugPrint('❌ cleanupExpiredSessions error: $e');
      return 0;
    }
  }

  // ── حذف الجلسات المنتهية قبل إنشاء جديدة ──────────────────────────────
  Future<void> autoCleanupBeforeCreate() async {
    if (!isConfigured) return;
    try {
      await cleanupExpiredSessions();
    } catch (e) {
      debugPrint('⚠️ خطأ في التنظيف التلقائي: $e');
    }
  }

  // ── سحب أكواد الاشتراك من السحابة ──────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchSubscriptionCodes() async {
    if (!isConfigured) return [];
    try {
      final res = await http
          .get(
            Uri.parse('$_url/subscription_codes?select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as List;
      final activeCodes = data.where((c) {
        final val = c['is_active'];
        return val == 1 || val == '1' || val == true || val == 'true';
      }).toList();
      return activeCodes.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ fetchSubscriptionCodes error: $e');
      return [];
    }
  }

  // ── سحب الإعلانات من السحابة ──────────────────────────────────────
  Future<List<Map<String, dynamic>>?> fetchAds() async {
    if (!isConfigured) return null;
    try {
      final res = await http
          .get(
            Uri.parse('$_url/ads?select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      final activeAds = data.where((a) {
        final val = a['is_active'];
        return val == 1 || val == '1' || val == true || val == 'true';
      }).toList();
      return activeAds.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ fetchAds error: $e');
      return null;
    }
  }
}

// ── نماذج البيانات ─────────────────────────────────────────────────────────
class RepResponse {
  final String sessionId;
  final String repName;
  final String repPhone;
  final String pharmacyName;
  final DateTime respondedAt;
  final List<ResponseItem> availableItems;
  final List<ResponseItem> unavailableItems;

  RepResponse({
    required this.sessionId,
    required this.repName,
    required this.repPhone,
    required this.pharmacyName,
    required this.respondedAt,
    required this.availableItems,
    required this.unavailableItems,
  });
}

class ResponseItem {
  final String id;
  final String drugName;
  final String company;
  final int quantity;
  final double price;
  final double discount;
  final String? notes;
  final String? repAlternative;

  ResponseItem({
    required this.id,
    required this.drugName,
    required this.company,
    required this.quantity,
    required this.price,
    required this.discount,
    this.notes,
    this.repAlternative,
  });

  factory ResponseItem.fromMap(Map<String, dynamic> map) => ResponseItem(
        id: map['id']?.toString() ?? '',
        drugName: map['drug_name']?.toString() ?? '',
        company: map['company']?.toString() ?? '',
        quantity: (map['quantity'] as num?)?.toInt() ?? 1,
        price: (map['price'] as num?)?.toDouble() ?? 0.0,
        discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
        notes: map['rep_notes']?.toString(),
        repAlternative: map['rep_alternative']?.toString(),
      );

  double get finalPrice => price * (1 - discount / 100);
  double get totalPrice => finalPrice * quantity;
}
