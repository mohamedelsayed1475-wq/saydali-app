import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/env_config.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  static const _url = EnvConfig.supabaseUrl;
  static const _key = EnvConfig.supabaseKey;

  bool get isConfigured =>
      _url.isNotEmpty &&
      _key.isNotEmpty &&
      !_url.contains('REPLACE') &&
      !_key.contains('REPLACE');

  /// تشخيص سريع لسبب عدم الإعداد
  String get configDiagnostic {
    if (_url.isEmpty) return 'SUPABASE_URL فارغ - أضف --dart-define=SUPABASE_URL=...';
    if (_key.isEmpty) return 'SUPABASE_KEY فارغ - أضف --dart-define=SUPABASE_KEY=...';
    return 'الإعدادات تبدو سليمة';
  }

  Map<String, String> get _headers => {
        'apikey': _key,
        'Authorization': 'Bearer $_key',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Map<String, String> get _adminHeaders => {
        'apikey': EnvConfig.supabaseServiceKey,
        'Authorization': 'Bearer ${EnvConfig.supabaseServiceKey}',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  // ── إنشاء جلسة جديدة ──────────────────────────────────────────────────
  Future<String?> createSession({
    required String repName,
    required String repPhone,
    required String pharmacyName,
    required List<Map<String, dynamic>> items,
    String currency = 'ج.م',
  }) async {
    if (!isConfigured) {
      debugPrint('⚠️ Supabase مش مضبوط: ${configDiagnostic}. سيتم استخدام وضع المحاكاة (Mock Mode)');
      await Future.delayed(const Duration(seconds: 1)); // Simulate network
      return 'MOCK${Random().nextInt(9000) + 1000}'; // Return e.g. MOCK1234
    }

    // ── تنظيف تلقائي للجلسات المنتهية قبل الإنشاء ──
    await autoCleanupBeforeCreate();

    try {
      final sessionCode = _generateCode(8);

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
                  .add(const Duration(hours: 2))  // ⬅️ تم التغيير من 4 إلى 2
                  .toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (sessionRes.statusCode != 201) {
        debugPrint(
            '❌ خطأ في إنشاء الجلسة: ${sessionRes.statusCode} ${sessionRes.body}');
        return null;
      }
      final sessionData = jsonDecode(sessionRes.body);
      final sessionId =
          sessionData is List ? sessionData[0]['id'] : sessionData['id'];

      for (final item in items) {
        final itemRes = await http
            .post(
              Uri.parse('$_url/session_items'),
              headers: _headers,
              body: jsonEncode({
                'session_id': sessionId,
                'drug_name': item['name'],
                'company': item['company'] ?? 'غير محدد',
                'quantity': item['quantity'] ?? 1,
                'is_private': item['is_private'] ?? 0,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (itemRes.statusCode != 201) {
          debugPrint('⚠️ خطأ في إضافة صنف: ${item['name']} - ${itemRes.body}');
        }
      }

      return sessionCode;
    } catch (e) {
      debugPrint('❌ createSession error: $e');
      return null;
    }
  }

  // ── استقبال رد المندوب بالكود ──────────────────────────────────────────────────
  Future<({RepResponse? response, String? error})> fetchResponseByCode(
      String responseCode) async {
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
              ResponseItem(id: '1', drugName: 'Congestal', company: 'Sigma', quantity: 5, price: 20.0, discount: 5.0, notes: 'متوفر'),
            ],
            unavailableItems: [
              ResponseItem(id: '2', drugName: 'Panadol', company: 'GSK', quantity: 2, price: 0, discount: 0, notes: 'ناقص'),
            ],
          ),
          error: null
        );
      }
      debugPrint('❌ Supabase key غير مضبوط');
      return (response: null, error: 'إعدادات الاتصال غير مكتملة');
    }
    try {
      final codeRes = await http
          .get(
            Uri.parse(
                '$_url/response_codes?response_code=eq.${responseCode.toUpperCase()}&select=*'),
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
      if (codes.isEmpty) return (response: null, error: null);

      final sessionId = codes[0]['session_id'];

      final sessionRes = await http
          .get(
            Uri.parse('$_url/rep_sessions?id=eq.$sessionId&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (sessionRes.statusCode != 200)
        return (response: null, error: 'خطأ في جلب بيانات الجلسة');
      final sessions = jsonDecode(sessionRes.body) as List;
      if (sessions.isEmpty) return (response: null, error: null);
      final session = sessions[0];

      final itemsRes = await http
          .get(
            Uri.parse('$_url/session_items?session_id=eq.$sessionId&select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (itemsRes.statusCode != 200)
        return (response: null, error: 'خطأ في جلب الأصناف');
      final items = jsonDecode(itemsRes.body) as List;

      return (
        response: RepResponse(
          sessionId: session['id'].toString(),
          repName: session['rep_name']?.toString() ?? '',
          repPhone: session['rep_phone']?.toString() ?? '',
          pharmacyName: session['pharmacy_name']?.toString() ?? '',
          respondedAt: session['responded_at'] != null
              ? DateTime.parse(session['responded_at'])
              : DateTime.now(),
          availableItems: items
              .where((i) => i['is_available'] == 1)
              .map((i) => ResponseItem.fromMap(i))
              .toList(),
          unavailableItems: items
              .where((i) => i['is_available'] == 0)
              .map((i) => ResponseItem.fromMap(i))
              .toList(),
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
      return (response: null, error: 'خطأ في الاتصال: $e');
    }
  }

  // ── تجديد جلسة منتهية ──────────────────────────────────────────────────
  /// يمدد صلاحية جلسة موجودة أو ينشئ جلسة جديدة إذا لم توجد
  Future<String?> renewSession(String oldSessionCode, {
    required String repName,
    required String repPhone,
    required String pharmacyName,
    required List<Map<String, dynamic>> items,
    String currency = 'ج.م',
  }) async {
    if (!isConfigured) {
      await Future.delayed(const Duration(seconds: 1));
      return 'MOCK${Random().nextInt(9000) + 1000}';
    }
    try {
      final sessionRes = await http
          .get(
            Uri.parse('$_url/rep_sessions?session_code=eq.${oldSessionCode.toUpperCase()}&select=*'),
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

      debugPrint('✅ تم حذف الجلسة وبياناتها من السحابة');
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
            headers: _headers,
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
  Future<bool> insertSubscriptionCode(Map<String, dynamic> data) async {
    if (!isConfigured) return false;
    try {
      final payload = Map<String, dynamic>.from(data);
      if (payload.containsKey('is_active')) {
        payload['is_active'] = payload['is_active'] == 1 || payload['is_active'] == true;
      }
      
      final res = await http
          .post(
            Uri.parse('$_url/subscription_codes'),
            headers: _adminHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
          
      if (res.statusCode != 201 && res.statusCode != 200) {
        debugPrint('❌ insertSubscriptionCode failed: ${res.statusCode} - ${res.body}');
      }
      return res.statusCode == 201 || res.statusCode == 200;
    } catch (e) {
      debugPrint('❌ insertSubscriptionCode error: $e');
      return false;
    }
  }

  // ── تحديث الاستخدام ──────────────────────────────────────────────────
  Future<bool> updateSubscriptionCodeUsage(String code, int usedCount) async {
    if (!isConfigured) return false;
    try {
      final res = await http
          .patch(
            Uri.parse('$_url/subscription_codes?code=eq.${code.toUpperCase()}'),
            headers: _headers,
            body: jsonEncode({'used_count': usedCount}),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      debugPrint('❌ updateSubscriptionCodeUsage error: $e');
      return false;
    }
  }

  // ── إضافة إعلان ──────────────────────────────────────────────────
  Future<bool> insertAd(Map<String, dynamic> data) async {
    if (!isConfigured) return false;
    try {
      final payload = Map<String, dynamic>.from(data);
      if (payload.containsKey('is_active')) {
        payload['is_active'] = payload['is_active'] == 1 || payload['is_active'] == true;
      }

      final res = await http
          .post(
            Uri.parse('$_url/ads'),
            headers: _adminHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
          
      if (res.statusCode != 201 && res.statusCode != 200) {
        debugPrint('❌ insertAd failed: ${res.statusCode} - ${res.body}');
      }
      return res.statusCode == 201 || res.statusCode == 200;
    } catch (e) {
      debugPrint('❌ insertAd error: $e');
      return false;
    }
  }

  // ── رابط الصفحة الويب ──────────────────────────────────────────────────
  String buildRepLink(String sessionCode) {
    const fallback = 'https://mohamedelsayed1475-wq.github.io/saydali-app1';
    final baseUrl = EnvConfig.webPortalBaseUrl.isNotEmpty
        ? EnvConfig.webPortalBaseUrl
        : fallback;
    final separator = baseUrl.endsWith('/') ? '' : '/';
    final link = '$baseUrl$separator?code=$sessionCode';
    debugPrint('🔗 رابط المندوب: $link');
    return link;
  }

  // ── حذف الجلسات المنتهية تلقائياً (تنظيف) ──────────────────────────────
  /// يحذف الجلسات اللي انتهت من أكثر من 24 ساعة لتنظيف السحابة
  Future<int> cleanupExpiredSessions() async {
    if (!isConfigured) return 0;
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      
      // 1. نجيب كل الجلسات المنتهية
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
        // حذف الأصناف المرتبطة
        await http
            .delete(
              Uri.parse('$_url/session_items?session_id=eq.$sessionId'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10));
        // حذف أكواد الردود
        await http
            .delete(
              Uri.parse('$_url/response_codes?session_id=eq.$sessionId'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10));
        // حذف الجلسة
        await http
            .delete(
              Uri.parse('$_url/rep_sessions?id=eq.$sessionId'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10));
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
  /// يستدعى قبل إنشاء جلسة جديدة لتنظيف المساحة
  Future<void> autoCleanupBeforeCreate() async {
    if (!isConfigured) return;
    try {
      await cleanupExpiredSessions();
    } catch (e) {
      debugPrint('⚠️ خطأ في التنظيف التلقائي: $e');
    }
  }

  // ── سحب أكواد الاشتراك من السحابة ──────────────────────────────────────
  /// يجلب كل أكواد الاشتراك الفعالة من Supabase
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
  /// يجلب كل الإعلانات النشطة من Supabase
  Future<List<Map<String, dynamic>>> fetchAds() async {
    if (!isConfigured) return [];
    try {
      final res = await http
          .get(
            Uri.parse('$_url/ads?select=*'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as List;
      final activeAds = data.where((a) {
        final val = a['is_active'];
        return val == 1 || val == '1' || val == true || val == 'true';
      }).toList();
      return activeAds.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ fetchAds error: $e');
      return [];
    }
  }
}

// ── نماذج البيانات ──────────────────────────────────────────────────
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

  ResponseItem({
    required this.id,
    required this.drugName,
    required this.company,
    required this.quantity,
    required this.price,
    required this.discount,
    this.notes,
  });

  factory ResponseItem.fromMap(Map<String, dynamic> map) => ResponseItem(
        id: map['id']?.toString() ?? '',
        drugName: map['drug_name']?.toString() ?? '',
        company: map['company']?.toString() ?? '',
        quantity: map['quantity'] as int? ?? 1,
        price: (map['price'] as num?)?.toDouble() ?? 0,
        discount: (map['discount'] as num?)?.toDouble() ?? 0,
        notes: map['rep_notes']?.toString(),
      );

  double get finalPrice => price * (1 - discount / 100);
  double get totalPrice => finalPrice * quantity;
}
