import 'dart:convert';
import 'package:http/http.dart' as http;

class FdaDrugModel {
  final String brandName;
  final String genericName;
  final String indications;
  final String dosage;
  final String adverseReactions;
  final String contraindications;
  final List<String> allBrands;

  FdaDrugModel({
    required this.brandName,
    required this.genericName,
    required this.indications,
    required this.dosage,
    required this.adverseReactions,
    required this.contraindications,
    required this.allBrands,
  });

  factory FdaDrugModel.fromJson(Map<String, dynamic> json) {
    final openfda = json['openfda'] as Map<String, dynamic>? ?? {};
    
    // استخراج أسماء تجارية
    final brandList = (openfda['brand_name'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final brandName = brandList.isNotEmpty ? brandList.first : 'Unknown Brand';
    
    // استخراج المادة الفعالة
    final genericList = (openfda['generic_name'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final genericName = genericList.isNotEmpty ? genericList.first : 'Unknown Generic';

    // تنظيف المخرجات النصية للخصائص الطبية
    String _cleanList(dynamic val) {
      if (val == null) return 'Not available';
      if (val is List) {
        return val.join('\n').trim();
      }
      return val.toString().trim();
    }

    return FdaDrugModel(
      brandName: brandName,
      genericName: genericName,
      indications: _cleanList(json['indications_and_usage']),
      dosage: _cleanList(json['dosage_and_administration']),
      adverseReactions: _cleanList(json['adverse_reactions']),
      contraindications: _cleanList(json['contraindications']),
      allBrands: brandList,
    );
  }
}

class OpenFdaService {
  static final OpenFdaService instance = OpenFdaService._();
  OpenFdaService._();

  static const String _baseUrl = 'https://api.fda.gov/drug/label.json';

  /// البحث عن الدواء بالاسم التجاري أو المادة الفعالة
  Future<List<FdaDrugModel>> searchDrug(String query) async {
    if (query.trim().isEmpty) return [];
    
    try {
      // البحث بمرونة عن الاسم التجاري أو العلمي
      // نستخدم ترميز آمن ومناسب لـ openFDA API
      final formattedQuery = query.trim().replaceAll(' ', '+');
      final url = '$_baseUrl?search=(openfda.brand_name:"$formattedQuery"+openfda.generic_name:"$formattedQuery")&limit=8';

      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List? ?? [];
        return results.map((e) => FdaDrugModel.fromJson(e)).toList();
      }
      
      return [];
    } catch (_) {
      return [];
    }
  }
}
