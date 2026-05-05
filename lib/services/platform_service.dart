import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// نتيجة بحث من منصة
class PlatformSearchResult {
  final String platformName;
  final String drugName;
  final double price;
  final double discount;
  final bool available;
  final String? drugId;
  final String? notes;

  PlatformSearchResult({
    required this.platformName,
    required this.drugName,
    required this.price,
    this.discount = 0,
    this.available = true,
    this.drugId,
    this.notes,
  });

  double get finalPrice => price - (price * discount / 100);
}

/// إعدادات منصة واحدة
class PlatformConfig {
  final String name;
  final String baseUrl;
  final String apiKey;
  final String searchPath; // e.g. /api/search?q={query}
  final String orderPath;  // e.g. /api/order
  final Map<String, String> headers;

  PlatformConfig({
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.searchPath = '/api/search?q={query}',
    this.orderPath = '/api/order',
    this.headers = const {},
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'searchPath': searchPath,
        'orderPath': orderPath,
        'headers': headers,
      };

  factory PlatformConfig.fromJson(Map<String, dynamic> json) {
    return PlatformConfig(
      name: json['name'] ?? '',
      baseUrl: json['baseUrl'] ?? '',
      apiKey: json['apiKey'] ?? '',
      searchPath: json['searchPath'] ?? '/api/search?q={query}',
      orderPath: json['orderPath'] ?? '/api/order',
      headers: Map<String, String>.from(json['headers'] ?? {}),
    );
  }
}

class PlatformService {
  static final PlatformService instance = PlatformService._();
  PlatformService._();

  static const _key = 'pharmacy_platforms';

  // ── حفظ وتحميل المنصات ──────────────────────────────────────────
  Future<List<PlatformConfig>> getPlatforms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => PlatformConfig.fromJson(e)).toList();
  }

  Future<void> savePlatforms(List<PlatformConfig> platforms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(platforms.map((p) => p.toJson()).toList()));
  }

  Future<void> addPlatform(PlatformConfig config) async {
    final list = await getPlatforms();
    list.add(config);
    await savePlatforms(list);
  }

  Future<void> removePlatform(String name) async {
    final list = await getPlatforms();
    list.removeWhere((p) => p.name == name);
    await savePlatforms(list);
  }

  // ── البحث في منصة واحدة ──────────────────────────────────────────
  Future<List<PlatformSearchResult>> searchPlatform(
      PlatformConfig platform, String query) async {
    try {
      final searchUrl = platform.baseUrl +
          platform.searchPath.replaceAll('{query}', Uri.encodeComponent(query));

      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...platform.headers,
      };
      if (platform.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${platform.apiKey}';
      }

      final response = await http
          .get(Uri.parse(searchUrl), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data is List
            ? data
            : (data['results'] ?? data['data'] ?? data['items'] ?? []);

        return items.take(10).map((item) {
          return PlatformSearchResult(
            platformName: platform.name,
            drugName: item['name']?.toString() ??
                item['drug_name']?.toString() ??
                item['title']?.toString() ??
                query,
            price: (item['price'] ?? item['unit_price'] ?? 0).toDouble(),
            discount:
                (item['discount'] ?? item['discount_percent'] ?? 0).toDouble(),
            available: item['available'] ?? item['in_stock'] ?? true,
            drugId: item['id']?.toString() ?? item['drug_id']?.toString(),
            notes: item['notes']?.toString() ?? item['description']?.toString(),
          );
        }).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ── البحث في كل المنصات ──────────────────────────────────────────
  Future<Map<String, List<PlatformSearchResult>>> searchAll(
      String query) async {
    final platforms = await getPlatforms();
    if (platforms.isEmpty) return {};

    final results = <String, List<PlatformSearchResult>>{};
    final futures = platforms.map((p) async {
      final r = await searchPlatform(p, query);
      if (r.isNotEmpty) results[p.name] = r;
    });
    await Future.wait(futures);
    return results;
  }

  // ── طلب من منصة ──────────────────────────────────────────
  Future<bool> placeOrder(PlatformConfig platform,
      {required String drugId, required int quantity}) async {
    try {
      final orderUrl = platform.baseUrl + platform.orderPath;
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...platform.headers,
      };
      if (platform.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${platform.apiKey}';
      }

      final response = await http
          .post(Uri.parse(orderUrl),
              headers: headers,
              body: jsonEncode({
                'drug_id': drugId,
                'quantity': quantity,
              }))
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
