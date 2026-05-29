import 'dart:convert';
import 'package:http/http.dart' as http;

// ════════════════════════════════════════════════════════════════════════════
// ▌ OpenFDA Service - مجاني 100%
// ════════════════════════════════════════════════════════════════════════════

class OpenFDAService {
  static final OpenFDAService instance = OpenFDAService._();
  OpenFDAService._();

  static const _base = 'https://api.fda.gov/drug';

  // ── بحث عن دواء ──────────────────────────────────────────────────
  Future<DrugInfo?> searchDrug(String name) async {
    try {
      final encoded = Uri.encodeComponent(name);
      final url = '$_base/label.json?search=openfda.brand_name:"$encoded"+openfda.generic_name:"$encoded"&limit=1';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          return DrugInfo.fromFDA(results.first);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── الأعراض الجانبية ──────────────────────────────────────────────────
  Future<List<String>> getSideEffects(String drugName) async {
    try {
      final encoded = Uri.encodeComponent(drugName);
      final url = '$_base/event.json?search=patient.drug.medicinalproduct:"$encoded"&count=patient.reaction.reactionmeddrapt.exact&limit=10';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List? ?? [];
        return results
            .take(8)
            .map((r) => r['term']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ── تحذيرات الدواء ──────────────────────────────────────────────────
  Future<String?> getWarnings(String drugName) async {
    final info = await searchDrug(drugName);
    return info?.warnings;
  }
}

// ── نموذج بيانات الدواء ──────────────────────────────────────────────────
class DrugInfo {
  final String brandName;
  final String genericName;
  final String? indications;
  final String? warnings;
  final String? dosage;
  final String? contraindications;

  DrugInfo({
    required this.brandName,
    required this.genericName,
    this.indications,
    this.warnings,
    this.dosage,
    this.contraindications,
  });

  factory DrugInfo.fromFDA(Map<String, dynamic> data) {
    final openfda = data['openfda'] as Map? ?? {};
    final brands = (openfda['brand_name'] as List?)?.join(', ') ?? '';
    final generics = (openfda['generic_name'] as List?)?.join(', ') ?? '';

    String? clean(dynamic val) {
      if (val == null) return null;
      if (val is List) return val.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return val.toString().trim();
    }

    return DrugInfo(
      brandName: brands,
      genericName: generics,
      indications: clean(data['indications_and_usage']),
      warnings: clean(data['warnings']),
      dosage: clean(data['dosage_and_administration']),
      contraindications: clean(data['contraindications']),
    );
  }

  // تحويل لنص عربي منظم
  String toArabicText() {
    final buf = StringBuffer();
    if (brandName.isNotEmpty) buf.writeln('📋 $brandName');
    if (genericName.isNotEmpty) buf.writeln('🧪 المادة الفعالة: $genericName');
    if (indications != null && indications!.isNotEmpty) {
      buf.writeln('\n📋 دواعي الاستعمال:');
      buf.writeln(_truncate(indications!, 300));
    }
    if (warnings != null && warnings!.isNotEmpty) {
      buf.writeln('\n⚠️ تحذيرات:');
      buf.writeln(_truncate(warnings!, 200));
    }
    if (dosage != null && dosage!.isNotEmpty) {
      buf.writeln('\n💉 الجرعة:');
      buf.writeln(_truncate(dosage!, 200));
    }
    if (contraindications != null && contraindications!.isNotEmpty) {
      buf.writeln('\n⛔ موانع الاستعمال:');
      buf.writeln(_truncate(contraindications!, 200));
    }
    return buf.toString().trim();
  }

  String _truncate(String text, int max) =>
      text.length > max ? '${text.substring(0, max)}...' : text;
}
