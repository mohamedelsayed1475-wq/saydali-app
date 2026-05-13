import 'dart:convert';
import 'package:http/http.dart' as http;

// ════════════════════════════════════════════════════════════════════════════
// ▌ RxNorm Service - مجاني 100% (NIH)
// ════════════════════════════════════════════════════════════════════════════

class RxNormService {
  static final RxNormService instance = RxNormService._();
  RxNormService._();

  static const _base = 'https://rxnav.nlm.nih.gov/REST';

  // ── جلب RxCUI من اسم الدواء ──────────────────────────────────────────────────
  Future<String?> getRxCUI(String drugName) async {
    try {
      final encoded = Uri.encodeComponent(drugName);
      final res = await http
          .get(Uri.parse('$_base/rxcui.json?name=$encoded'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['idGroup']?['rxnormId']?[0] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── البدائل بنفس المادة الفعالة ──────────────────────────────────────────────────
  Future<List<DrugAlternative>> getAlternatives(String drugName) async {
    try {
      final rxcui = await getRxCUI(drugName);
      if (rxcui == null) return [];

      // جلب المادة الفعالة أولاً
      final ingredientRes = await http
          .get(Uri.parse('$_base/rxcui/$rxcui/related.json?tty=IN'))
          .timeout(const Duration(seconds: 10));

      if (ingredientRes.statusCode != 200) return [];

      final ingredientData = jsonDecode(ingredientRes.body);
      final concepts = ingredientData['relatedGroup']?['conceptGroup'] as List? ?? [];

      String? ingredientCUI;
      String? ingredientName;

      for (final group in concepts) {
        final props = group['conceptProperties'] as List? ?? [];
        if (props.isNotEmpty) {
          ingredientCUI = props[0]['rxcui']?.toString();
          ingredientName = props[0]['name']?.toString();
          break;
        }
      }

      if (ingredientCUI == null) return [];

      // جلب كل الأدوية بنفس المادة الفعالة
      final altsRes = await http
          .get(Uri.parse('$_base/rxcui/$ingredientCUI/related.json?tty=SBD+GPCK+SCD'))
          .timeout(const Duration(seconds: 10));

      if (altsRes.statusCode != 200) return [];

      final altsData = jsonDecode(altsRes.body);
      final altConcepts = altsData['relatedGroup']?['conceptGroup'] as List? ?? [];

      final alternatives = <DrugAlternative>[];

      for (final group in altConcepts) {
        final props = group['conceptProperties'] as List? ?? [];
        for (final prop in props.take(10)) {
          final name = prop['name']?.toString() ?? '';
          if (name.isNotEmpty && !name.toLowerCase().contains(drugName.toLowerCase())) {
            alternatives.add(DrugAlternative(
              name: name,
              rxcui: prop['rxcui']?.toString() ?? '',
              activeIngredient: ingredientName ?? '',
            ));
          }
        }
      }

      return alternatives.take(8).toList();
    } catch (_) {
      return [];
    }
  }

  // ── معلومات الجرعة ──────────────────────────────────────────────────
  Future<String?> getDosageInfo(String drugName) async {
    try {
      final rxcui = await getRxCUI(drugName);
      if (rxcui == null) return null;

      final res = await http
          .get(Uri.parse('$_base/rxcui/$rxcui/property.json?propName=AVAILABLE_STRENGTH'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final props = data['propConceptGroup']?['propConcept'] as List? ?? [];
        if (props.isNotEmpty) {
          return props.map((p) => p['propValue']?.toString() ?? '').join(', ');
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── تحويل البدائل لنص عربي ──────────────────────────────────────────────────
  String alternativesToArabicText(List<DrugAlternative> alternatives, String originalDrug) {
    if (alternatives.isEmpty) return '❌ لم أجد بدائل في قاعدة بيانات RxNorm';

    final buf = StringBuffer();
    buf.writeln('🔄 بدائل "$originalDrug":');
    if (alternatives.isNotEmpty) {
      buf.writeln('🧪 المادة الفعالة: ${alternatives.first.activeIngredient}');
    }
    buf.writeln();
    for (final alt in alternatives) {
      buf.writeln('💊 ${alt.name}');
    }
    buf.writeln('\n💡 كل البدائل بنفس المادة الفعالة. استشر الصيدلاني قبل الاستبدال.');
    return buf.toString().trim();
  }
}

class DrugAlternative {
  final String name;
  final String rxcui;
  final String activeIngredient;

  DrugAlternative({
    required this.name,
    required this.rxcui,
    required this.activeIngredient,
  });
}
