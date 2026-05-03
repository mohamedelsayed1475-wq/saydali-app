import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  static const _url = 'https://kmrszdvsdqfaaksqhnqf.supabase.co/rest/v1';
  static const _key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImttcnN6ZHZzZHFmYWFrc3FobnFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0OTYwNTIsImV4cCI6MjA5MzA3MjA1Mn0.ac8p574OhOG9OPuHzCDOxeHNdEiUkFEtFG_l535Pl3A';

  bool get isConfigured => _key.isNotEmpty && !_key.contains('REPLACE');

  Map<String, String> get _headers => {
        'apikey': _key,
        'Authorization': 'Bearer $_key',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  // ── إنشاء جلسة جديدة ──────────────────────────────────────────────────
  Future<String?> createSession({
    required String repName,
    required String repPhone,
    required String pharmacyName,
    required List<Map<String, dynamic>> items,
  }) async {
    if (!isConfigured) {
      debugPrint('❌ Supabase key غير مضبوط');
      return null;
    }
    try {
      final sessionCode = _generateCode(8);

      final sessionRes = await http.post(
        Uri.parse('$_url/rep_sessions'),
        headers: _headers,
        body: jsonEncode({
          'session_code': sessionCode,
          'rep_name': repName,
          'rep_phone': repPhone,
          'pharmacy_name': pharmacyName,
          'status': 'pending',
          'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));

      if (sessionRes.statusCode != 201) {
        debugPrint('❌ خطأ في إنشاء الجلسة: ${sessionRes.statusCode} ${sessionRes.body}');
        return null;
      }
      final sessionData = jsonDecode(sessionRes.body);
      final sessionId = sessionData is List ? sessionData[0]['id'] : sessionData['id'];

      for (final item in items) {
        final itemRes = await http.post(
          Uri.parse('$_url/session_items'),
          headers: _headers,
          body: jsonEncode({
            'session_id': sessionId,
            'drug_name': item['name'],
            'company': item['company'] ?? 'غير محدد',
            'quantity': item['quantity'] ?? 1,
            'is_private': item['is_private'] ?? 0,
          }),
        ).timeout(const Duration(seconds: 10));

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
  Future<RepResponse?> fetchResponseByCode(String responseCode) async {
    if (!isConfigured) {
      debugPrint('❌ Supabase key غير مضبوط');
      return null;
    }
    try {
      final codeRes = await http.get(
        Uri.parse('$_url/response_codes?response_code=eq.${responseCode.toUpperCase()}&select=*'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (codeRes.statusCode != 200) {
        debugPrint('❌ خطأ في جلب الكود: ${codeRes.statusCode}');
        return null;
      }
      final codes = jsonDecode(codeRes.body) as List;
      if (codes.isEmpty) return null;

      final sessionId = codes[0]['session_id'];

      final sessionRes = await http.get(
        Uri.parse('$_url/rep_sessions?id=eq.$sessionId&select=*'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (sessionRes.statusCode != 200) return null;
      final sessions = jsonDecode(sessionRes.body) as List;
      if (sessions.isEmpty) return null;
      final session = sessions[0];

      final itemsRes = await http.get(
        Uri.parse('$_url/session_items?session_id=eq.$sessionId&select=*'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (itemsRes.statusCode != 200) return null;
      final items = jsonDecode(itemsRes.body) as List;

      return RepResponse(
        repName: session['rep_name'] ?? '',
        repPhone: session['rep_phone'] ?? '',
        pharmacyName: session['pharmacy_name'] ?? '',
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
      );
    } catch (e) {
      debugPrint('❌ fetchResponseByCode error: $e');
      return null;
    }
  }

  // ── توليد كود عشوائي ──────────────────────────────────────────────────
  String _generateCode(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  // ── التحقق من كود الاشتراك ──────────────────────────────────────────────────
  Future<Map<String, dynamic>?> checkSubscriptionCode(String code) async {
    if (!isConfigured) return null;
    try {
      final res = await http.get(
        Uri.parse('$_url/subscription_codes?code=eq.${code.toUpperCase()}&select=*'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) return null;
      return data[0] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ checkSubscriptionCode error: $e');
      return null;
    }
  }

  // ── رابط الصفحة الويب ──────────────────────────────────────────────────
  String buildRepLink(String sessionCode) {
    return 'https://mohamedelsayed1475-wq.github.io/saydali-web/rep.html?code=$sessionCode';
  }
}

// ── نماذج البيانات ──────────────────────────────────────────────────
class RepResponse {
  final String repName;
  final String repPhone;
  final String pharmacyName;
  final DateTime respondedAt;
  final List<ResponseItem> availableItems;
  final List<ResponseItem> unavailableItems;

  RepResponse({
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
        id: map['id'] ?? '',
        drugName: map['drug_name'] ?? '',
        company: map['company'] ?? '',
        quantity: map['quantity'] ?? 1,
        price: (map['price'] as num?)?.toDouble() ?? 0,
        discount: (map['discount'] as num?)?.toDouble() ?? 0,
        notes: map['rep_notes'],
      );

  double get finalPrice => price * (1 - discount / 100);
  double get totalPrice => finalPrice * quantity;
}
