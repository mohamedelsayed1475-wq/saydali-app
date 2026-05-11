import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:excel/excel.dart' as ex;
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'package:archive/archive.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../database/database_helper.dart';
import '../utils/fuzzy_search.dart';
import 'platform_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// ▌ نظام المساعد الذكي "حكيم" - الإصدار المدمج v4.0 ▌
// ▌ يجمع أفضل ميزات v1 + v2 بدون تكرار                ▌
// ════════════════════════════════════════════════════════════════════════════

// ── أنواع النوايا (Intents) ──────────────────────────────────────────────────
enum ChatIntent {
  // إدارة النواقص
  addShortage,
  showShortages,
  showPendingShortages,
  markCovered,
  deleteShortage,

  // البحث والاستفسار
  searchDrug,
  findAlternative,
  analyzePatterns,
  searchPlatform,

  // إدارة العملاء والديون
  addCustomer,
  showDebts,
  checkCustomerDebt,
  addDebt,
  recordPayment,

  // المندوبين
  showReps,
  addRep,

  // التقارير
  showStats,
  generateReport,

  // إعدادات
  apiSettings,
  help,

  // ميزات متقدمة
  addShortagesFromImage,
  smartChat,

  // أنواع محددة من الرسائل
  drugInquiry,
  priceInquiry,
  availabilityInquiry,
  generalQuestion,
  complaint,
  suggestion,

  unknown,
}

// ── نموذج الرد ──────────────────────────────────────────────────
class ChatResponse {
  final String text;
  final ChatIntent intent;
  final bool success;
  final Map<String, dynamic>? actionData;

  ChatResponse({
    required this.text,
    required this.intent,
    this.success = true,
    this.actionData,
  });
}

// ── Message Type Enum ──────────────────────────────────────────────────
enum MessageType {
  drug,
  alternative,
  shortage,
  debt,
  rep,
  stats,
  general,
  image,
}

extension MessageTypeExtension on MessageType {
  String get emoji {
    switch (this) {
      case MessageType.drug:
        return '💊';
      case MessageType.alternative:
        return '🔄';
      case MessageType.shortage:
        return '📋';
      case MessageType.debt:
        return '💰';
      case MessageType.rep:
        return '👥';
      case MessageType.stats:
        return '📊';
      case MessageType.general:
        return '❓';
      case MessageType.image:
        return '🖼️';
    }
  }

  String get label {
    switch (this) {
      case MessageType.drug:
        return 'استفسار دواء';
      case MessageType.alternative:
        return 'طلب بديل';
      case MessageType.shortage:
        return 'إضافة ناقص';
      case MessageType.debt:
        return 'سؤال عن دين';
      case MessageType.rep:
        return 'سؤال عن مندوب';
      case MessageType.stats:
        return 'إحصائيات';
      case MessageType.general:
        return 'سؤال عام';
      case MessageType.image:
        return 'صورة روشتة';
    }
  }

  String get hint {
    switch (this) {
      case MessageType.drug:
        return 'اكتب اسم الدواء...';
      case MessageType.alternative:
        return 'اكتب اسم الدواء للبحث عن بديل...';
      case MessageType.shortage:
        return 'اكتب اسم الدواء الناقص...';
      case MessageType.debt:
        return 'اكتب اسم العميل أو الأمر...';
      case MessageType.rep:
        return 'اكتب سؤالك عن المندوبين...';
      case MessageType.stats:
        return 'اكتب طلبك للإحصائيات...';
      case MessageType.general:
        return 'اكتب سؤالك هنا...';
      case MessageType.image:
        return 'أرفق صورة الروشتة...';
    }
  }

  List<String> get sampleCommands {
    switch (this) {
      case MessageType.drug:
        return ['باراسيتامول', 'بروفين 400', 'أدول'];
      case MessageType.alternative:
        return ['بديل بروفين', 'بديل ادول', 'عوض عن'];
      case MessageType.shortage:
        return ['أضف ناقص', 'سجل دواء ناقص', 'ضيف'];
      case MessageType.debt:
        return ['الديون', 'دين احمد', 'ضيف دين'];
      case MessageType.rep:
        return ['المندوبين', 'أضف مندوب', 'تقييم'];
      case MessageType.stats:
        return ['ملخص', 'إحصائيات', 'تقرير'];
      case MessageType.general:
        return ['مساعدة', 'ازاي أستخدم', 'الأوامر'];
      case MessageType.image:
        return [];
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ System Prompt المحسّن لحكيم
// ════════════════════════════════════════════════════════════════════════════

String getPharmacistSystemPrompt(
    {String? pharmacyName, MessageType? messageType}) {
  String typeContext = '';
  if (messageType != null) {
    switch (messageType) {
      case MessageType.drug:
        typeContext =
            '\n═══ السياق الحالي: المستخدم يسأل عن دواء محدد ═══\nقدم معلومات شاملة عن الدواء.';
        break;
      case MessageType.alternative:
        typeContext =
            '\n═══ السياق الحالي: المستخدم يريد بديل لدواء ═══\nقدم بدائل بنفس المادة الفعالة.';
        break;
      case MessageType.shortage:
        typeContext =
            '\n═══ السياق الحالي: المستخدم يضيف دواء ناقص ═══\nساعده في إضافة الدواء بشكل صحيح.';
        break;
      case MessageType.debt:
        typeContext =
            '\n═══ السياق الحالي: سؤال عن ديون/مالية ═══\nقدم معلومات مالية دقيقة.';
        break;
      case MessageType.rep:
        typeContext =
            '\n═══ السياق الحالي: سؤال عن مندوبين ═══\nقدم معلومات عن المندوبين.';
        break;
      case MessageType.stats:
        typeContext =
            '\n═══ السياق الحالي: طلب إحصائيات ═══\nقدم تحليلات وتقارير.';
        break;
      case MessageType.general:
        typeContext = '\n═══ السياق الحالي: سؤال عام ═══\nأجب بشكل شامل ومفصل.';
        break;
      case MessageType.image:
        typeContext =
            '\n═══ السياق الحالي: تحليل صورة/روشتة ═══\nاستخرج الأدوية من الصورة.';
        break;
    }
  }

  return '''
أنت "حكيم" - مساعد صيدلي محترف ذكي متخصص في السوق المصري والعربي.

$typeContext

═══════════════════════════════════════════════════════════════════════════════
▌ شخصيتك:
═══════════════════════════════════════════════════════════════════════════════
• صيدلي خبير معتمد، تتحدث بالعربية الفصحى السهلة والمفهومة
• ودود ومهني، تستخدم الإيموجي بشكل مناسب وذي معنى
• تقدم نصائح دقيقة ومفيدة بناءً على معرفتك الصيدلانية
• حريص على تقديم المعلومات الصحيحة مع ذكر مصدرها إن أمكن
• تستجيب بسرعة وفعالية لكل استفسار

═══════════════════════════════════════════════════════════════════════════════
▌ معرفتك الصيدلانية:
═══════════════════════════════════════════════════════════════════════════════
• الأدوية المصرية والعربية الشائعة: الأسماء التجارية، الشركات المصنعة
• المواد الفعالة والتراكيب الدوائية
• البدائل المثيلة (نفس المادة الفعالة، شركات مختلفة)
• التفاعلات الدوائية الشائعة والتحذيرات المهمة
• معلومات عامة عن الجرعات والاستخدامات
• أسعار تقريبية للأدوية الشائعة في السوق المصري

═══════════════════════════════════════════════════════════════════════════════
▌ قدراتك الأساسية:
═══════════════════════════════════════════════════════════════════════════════

📋 إدارة النواقص:
• إضافة أدوية ناقصة للقائمة
• البحث عن حالة النواقص
• تعليم الأدوية المتوفرة
• تحليل أنماط النواقص المتكررة
• إرسال النواقص للمندوبين

💊 البحث والاستفسار:
• البحث عن معلومات الأدوية
• اقتراح البدائل المثيلة
• البحث في منصات الأدوية المختلفة
• مقارنة الأسعار والتوفر

💰 إدارة المالية:
• عرض ديون العملاء
• إضافة ديون جديدة
• تسجيل المدفوعات
• تتبع الاستحقاقات

👥 المندوبين:
• عرض قائمة المندوبين
• تقييم الأداء
• تتبع ردود المندوبين

📊 التقارير:
• إحصائيات يومية/أسبوعية/شهرية
• تحليل أداء الصيدلية
• تقارير الديون والمبيعات

═══════════════════════════════════════════════════════════════════════════════
▌ قواعد الرد المهمة (اتبعها بدقة):
═══════════════════════════════════════════════════════════════════════════════

1️⃣ هيكل الرسالة:
   • ابدأ دائماً برمز يدل على نوع المحتوى:
     - 💊 للأدوية والمعلومات الدوائية
     - 🔍 للبحث والنتائج
     - 📋 للقوائم والتقارير
     - 💰 للمالية والديون
     - 👥 للمندوبين والعملاء
     - ✅ للتأكيد والنجاح
     - ⚠️ للتحذيرات
     - 🔄 للبدائل
     - 💡 للنصائح
   • قسّم المعلومات الكبيرة لنقاط واضحة باستخدام •
   • اختم دائماً بنصيحة مفيدة (💡)

2️⃣ عند ذكر دواء، قدم:
   • الاسم التجاري والاسم العلمي
   • المادة الفعالة والتركيز
   • الشركة المصنعة
   • الاستخدامات الشائعة
   • التحذيرات والتفاعلات المهمة
   • البدائل المتاحة (إن وجدت)

3️⃣ عند السؤال عن السعر:
   • اذكر أن السعر تقريبي ويختلف حسب الصيدلية والموقع
   • قدم نطاق سعري تقريبي

4️⃣ عند السؤال عن توفر دواء:
   • اذكر أن التوفر يتغير باستمرار
   • اقترح البحث في منصات مختلفة
   • قدم البدائل المتاحة

5️⃣ عند الشكوى أو المشكلة:
   • استمع باهتمام وقدم حلول عملية

6️⃣ الأمور المحظورة:
   • ❌ لا تقدم نصائح طبية بديلاً عن الطبيب
   • ❌ لا تذكر أسعار نهائية (قد تتغير)
   • ❌ لا تؤكد توفر دواء إلا إذا كان في قاعدة البيانات

═══════════════════════════════════════════════════════════════════════════════
▌ سياق التطبيق:
═══════════════════════════════════════════════════════════════════════════════
• اسم الصيدلية: ${pharmacyName ?? 'صيدليتك'}
• العملة: جنيه مصري (ج.م)
• المنطقة: مصر
• نوع التطبيق: صيدلية تجزئة (Retail Pharmacy)

═══════════════════════════════════════════════════════════════════════════════
▌ ملخص القواعد النهائية:
═══════════════════════════════════════════════════════════════════════════════
✅ ابدأ برمز يدل على نوع المحتوى
✅ قدم معلومات شاملة ومنظمة
✅ اختم بنصيحة مفيدة
✅ استخدم الإيموجي بشكل مناسب
❌ لا تقدم نصائح طبية بديلة للطبيب
❌ لا تذكر أسعار نهائية
''';
}

/// ▌ System Prompt المختصر للـ autocomplete
String getDrugSuggestionsPrompt() {
  return '''
أنت قاموس أدوية مصري وعربي متخصص.
مهمتك: اقتراح أسماء أدوية مطابقة أو مشابهة للاسم المطلوب.
القواعد:
• أعد فقط أسماء الأدوية (اسم تجاري واحد لكل سطر)
• بدون أرقام أو ترقيم أو شروحات
• بدون تكرار
• من 3-8 نتائج كحد أقصى
''';
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ قاموس المعلومات الدوائية المفصّلة (من v2)
// ════════════════════════════════════════════════════════════════════════════
const Map<String, Map<String, String>> _detailedDrugInfo = {
  'paracetamol': {
    'arName': 'باراسيتامول (أسيتامينوفين)',
    'drugClass': 'مسكن ألم وخافض حرارة',
    'indications':
        '• الألم الخفيف إلى المتوسط\n• الصداع\n• آلام الأسنان\n• الحمى\n• آلام المفاصل والعضلات',
    'dosage':
        '• البالغون: 500-1000 مجم كل 4-6 ساعات (حد أقصى 4 جم/يوم)\n• الأطفال: حسب الوزن',
    'sideEffects':
        '• نادراً في الجرعات العادية\n• قد يسبب مشاكل كبدية في الجرعات العالية\n• حساسية جلدية نادرة',
    'contraindications': '• مرض الكبد الشديد\n• الحساسية للباراسيتامول',
    'interactions': '• وارفارين (زيادة ميوعة الدم)\n• كحول (زيادة خطر الكبد)',
  },
  'ibuprofen': {
    'arName': 'إيبوبروفين',
    'drugClass': 'مضاد التهاب غير ستيرويدي (NSAID)',
    'indications':
        '• الألم والالتهاب\n• الصداع النصفي\n• آلام الأسنان\n• الحمى\n• آلام الدورة الشهرية\n• التهاب المفاصل',
    'dosage':
        '• البالغون: 200-400 مجم كل 4-6 ساعات (حد أقصى 1200 مجم/يوم)\n• مع الطعام لتقليل اضطراب المعدة',
    'sideEffects':
        '• اضطراب المعدة\n• قرحة معدية\n• دوخة\n• صداع\n• احتباس السوائل',
    'contraindications':
        '• قرحة معدية نشطة\n• فشل كلوي\n• الحمل في آخر 3 أشهر\n• حساسية للأسبرين',
    'interactions': '• مميعات الدم\n• بعض أدوية الضغط\n• ميثوتريكسات',
  },
  'amoxicillin': {
    'arName': 'أموكسيسيلين',
    'drugClass': 'مضاد حيوي من مجموعة البنسيلين',
    'indications':
        '• التهابات الجهاز التنفسي\n• التهاب الحلق\n• التهاب الأذن الوسطى\n• التهابات المسالك البولية\n• عدوى الجلد',
    'dosage': '• 250-500 مجم كل 8 ساعات\n• مع أو بدون طعام',
    'sideEffects': '• إسهال\n• غثيان\n• طفح جلدي\n• حساسية (يجب إيقاف الدواء)',
    'contraindications': '• حساسية للبنسيلين',
    'interactions': '• ميثوتريكسات\n• وارفارين\n• موانع الحمل الفموية',
  },
  'omeprazole': {
    'arName': 'أوميبرازول',
    'drugClass': 'مثبط مضخة البروتون (PPI)',
    'indications':
        '• قرحة المعدة والاثني عشر\n• ارتجاع المريء\n• جرثومة المعدة\n• عسر الهضم',
    'dosage': '• 20-40 مجم يومياً قبل الإفطار\n• عادة لمدة 4-8 أسابيع',
    'sideEffects':
        '• صداع\n• إسهال أو إمساك\n• غثيان\n• نقص فيتامين B12 على المدى الطويل',
    'contraindications': '• حساسية لمثبطات مضخة البروتون',
    'interactions': '• كلوبيدوغريل\n• ميثوتريكسات',
  },
  'metformin': {
    'arName': 'ميتفورمين',
    'drugClass': 'مضاد السكري من مجموعة البيغوانيد',
    'indications':
        '• السكري من النوع الثاني\n• مقاومة الأنسولين\n• السمنة المصاحبة للسكري',
    'dosage':
        '• ابدأ بـ 500 مجم مرتين يومياً\n• زيادة تدريجية حسب السكر\n• مع الطعام',
    'sideEffects':
        '• اضطراب المعدة\n• إسهال (يقل مع الوقت)\n• نقص فيتامين B12\n• نادراً: حماض لبني',
    'contraindications': '• فشل كلوي حاد\n• حماض كيتوني سكري',
    'interactions': '• مواد التباين (أشعة)\n• بعض الأدوية تؤثر على الكلى',
  },
  'aspirin': {
    'arName': 'أسبرين (حمض أسيتيل ساليسيليك)',
    'drugClass': 'مضاد التهاب غير ستيرويدي + مضاد صفائح',
    'indications':
        '• الألم والحمى\n• الصداع\n• منع الجلطات (جرعة منخفضة)\n• منع النوبات القلبية',
    'dosage': '• للألم: 325-650 مجم كل 4-6 ساعات\n• للقلب: 81-325 مجم يومياً',
    'sideEffects':
        '• اضطراب المعدة\n• قرحة معدية\n• نزيف\n• طنين في الأذن (بجرعات عالية)',
    'contraindications': '• حساسية للأسبرين\n• قرحة نشطة\n• نزيف نشط',
    'interactions': '• مميعات الدم (خطر نزيف)\n• NSAID أخرى',
  },
  'amlodipine': {
    'arName': 'أملوديبين',
    'drugClass': 'حاصر قنوات الكالسيوم',
    'indications': '• ارتفاع ضغط الدم\n• الذبحة الصدرية\n• أمراض الشرايين',
    'dosage': '• 5-10 مجم يومياً\n• ابدأ بـ 5 مجم لكبار السن',
    'sideEffects': '• تورم الكاحلين\n• صداع\n• احمرار الوجه\n• دوخة',
    'contraindications': '• صدمة قلبية\n• حساسية للأملوديبين',
    'interactions': '• سيمفاستاتين (حد للجرعة)\n• مثبطات CYP3A4',
  },
  'losartan': {
    'arName': 'لوسارتان',
    'drugClass': 'حاصر مستقبل الإنجيوتنسين II',
    'indications': '• ارتفاع ضغط الدم\n• حماية الكلى في السكري\n• فشل القلب',
    'dosage': '• 25-50 مجم يومياً\n• يمكن زيادة إلى 100 مجم',
    'sideEffects': '• دوخة\n• صداع\n• ارتفاع البوتاسيوم',
    'contraindications': '• الحمل\n• حساسية لـ ARBs',
    'interactions':
        '• مدرات البول\n• مكملات البوتاسيوم\n• NSAID (تقلل الفعالية)',
  },
};

// ════════════════════════════════════════════════════════════════════════════
// ▌ قاموس ترجمة المصطلحات الصيدلانية الإنجليزية (من v2)
// ════════════════════════════════════════════════════════════════════════════
const Map<String, String> _pharmaceuticalTranslations = {
  // أسماء الأدوية الشائعة
  'paracetamol': 'باراسيتامول (أسيتامينوفين)',
  'acetaminophen': 'باراسيتامول (أسيتامينوفين)',
  'panadol': 'باراسيتامول (أدول)',
  'advil': 'إيبوبروفين (بروفين)',
  'brufen': 'إيبوبروفين (بروفين)',
  'ibuprofen': 'إيبوبروفين (بروفين)',
  'aspirin': 'أسبرين (حمض أسيتيل ساليسيليك)',
  'voltaren': 'ديكلوفيناك (فولتارين)',
  'diclofenac': 'ديكلوفيناك',
  'augmentin': 'أموكسيسيلين/كلافيولانيك أسيد (أوجمنتين)',
  'amoxicillin': 'أموكسيسيلين',
  'azithromycin': 'أزيثرومايسين (أزيماك)',
  'ciprofloxacin': 'سيبروفلوكساسين (سيبروكسين)',
  'omeprazole': 'أوميبرازول (لوسك)',
  'metformin': 'ميتفورمين (جلوكوفاج)',
  'ranitidine': 'رانيتيدين',
  'furosemide': 'فوروسيميد',
  // أشكال الدواء
  'tablet': 'قرص',
  'capsule': 'كبسولة',
  'syrup': 'شراب',
  'suspension': 'معلق',
  'injection': 'حقن/محلول للحقن',
  'cream': 'كريم',
  'ointment': 'مرهم',
  'gel': 'جل',
  'drops': 'قطرات',
  'inhaler': 'جهاز استنشاق',
  'patch': 'لصقة',
  // تصنيفات دوائية
  'nsaid': 'مضاد التهاب غير ستيرويدي',
  'antibiotic': 'مضاد حيوي',
  'antiviral': 'مضاد فيروسي',
  'antifungal': 'مضاد فطريات',
  'antihistamine': 'مضاد هيستامين',
  'analgesic': 'مسكن',
  'antipyretic': 'خافض حرارة',
  'antacid': 'مضاد حموضة',
  'anticoagulant': 'مميع دم',
  'beta blocker': 'حاصر بيتا',
  // معلومات دوائية
  'indication': 'دواعي الاستعمال',
  'contraindication': 'موانع الاستعمال',
  'dosage': 'الجرعة',
  'side effect': 'أثر جانبي',
  'side effects': 'آثار جانبية',
  'drug interaction': 'تفاعل دوائي',
  'precaution': 'احتياط',
  'warning': 'تحذير',
  'storage': 'التخزين',
  'mechanism of action': 'آلية العمل',
  'half-life': 'نصف العمر',
  'bioavailability': 'التوافر الحيوي',
  // أمراض شائعة
  'hypertension': 'ارتفاع ضغط الدم',
  'hypotension': 'انخفاض ضغط الدم',
  'diabetes': 'السكري',
  'asthma': 'الربو',
  'infection': 'عدوى',
  'inflammation': 'التهاب',
  'pain': 'ألم',
  'fever': 'حمى',
  'headache': 'صداع',
  'nausea': 'غثيان',
  'vomiting': 'قيء',
  'diarrhea': 'إسهال',
  'constipation': 'إمساك',
  'allergy': 'حساسية',
};

// ════════════════════════════════════════════════════════════════════════════
// ▌ خدمة الشات بوت الرئيسية - المدمجة v4.0
// ════════════════════════════════════════════════════════════════════════════
class ChatService {
  static final ChatService instance = ChatService._();
  ChatService._();

  // ── تطبيع النص العربي ──────────────────────────────────────────────────
  String _normalize(String s) => s
      .replaceAll(RegExp(r'[إأآا]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[؟!.,،]'), '')
      .toLowerCase()
      .trim();

  // ── تصنيف النية ──────────────────────────────────────────────────
  ChatIntent _classify(String text, {MessageType? forcedType}) {
    if (forcedType != null) {
      switch (forcedType) {
        case MessageType.drug:
          return ChatIntent.drugInquiry;
        case MessageType.alternative:
          return ChatIntent.findAlternative;
        case MessageType.shortage:
          return ChatIntent.addShortage;
        case MessageType.debt:
          return ChatIntent.showDebts;
        case MessageType.rep:
          return ChatIntent.showReps;
        case MessageType.stats:
          return ChatIntent.showStats;
        case MessageType.general:
          return ChatIntent.generalQuestion;
        case MessageType.image:
          return ChatIntent.addShortagesFromImage;
      }
    }

    final n = _normalize(text);

    if (RegExp(r'(اضف|أضف|ضيف|سجل|دخل)').hasMatch(n) &&
        RegExp(r'(ناقص|نواقص|دواء|عقار|دوا)').hasMatch(n))
      return ChatIntent.addShortage;
    if (RegExp(r'(تم|وجد|اتوفر|كامل|غطي|غطى|اتغطى|توفر)').hasMatch(n))
      return ChatIntent.markCovered;
    if (RegExp(r'(معلق|انتظار)').hasMatch(n) &&
        RegExp(r'(نواقص|دواء)').hasMatch(n))
      return ChatIntent.showPendingShortages;
    if (RegExp(r'(نواقص|الناقص|نواقصي)').hasMatch(n) &&
        !RegExp(r'(اضف|ضيف|سجل)').hasMatch(n)) return ChatIntent.showShortages;

    if (RegExp(r'(ديون|الدين|مدين|مديون|دين)').hasMatch(n)) {
      final words = n.split(' ').where((w) => w.length > 2).toList();
      const stopDebt = {
        'ديون',
        'الدين',
        'مدين',
        'مديون',
        'دين',
        'كل',
        'اجمالي',
        'مجموع'
      };
      final hasName = words.any((w) => !stopDebt.contains(w));
      return hasName ? ChatIntent.checkCustomerDebt : ChatIntent.showDebts;
    }

    if (RegExp(r'(مندوب|مندوبين)').hasMatch(n)) return ChatIntent.showReps;
    if (RegExp(r'(احصاء|احصائيات|تقرير|ملخص|اليوم|الوضع)').hasMatch(n))
      return ChatIntent.showStats;
    if (RegExp(r'(api|ايبيآي|مفتاح|ذكاء)').hasMatch(n))
      return ChatIntent.apiSettings;
    if (RegExp(r'(بديل|بدائل|بدل|عوض)').hasMatch(n))
      return ChatIntent.findAlternative;
    if (RegExp(r'(تحليل|انماط|نمط|تكرار|متكرر)').hasMatch(n))
      return ChatIntent.analyzePatterns;
    if (RegExp(r'(ابحث|دور|سعر|اسعار|اطلب|طلب|منصة|منصات|شركة|شركات|اونلاين)')
            .hasMatch(n) &&
        !RegExp(r'(ناقص|نواقص|اضف|معلق)').hasMatch(n))
      return ChatIntent.searchPlatform;
    if (RegExp(r'(مساعده|مساعدة|ايه|ازاي|كيف|ايش|امر|اوامر)').hasMatch(n))
      return ChatIntent.help;
    if (RegExp(r'(اعمل|ضيف|سجل|انشئ|أنشئ)').hasMatch(n) &&
        RegExp(r'(حساب|عميل|زبون)').hasMatch(n)) return ChatIntent.addCustomer;
    if (RegExp(r'(ضيف|اضف|سجل|استخرج)').hasMatch(n) &&
        RegExp(r'(الاصناف|النواقص|الادوية|الادويه|الصور|الصوره|الصورة|روشته|روشتة|الصنف|صنف|صوره)')
            .hasMatch(n)) return ChatIntent.addShortagesFromImage;

    if (n.length > 2) return ChatIntent.smartChat;
    return ChatIntent.unknown;
  }

  // ── تنفيذ الأمر ──────────────────────────────────────────────────
  Future<ChatResponse> execute(String text,
      {List<String>? filePaths, MessageType? messageType}) async {
    final intent = _classify(text, forcedType: messageType);

    if (intent == ChatIntent.addShortagesFromImage)
      return _extractAndAddItemsFromImage(text, filePaths);
    if (filePaths != null &&
        filePaths.isNotEmpty &&
        intent != ChatIntent.addShortagesFromImage) {
      return _searchViaApi(text,
          filePaths: filePaths, messageType: messageType);
    }

    switch (intent) {
      case ChatIntent.addShortage:
        return _handleAddShortage(text);
      case ChatIntent.showShortages:
        return _handleShowShortages();
      case ChatIntent.showPendingShortages:
        return _handleShowShortages(status: 'pending');
      case ChatIntent.markCovered:
        return _handleMarkCovered(text);
      case ChatIntent.checkCustomerDebt:
        return _handleCustomerDebt(text);
      case ChatIntent.showDebts:
        return _handleShowDebts();
      case ChatIntent.showReps:
        return _handleShowReps();
      case ChatIntent.showStats:
        return _handleShowStats();
      case ChatIntent.apiSettings:
        return ChatResponse(
            text: _apiHelpText(), intent: ChatIntent.apiSettings);
      case ChatIntent.help:
        return ChatResponse(text: _helpText(), intent: ChatIntent.help);
      case ChatIntent.findAlternative:
        return _handleFindAlternative(text);
      case ChatIntent.analyzePatterns:
        return _handleAnalyzePatterns();
      case ChatIntent.searchPlatform:
        return _handleSearchPlatform(text);
      case ChatIntent.addCustomer:
        return _handleAddCustomer(text);
      case ChatIntent.drugInquiry:
        return _handleDrugInquiry(text);
      case ChatIntent.generalQuestion:
        return _handleSmartChat(text, messageType: messageType);
      case ChatIntent.smartChat:
        return _handleSmartChat(text, messageType: messageType);
      default:
        return _handleSearchDrug(text);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ محادثة ذكية
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleSmartChat(String text,
      {MessageType? messageType}) async {
    final localResponse = await _searchLocalKnowledge(text);
    if (localResponse != null) return localResponse;
    return _searchViaApi(text, messageType: messageType);
  }

  Future<ChatResponse?> _searchLocalKnowledge(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final savedFiles = prefs.getStringList('custom_api_files') ?? [];
    if (savedFiles.isEmpty) return null;
    final localRes = await _searchLocalFiles(query, savedFiles);
    if (localRes.success && localRes.text.contains('📄')) return localRes;
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ استفسار عن دواء محدد - مع القاموس المفصّل (v2) + القاموس المحلي (v1)
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleDrugInquiry(String text) async {
    final n = _normalize(text);
    final stopWords = {'ما', 'هو', 'عن', 'دواء', 'عقار', 'معلومات'};
    final words = n
        .split(' ')
        .where((w) => !stopWords.contains(w) && w.length > 2)
        .toList();
    final drugName = words.isNotEmpty ? words.join(' ') : text;

    // ▌ 1️⃣ البحث في القاموس المفصّل (v2)
    final detailedKey = _detailedDrugInfo.keys.firstWhere(
      (k) =>
          k.contains(drugName.toLowerCase()) ||
          drugName.toLowerCase().contains(k),
      orElse: () => '',
    );
    if (detailedKey.isNotEmpty) {
      final info = _detailedDrugInfo[detailedKey]!;
      return ChatResponse(
        text: '''
💊 ${info['arName']} ($detailedKey)

━━━━━━━━━━━━━━━━━━━━━━
📌 التصنيف: ${info['drugClass']}
━━━━━━━━━━━━━━━━━━━━━━
📋 دواعي الاستعمال:
${info['indications']}
━━━━━━━━━━━━━━━━━━━━━━
💊 الجرعة:
${info['dosage']}
━━━━━━━━━━━━━━━━━━━━━━
⚠️ الآثار الجانبية:
${info['sideEffects']}
━━━━━━━━━━━━━━━━━━━━━━
⛔ موانع الاستعمال:
${info['contraindications']}
━━━━━━━━━━━━━━━━━━━━━━
🔬 التفاعلات الدوائية:
${info['interactions']}
━━━━━━━━━━━━━━━━━━━━━━

💡 هذه المعلومات للاسترشاد فقط. استشر طبيبك أو الصيدلي دائماً.
''',
        intent: ChatIntent.drugInquiry,
      );
    }

    // ▌ 2️⃣ البحث في القاموس المحلي (v1)
    final dictionary = await _loadDictionary();
    if (dictionary.isNotEmpty) {
      final matches = dictionary
          .where((drug) {
            final en = drug['enName']?.toString().toLowerCase() ?? '';
            final ar = drug['arName']?.toString().toLowerCase() ?? '';
            return en.contains(drugName.toLowerCase()) ||
                ar.contains(drugName.toLowerCase());
          })
          .take(5)
          .toList();

      if (matches.isNotEmpty) {
        final drug = matches.first;
        final enName = drug['enName'] ?? '';
        final arName = drug['arName'] ?? '';
        final active = drug['activeIngredient'] ?? '';
        final company = drug['company'] ?? '';
        final form = drug['form'] ?? '';

        String details = '💊 $enName';
        if (arName.toString().isNotEmpty) details += ' ($arName)';
        details += '\n\n';
        if (active.toString().isNotEmpty)
          details += '🧪 المادة الفعالة: $active\n';
        if (company.toString().isNotEmpty) details += '🏭 الشركة: $company\n';
        if (form.toString().isNotEmpty) details += '💊 الشكل: $form\n';
        details += '\n💡 اكتب "بديل $enName" للبحث عن بدائل.';

        return ChatResponse(text: details, intent: ChatIntent.drugInquiry);
      }
    }

    // ▌ 3️⃣ استخدام API
    return _searchViaApi(text);
  }

  // ── إضافة ناقص ──────────────────────────────────────────────────
  Future<ChatResponse> _handleAddShortage(String text) async {
    final n = _normalize(text);
    const stopWords = {
      'اضف',
      'أضف',
      'ضيف',
      'سجل',
      'دخل',
      'ناقص',
      'نواقص',
      'دواء',
      'عقار',
      'في',
      'الى',
      'ل',
      'دوا'
    };
    final words = n
        .split(' ')
        .where((w) => !stopWords.contains(w) && w.length > 1)
        .toList();
    if (words.isEmpty) {
      return ChatResponse(
        text:
            '❓ كيف أضيف دواء للنواقص؟\n\n💡 اكتب: "أضف دواء [اسم الدواء]"\n\n📌 مثال: "أضف دواء باراسيتامول"',
        intent: ChatIntent.addShortage,
        success: false,
      );
    }
    final drugName = words.join(' ');
    await DatabaseHelper.instance.insertShortage({
      'name': drugName,
      'company': 'غير محدد',
      'quantity': 1,
      'status': 'pending',
      'is_urgent': 0,
      'notes': 'أُضيف عن طريق المساعد الذكي',
    });
    return ChatResponse(
      text: '✅ تم إضافة "$drugName" للنواقص بنجاح!\n\n'
          '📋 يمكنك الآن:\n• إرساله للمندوبين من شاشة النواقص\n'
          '• تعليمه كمتوفر عند توفره\n• البحث عن بديل له\n\n'
          '💡 أرفق صورة لإضافة عدة أدوية دفعة واحدة.',
      intent: ChatIntent.addShortage,
      success: true,
      actionData: {'drug': drugName, 'action': 'add_shortage'},
    );
  }

  // ── عرض النواقص ──────────────────────────────────────────────────
  Future<ChatResponse> _handleShowShortages({String? status}) async {
    final shortages =
        await DatabaseHelper.instance.getShortages(status: status);
    if (shortages.isEmpty) {
      return ChatResponse(
        text: status == 'pending'
            ? '🎉 لا توجد نواقص معلقة حالياً!\n\n✨ كل الأدوية متوفرة في السوق.'
            : '📭 لا توجد نواقص مسجلة حالياً.',
        intent: ChatIntent.showShortages,
      );
    }
    const statusIcons = {
      'pending': '⏳',
      'covered': '✅',
      'offered': '📦',
      'stubborn': '🔴'
    };
    const statusLabels = {
      'pending': 'معلق',
      'covered': 'متوفر',
      'offered': 'مُعروض',
      'stubborn': 'عنيد'
    };
    final label = status == 'pending' ? 'المعلقة' : 'الكل';
    final lines = shortages.take(10).map((s) {
      final icon = statusIcons[s['status']] ?? '💊';
      final statusLabel = statusLabels[s['status']] ?? s['status'];
      return '$icon ${s['name']} | ${s['company']}\n   📌 الحالة: $statusLabel';
    }).join('\n\n');
    final more = shortages.length > 10
        ? '\n\n...و ${shortages.length - 10} أدوية أخرى'
        : '';
    return ChatResponse(
      text: '📋 قائمة النواقص $label (${shortages.length}):\n\n$lines$more',
      intent: ChatIntent.showShortages,
    );
  }

  // ── إضافة عميل ──────────────────────────────────────────────────
  Future<ChatResponse> _handleAddCustomer(String text) async {
    final patterns = [
      RegExp(r'(?:باسم|اسم|اسمه)\s+([^\s\d]+(?:\s+[^\s\d]+)*)'),
      RegExp(r'(?:عميل\s+(?:اسمه|مسمى)?)\s*([^\s\d]+(?:\s+[^\s\d]+)*)',
          caseSensitive: false),
      RegExp(
          r'(?:اعمل\s+(?:حساب|عميل)|أنشئ\s+(?:حساب|عميل))\s*(?:باسم\s+)?([^\s\d]+(?:\s+[^\s\d]+)*)',
          caseSensitive: false),
      RegExp(r'(?:أضف|ضيف)\s+(?:عميل\s+)?([^\s\d]+(?:\s+[^\s\d]+)*)',
          caseSensitive: false),
    ];

    String? extractedName;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        extractedName = match.group(1)!.trim();
        break;
      }
    }

    if (extractedName == null || extractedName.isEmpty) {
      final words = text.split(RegExp(r'[\s\،\,\.]+'));
      for (final word in words) {
        final clean = word.trim();
        if (clean.length >= 2 &&
            clean.length <= 15 &&
            !RegExp(r'^(عميل|باسم|اسم|اعمل|أنشئ|أضف|ضيف|حساب|رقم|تليفون|موبايل)$',
                    caseSensitive: false)
                .hasMatch(clean) &&
            !RegExp(r'^[\d\-]+$').hasMatch(clean)) {
          extractedName = clean;
          break;
        }
      }
    }

    final phoneMatch = RegExp(r'[\d\-\+]{8,15}').firstMatch(text);
    final phone = phoneMatch?.group(0)?.trim() ?? '';

    if (extractedName == null || extractedName.isEmpty) {
      return ChatResponse(
        text: '❓ أحتاج اسم العميل!\n\n💡 اكتب: "أضف عميل [الاسم]"',
        intent: ChatIntent.addCustomer,
        success: false,
      );
    }

    try {
      await DatabaseHelper.instance.insertCustomer(
          {'name': extractedName, 'phone': phone, 'address': ''});
      return ChatResponse(
        text:
            '✅ تم إنشاء حساب العميل "$extractedName"${phone.isNotEmpty ? ' برقم $phone' : ''} بنجاح!',
        intent: ChatIntent.addCustomer,
        success: true,
      );
    } catch (e) {
      return ChatResponse(
        text:
            '⚠️ حدث خطأ أثناء إضافة العميل "$extractedName".\n\n💡 تأكد من قاعدة البيانات وحاول مرة أخرى.',
        intent: ChatIntent.addCustomer,
        success: false,
      );
    }
  }

  // ── استخراج النواقص من صورة ──────────────────────────────────────────────────
  Future<ChatResponse> _extractAndAddItemsFromImage(
      String text, List<String>? filePaths) async {
    final prefs = await SharedPreferences.getInstance();
    final customKey = prefs.getString('custom_api_key') ?? '';
    final customType = prefs.getString('custom_api_type') ?? 'openai';

    if (filePaths == null || filePaths.isEmpty) {
      return ChatResponse(
        text: '📷 أحتاج صورة لاستخراج الأدوية!\n\n'
            '💡 أرفق صورة الروشتة أو قائمة الأدوية مع رسالتك.\n\n'
            '📌 نصائح لصورة أفضل:\n• تأكد من وضوح النص\n• استخدم إضاءة جيدة\n• صور بشكل مستقيم',
        intent: ChatIntent.addShortagesFromImage,
        success: false,
      );
    }

    // ▌ محاولة استخدام Gemini
    if (customKey.isNotEmpty && customType == 'gemini') {
      try {
        final model =
            GenerativeModel(model: 'gemini-1.5-flash', apiKey: customKey);
        const prompt = '''استخرج جميع أسماء الأدوية أو الأصناف من هذه الصورة.
أعدهم في قائمة JSON بالشكل:
[{"name": "اسم الدواء", "company": "اسم الشركة", "quantity": 1}]
⚠️ أرجع فقط مصفوفة JSON بدون أي نص آخر''';

        final parts = <Part>[TextPart(prompt)];
        for (final path in filePaths) {
          if (!File(path).existsSync()) continue;
          final bytes = File(path).readAsBytesSync();
          final ext = path.split('.').last.toLowerCase();
          String mime = 'image/jpeg';
          if (ext == 'png') mime = 'image/png';
          if (ext == 'pdf') mime = 'application/pdf';
          parts.add(DataPart(mime, bytes));
        }

        final response = await model.generateContent([Content.multi(parts)]);
        final resText = response.text ?? '';
        final jsonMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(resText);
        if (jsonMatch != null) {
          final List<dynamic> items = jsonDecode(jsonMatch.group(0)!);
          int added = 0;
          final buffer = StringBuffer();
          for (final item in items) {
            final name = item['name']?.toString() ?? '';
            if (name.isEmpty) continue;
            final company = item['company']?.toString() ?? 'غير محدد';
            final quantity =
                int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
            await DatabaseHelper.instance.insertShortage({
              'name': name,
              'company': company,
              'quantity': quantity,
              'status': 'pending',
              'is_urgent': 0,
              'notes': 'مستخرج من صورة عبر ذكاء اصطناعي',
            });
            buffer.writeln(
                '💊 $name${company != 'غير محدد' ? ' | $company' : ''}');
            added++;
          }
          if (added > 0) {
            return ChatResponse(
              text:
                  '✅ تم استخراج وإضافة $added صنف للنواقص!\n\n${buffer.toString()}\n\n💡 راجع شاشة النواقص للتعديل أو الحذف.',
              intent: ChatIntent.addShortagesFromImage,
            );
          }
        }
      } catch (_) {}
    }

    // ▌ الاستخراج المحلي
    try {
      final textRecognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      int added = 0;
      final buffer = StringBuffer();
      for (final path in filePaths) {
        if (!File(path).existsSync()) continue;
        final ext = path.split('.').last.toLowerCase();
        if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp') {
          final inputImage = InputImage.fromFilePath(path);
          final recognizedText = await textRecognizer.processImage(inputImage);
          final lines = recognizedText.text.split('\n');
          for (var line in lines) {
            line = line.trim();
            if (line.isEmpty ||
                line.length <= 2 ||
                RegExp(r'^\d+$').hasMatch(line)) continue;
            if (line.toLowerCase().contains('total') ||
                line.toLowerCase().contains('discount')) continue;
            await DatabaseHelper.instance.insertShortage({
              'name': line,
              'company': 'غير محدد',
              'quantity': 1,
              'status': 'pending',
              'is_urgent': 0,
              'notes': 'مستخرج من صورة محلياً',
            });
            buffer.writeln('💊 $line');
            added++;
            if (added >= 20) break;
          }
        }
      }
      textRecognizer.close();
      if (added > 0) {
        return ChatResponse(
          text:
              '✅ تم استخراج $added سطر من الصورة:\n\n${buffer.toString()}\n\n⚠️ راجع الأسماء فقد تحتاج تعديل.',
          intent: ChatIntent.addShortagesFromImage,
        );
      }
    } catch (_) {}

    return ChatResponse(
      text:
          '❌ لم أجد نصوص واضحة في الصورة.\n\n💡 جرب صورة أوضح أو أضف الأدوية يدوياً.',
      intent: ChatIntent.addShortagesFromImage,
      success: false,
    );
  }

  // ── تعليم متوفر ──────────────────────────────────────────────────
  Future<ChatResponse> _handleMarkCovered(String text) async {
    final n = _normalize(text);
    const stop = {'تم', 'وجد', 'اتوفر', 'كامل', 'غطي', 'غطى', 'توفر', 'اتغطى'};
    final words =
        n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ كيف أحدد أن الدواء متوفر؟\n\n💡 اكتب: "تم توفير [اسم الدواء]"',
        intent: ChatIntent.markCovered,
        success: false,
      );
    }
    final drugName = words.join(' ');
    final db = await DatabaseHelper.instance.database;
    final results = await db.query('shortages',
        where: "name LIKE ? AND status != 'covered'",
        whereArgs: ['%$drugName%']);
    if (results.isEmpty) {
      return ChatResponse(
        text:
            '🔍 لم أجد "$drugName" في قائمة النواقص المعلقة.\n\n💡 قد يكون متوفراً بالفعل أو غير مضاف.',
        intent: ChatIntent.markCovered,
        success: false,
      );
    }
    for (final s in results) {
      await DatabaseHelper.instance
          .updateShortage(s['id'] as int, {'status': 'covered'});
    }
    return ChatResponse(
      text:
          '✅ تم تعليم "${results.first['name']}" كـ متوفر!\n\n📊 يمكنك الآن عرض النواقص المعلقة.',
      intent: ChatIntent.markCovered,
    );
  }

  // ── دين عميل ──────────────────────────────────────────────────
  Future<ChatResponse> _handleCustomerDebt(String text) async {
    final n = _normalize(text);
    const stop = {'ديون', 'دين', 'مدين', 'مديون', 'عميل', 'كام', 'بكام', 'فين'};
    final words =
        n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) return _handleShowDebts();
    final name = words.join(' ');
    final db = await DatabaseHelper.instance.database;
    final results = await db
        .query('customers', where: 'name LIKE ?', whereArgs: ['%$name%']);
    if (results.isEmpty) {
      return ChatResponse(
        text:
            '🔍 لم أجد عميل باسم "$name".\n\n💡 جرب كتابة الاسم بشكل مختلف أو اكتب "الديون".',
        intent: ChatIntent.checkCustomerDebt,
        success: false,
      );
    }
    final c = results.first;
    final debt = (c['total_debt'] as num).toDouble();
    final emoji = debt > 500
        ? '🔴'
        : debt > 0
            ? '🟡'
            : '✅';
    final status = debt > 500
        ? 'مرتفع جداً'
        : debt > 0
            ? 'معتدل'
            : 'منتهي';
    return ChatResponse(
      text:
          '$emoji العميل: ${c['name']}\n\n💰 الدين: ${debt.toStringAsFixed(2)} ج.م\n📱 ${c['phone'] ?? "غير محدد"}\n📌 الحالة: $status',
      intent: ChatIntent.checkCustomerDebt,
    );
  }

  // ── كل الديون ──────────────────────────────────────────────────
  Future<ChatResponse> _handleShowDebts() async {
    final customers = await DatabaseHelper.instance.getCustomers();
    final withDebt =
        customers.where((c) => (c['total_debt'] as num) > 0).toList();
    if (withDebt.isEmpty) {
      return ChatResponse(
          text: '🎉 لا توجد ديون حالياً!\n\n✨ جميع العملاء موفّقين.',
          intent: ChatIntent.showDebts);
    }
    final total = withDebt.fold<double>(
        0, (sum, c) => sum + (c['total_debt'] as num).toDouble());
    final lines = withDebt.take(8).map((c) {
      final debt = (c['total_debt'] as num).toDouble();
      final emoji = debt > 500
          ? '🔴'
          : debt > 0
              ? '🟡'
              : '✅';
      return '$emoji ${c['name']}: ${debt.toStringAsFixed(0)} ج.م';
    }).join('\n');
    return ChatResponse(
      text:
          '💰 الديون المتراكمة (${withDebt.length} عميل):\n\n$lines\n\n📊 الإجمالي: ${total.toStringAsFixed(2)} ج.م',
      intent: ChatIntent.showDebts,
    );
  }

  // ── المندوبين ──────────────────────────────────────────────────
  Future<ChatResponse> _handleShowReps() async {
    final reps = await DatabaseHelper.instance.getReps();
    if (reps.isEmpty) {
      return ChatResponse(
        text:
            '📭 لا يوجد مندوبين مسجلين.\n\n💡 أضف المندوبين من شاشة المندوبين للبدء.',
        intent: ChatIntent.showReps,
      );
    }
    final lines = reps.take(6).map((r) {
      final stars = '⭐' * (((r['rating'] as int?) ?? 3).clamp(1, 5));
      return '👤 ${r['name']} | ${r['company'] ?? "غير محدد"}\n   $stars | غطى ${r['total_covered'] ?? 0} صنف';
    }).join('\n\n');
    return ChatResponse(
        text: '👥 المندوبون المسجلون (${reps.length}):\n\n$lines',
        intent: ChatIntent.showReps);
  }

  // ── الإحصائيات ──────────────────────────────────────────────────
  Future<ChatResponse> _handleShowStats() async {
    final stats = await DatabaseHelper.instance.getShortageStats();
    final totalDebt = await DatabaseHelper.instance.getTotalDebt();
    final currency = await DatabaseHelper.instance.getCurrency();
    final rate = stats['total']! > 0
        ? ((stats['covered']! / stats['total']!) * 100).toStringAsFixed(0)
        : '0';
    return ChatResponse(
      text: '📊 ملخص الصيدلية:\n\n'
          '💊 النواقص: ${stats['total']} صنف\n'
          '   ⏳ معلق: ${stats['pending']}\n'
          '   ✅ متوفر: ${stats['covered']}\n'
          '   📦 مُعروض: ${stats['offered']}\n'
          '   🔴 عنيد: ${stats['stubborn']}\n\n'
          '📈 نسبة التغطية: $rate%\n\n'
          '💰 إجمالي الديون: ${totalDebt.toStringAsFixed(2)} $currency',
      intent: ChatIntent.showStats,
    );
  }

  // ── بدائل الأدوية ──────────────────────────────────────────────────
  Future<ChatResponse> _handleFindAlternative(String text) async {
    final n = _normalize(text);
    const stop = {'بديل', 'بدائل', 'بدل', 'عوض', 'لـ', 'ل', 'دواء', 'عقار'};
    final words =
        n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) {
      return ChatResponse(
        text:
            '❓ كيف أجد بديل لدواء؟\n\n💡 اكتب: "بديل [اسم الدواء]"\n\n📌 مثال: "بديل بروفين"',
        intent: ChatIntent.findAlternative,
        success: false,
      );
    }
    final drugName = words.join(' ');
    final dictionary = await _loadDictionary();
    if (dictionary.isEmpty) {
      return ChatResponse(
        text: '📖 القاموس فارغ!\n\n💡 ارفع قاموس الأدوية من الإعدادات أولاً.',
        intent: ChatIntent.findAlternative,
        success: false,
      );
    }
    final original = dictionary.where((d) {
      final en = d['enName']?.toString().toLowerCase() ?? '';
      final ar = d['arName']?.toString().toLowerCase() ?? '';
      return en.contains(drugName.toLowerCase()) ||
          ar.contains(drugName.toLowerCase());
    }).toList();
    if (original.isEmpty) {
      return ChatResponse(
        text:
            '🔍 لم أجد "$drugName" في القاموس.\n\n💡 جرب البحث في Google أو اسأل المندوبين.',
        intent: ChatIntent.findAlternative,
        success: false,
      );
    }
    final activeIngredient =
        original.first['activeIngredient']?.toString() ?? '';
    if (activeIngredient.isEmpty) {
      return ChatResponse(
        text:
            '🔍 "${original.first['enName']}" غير مسجل له مادة فعالة.\n\n💡 تواصل مع الموزّع.',
        intent: ChatIntent.findAlternative,
        success: false,
      );
    }
    final alternatives = dictionary
        .where((d) {
          final act = d['activeIngredient']?.toString().toLowerCase() ?? '';
          final en = d['enName']?.toString() ?? '';
          return act.contains(activeIngredient.toLowerCase()) &&
              en != original.first['enName'];
        })
        .take(8)
        .toList();
    if (alternatives.isEmpty) {
      return ChatResponse(
        text:
            '🔍 البديل لـ "${original.first['enName']}":\n\n🧪 المادة الفعالة: $activeIngredient\n\n❌ لا توجد بدائل في القاموس.',
        intent: ChatIntent.findAlternative,
      );
    }
    final lines = alternatives
        .map((d) =>
            '💊 ${d['enName']}${d['arName']?.toString().isNotEmpty == true ? " (${d['arName']})" : ""}')
        .join('\n');
    return ChatResponse(
      text:
          '🔄 بدائل "${original.first['enName']}":\n\n🧪 المادة الفعالة: $activeIngredient\n\n$lines\n\n💡 اسأل المندوبين عن توفر هذه البدائل.',
      intent: ChatIntent.findAlternative,
    );
  }

  // ── تحليل أنماط النواقص ──────────────────────────────────────────────────
  Future<ChatResponse> _handleAnalyzePatterns() async {
    final db = await DatabaseHelper.instance.database;
    final all = await db.query('shortages', orderBy: 'created_at DESC');
    if (all.isEmpty)
      return ChatResponse(
          text: '📭 لا توجد نواقص للتحليل.',
          intent: ChatIntent.analyzePatterns);
    final freq = <String, int>{};
    for (final s in all) {
      final name = s['name']?.toString() ?? '';
      freq[name] = (freq[name] ?? 0) + 1;
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(10).toList();
    final stubborn = all.where((s) => s['status'] == 'stubborn').length;
    final covered = all.where((s) => s['status'] == 'covered').length;
    final rate = all.isNotEmpty
        ? ((covered / all.length) * 100).toStringAsFixed(0)
        : '0';
    final lines = top.asMap().entries.map((e) {
      final medal = e.key < 3 ? ['🥇', '🥈', '🥉'][e.key] : '${e.key + 1}.';
      return '$medal ${e.value.key} (${e.value.value} مرة)';
    }).join('\n');
    return ChatResponse(
      text:
          '📈 تحليل أنماط النواقص:\n\n🔢 إجمالي: ${all.length} صنف\n✅ نسبة التغطية: $rate%\n🔴 مستعصي: $stubborn صنف\n\n🏆 الأكثر تكراراً:\n$lines\n\n💡 خزّن الأدوية الأكثر تكراراً بكميات أكبر!',
      intent: ChatIntent.analyzePatterns,
    );
  }

  // ── البحث في منصات الأدوية ──────────────────────────────────────────────────
  Future<ChatResponse> _handleSearchPlatform(String text) async {
    final n = _normalize(text);
    const stop = {
      'ابحث',
      'دور',
      'عن',
      'في',
      'سعر',
      'اسعار',
      'اطلب',
      'طلب',
      'منصة',
      'منصات',
      'شركة',
      'شركات',
      'اونلاين',
      'من',
      'لي',
      'لى',
      'عاوز',
      'عايز'
    };
    final words =
        n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ كيف أبحث عن سعر دواء؟\n\n💡 اكتب: "ابحث عن [اسم الدواء]"',
        intent: ChatIntent.searchPlatform,
        success: false,
      );
    }
    final drugName = words.join(' ');
    final platforms = await PlatformService.instance.getPlatforms();
    if (platforms.isEmpty) {
      return ChatResponse(
        text:
            '📱 لا توجد منصات مضافة!\n\n💡 أضف منصات الأدوية من:\nالإعدادات ← منصات الأدوية',
        intent: ChatIntent.searchPlatform,
        success: false,
      );
    }
    final results = await PlatformService.instance.searchAll(drugName);
    if (results.isEmpty) {
      return ChatResponse(
        text:
            '🔍 بحثت في ${platforms.length} منصة عن "$drugName"\n\n❌ لم أجد نتائج.\n\n💡 جرب اسم مختلف.',
        intent: ChatIntent.searchPlatform,
      );
    }
    final buf =
        StringBuffer('🔍 نتائج "$drugName" من ${results.length} منصة:\n\n');
    for (final entry in results.entries) {
      buf.writeln('📦 ${entry.key}:');
      for (final r in entry.value) {
        final avail = r.available ? '✅' : '❌';
        buf.write('  $avail ${r.drugName} - ${r.price.toStringAsFixed(2)}');
        if (r.discount > 0)
          buf.write(' (خصم ${r.discount.toStringAsFixed(0)}%)');
        buf.writeln();
      }
      buf.writeln();
    }
    buf.writeln('💡 للطلب تواصل مع المنصة مباشرة.');
    return ChatResponse(
        text: buf.toString().trim(), intent: ChatIntent.searchPlatform);
  }



  // ── تحميل القاموس ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _loadDictionary() async {
    final dictStr =
        await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        return decoded.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    final oldStr = await DatabaseHelper.instance.getSetting('drug_dictionary');
    if (oldStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(oldStr);
        return decoded
            .map((s) => <String, dynamic>{'enName': s.toString()})
            .toList();
      } catch (_) {}
    }
    return [];
  }

  // ── البحث عن دواء ──────────────────────────────────────────────────
  Future<ChatResponse> _handleSearchDrug(String text) async {
    final n = _normalize(text);
    final terms =
        text.split(RegExp(r'[\s/]+')).where((t) => t.isNotEmpty).toList();

    // ▌ 1️⃣ البحث في القاموس المفصّل (v2)
    final detailedKey = _detailedDrugInfo.keys.firstWhere(
      (k) => terms.any(
          (t) => k.contains(t.toLowerCase()) || t.toLowerCase().contains(k)),
      orElse: () => '',
    );
    if (detailedKey.isNotEmpty) {
      return _handleDrugInquiry(text);
    }

    // ▌ 2️⃣ البحث في القاموس المحلي
    final dictionary = await _loadDictionary();
    if (dictionary.isNotEmpty) {
      final matches = dictionary
          .where((drug) {
            final en = drug['enName']?.toString() ?? '';
            final ar = drug['arName']?.toString() ?? '';
            final act = drug['activeIngredient']?.toString() ?? '';
            final bar = drug['barcode']?.toString() ?? '';
            return terms.every((term) =>
                FuzzySearch.match(term, en) ||
                FuzzySearch.match(term, ar) ||
                FuzzySearch.match(term, act) ||
                FuzzySearch.match(term, bar));
          })
          .take(8)
          .toList();

      if (matches.isNotEmpty) {
        final lines = matches.map((d) {
          final en = d['enName'] ?? '';
          final ar = d['arName'] ?? '';
          final act = d['activeIngredient'] ?? '';
          final parts = <String>[
            '💊 $en',
            if (ar.toString().isNotEmpty) '   🏷️ $ar',
            if (act.toString().isNotEmpty) '   🧪 $act',
          ];
          return parts.join('\n');
        }).join('\n\n');
        return ChatResponse(
          text:
              '📖 نتائج البحث (${matches.length}):\n\n$lines\n\n💡 جرب: "أضف دواء ${matches.first['enName']}" أو "بديل ${matches.first['enName']}"',
          intent: ChatIntent.searchDrug,
        );
      }
    }

    // ▌ 3️⃣ البحث في النواقص المحلية
    final db = await DatabaseHelper.instance.database;
    final localResults = await db.query('shortages',
        where: 'name LIKE ?', whereArgs: ['%$n%'], limit: 5);
    if (localResults.isNotEmpty) {
      const statusLabel = {
        'pending': '⏳ معلق',
        'covered': '✅ متوفر',
        'offered': '📦 مُعروض',
        'stubborn': '🔴 عنيد'
      };
      final lines = localResults
          .map((s) =>
              '💊 ${s['name']} | ${statusLabel[s['status']] ?? s['status']}')
          .join('\n');
      return ChatResponse(
          text: '🗄️ موجود في النواقص المحلية:\n\n$lines',
          intent: ChatIntent.searchDrug);
    }

    // ▌ 4️⃣ البحث عبر API
    return _searchViaApi(text);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ نظام البحث Cascading - 4 مستويات (v2)
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _searchViaApi(String query,
      {List<String>? filePaths, MessageType? messageType}) async {
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('custom_api_url') ?? '';
    final customKey = prefs.getString('custom_api_key') ?? '';
    final customType = prefs.getString('custom_api_type') ?? 'openai';
    final savedFiles = prefs.getStringList('custom_api_files') ?? [];
    final pharmacyName =
        await DatabaseHelper.instance.getSetting('pharmacy_name');

    final allFiles = <String>[...?filePaths, ...savedFiles];

    // ▌ المستوى 1: القاموس المفصّل (v2)
    if (query.isNotEmpty) {
      final detailedKey = _detailedDrugInfo.keys.firstWhere(
        (k) =>
            k.contains(query.toLowerCase()) || query.toLowerCase().contains(k),
        orElse: () => '',
      );
      if (detailedKey.isNotEmpty) return _handleDrugInquiry(query);
    }

    // ▌ المستوى 2: البحث في الكتب المرفوعة (v2 - مع الترجمة)
    if (allFiles.isNotEmpty) {
      final bookRes =
          await _searchLocalFiles(query.isEmpty ? 'ملخص' : query, allFiles);
      if (bookRes.success && bookRes.text.contains('📄')) return bookRes;
    }

    // ▌ المستوى 3: DuckDuckGo مجاني
    try {
      final ddgRes = await _callDuckDuckGo(query);
      if (ddgRes.success) return ddgRes;
    } catch (_) {}

    // ▌ المستوى 4: API مدفوع
    try {
      if (customKey.isNotEmpty && customType == 'gemini') {
        return await _callGeminiApi(
            customKey, query, allFiles, pharmacyName, messageType);
      }
      if (customUrl.isNotEmpty &&
          customKey.isNotEmpty &&
          customType == 'openai') {
        return await _callOpenAIApi(
            customUrl, customKey, query, pharmacyName, messageType);
      }
      if (customUrl.isNotEmpty && customKey.isNotEmpty) {
        final res = await http
            .post(
              Uri.parse(customUrl),
              headers: {
                'Authorization': 'Bearer $customKey',
                'Content-Type': 'application/json'
              },
              body: jsonEncode({'query': query, 'q': query}),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final d = jsonDecode(res.body);
          final answer = d['answer'] ??
              d['response'] ??
              d['text'] ??
              d['AbstractText'] ??
              res.body;
          return ChatResponse(
              text: '🤖 حكيم:\n\n$answer', intent: ChatIntent.smartChat);
        }
      }
    } catch (e) {
      if (e.toString().contains('API_KEY') || e.toString().contains('401')) {
        return ChatResponse(
            text: '🔑 مفتاح API غير صحيح.\n\n💡 تحقق من المفتاح في الإعدادات.',
            intent: ChatIntent.smartChat,
            success: false);
      }
      if (e.toString().contains('quota') || e.toString().contains('429')) {
        return ChatResponse(
            text: '⏳ تم تجاوز حد الاستخدام.\n\n💡 انتظر قليلاً أو جرب API آخر.',
            intent: ChatIntent.smartChat,
            success: false);
      }
    }

    return ChatResponse(
      text:
          '🔍 لم أجد معلومات عن "$query".\n\n💡 جرب:\n• البحث باسم أبسط\n• رفع كتب علمية من الإعدادات\n• إضافة API مجاني أو مدفوع',
      intent: ChatIntent.smartChat,
      success: false,
    );
  }



  // ════════════════════════════════════════════════════════════════════════════
  // ▌ البحث في الكتب المرفوعة مع الترجمة التلقائية (v2)
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _searchLocalFiles(
      String query, List<String> files) async {
    final buffer = StringBuffer();
    int foundCount = 0;

    final terms =
        query.toLowerCase().split(' ').where((w) => w.length > 2).toList();
    if (terms.isEmpty) terms.add(query.toLowerCase());

    for (final path in files) {
      if (!File(path).existsSync()) continue;
      final ext = path.split('.').last.toLowerCase();
      final file = File(path);
      String text = '';

      try {
        if (ext == 'pdf') {
          final document = pdf.PdfDocument(inputBytes: file.readAsBytesSync());
          text = pdf.PdfTextExtractor(document).extractText();
          document.dispose();
          // ترجمة المصطلحات الإنجليزية للعربية
          for (final entry in _pharmaceuticalTranslations.entries) {
            text = text.replaceAll(RegExp(entry.key, caseSensitive: false),
                '${entry.key} (${entry.value})');
          }
        } else if (ext == 'xlsx' || ext == 'xls') {
          final bytes = file.readAsBytesSync();
          final excel = ex.Excel.decodeBytes(bytes);
          final tb = StringBuffer();
          for (final table in excel.tables.keys) {
            for (final row in excel.tables[table]!.rows) {
              tb.writeln(
                  row.map((e) => e?.value?.toString() ?? '').join(' | '));
            }
          }
          text = tb.toString();
        } else if (ext == 'docx') {
          final bytes = file.readAsBytesSync();
          final archive = ZipDecoder().decodeBytes(bytes);
          final docXml = archive.findFile('word/document.xml');
          if (docXml != null) {
            final content = utf8.decode(docXml.content as List<int>);
            final regex = RegExp(r'<w:t[^>]*>(.*?)<\/w:t>');
            text = regex.allMatches(content).map((m) => m.group(1)).join(' ');
          }
        } else if (ext == 'csv' || ext == 'txt') {
          text = file.readAsStringSync(encoding: utf8);
        } else if (ext == 'jpg' ||
            ext == 'jpeg' ||
            ext == 'png' ||
            ext == 'webp') {
          final textRecognizer =
              TextRecognizer(script: TextRecognitionScript.latin);
          final inputImage = InputImage.fromFilePath(path);
          final recognizedText = await textRecognizer.processImage(inputImage);
          text = recognizedText.text;
          // ترجمة النص المستخرج من الصورة
          for (final entry in _pharmaceuticalTranslations.entries) {
            text = text.replaceAll(RegExp(entry.key, caseSensitive: false),
                '${entry.key} (${entry.value})');
          }
          textRecognizer.close();
        }
      } catch (_) {}

      if (text.isEmpty) continue;

      final lines = text.split(RegExp(r'\n|\r|\. '));
      for (final line in lines) {
        bool matches = false;
        if (terms.length == 1) {
          matches = FuzzySearch.match(terms.first, line);
        } else {
          matches = terms.every((term) => line.toLowerCase().contains(term));
        }

        if (matches && buffer.length < 3000) {
          final name = path.split(Platform.pathSeparator).last;

          // تحديد نوع المحتوى وأيقونته (v2)
          String contentType = '📄';
          final lineLower = line.toLowerCase();
          if (lineLower.contains('tablet') ||
              lineLower.contains('capsule') ||
              lineLower.contains('syrup') ||
              lineLower.contains('injection')) {
            contentType = '💊';
          } else if (lineLower.contains('side effect') ||
              lineLower.contains('dosage') ||
              lineLower.contains('warning')) {
            contentType = '⚠️';
          } else if (lineLower.contains('indication') ||
              lineLower.contains('treatment') ||
              lineLower.contains('use')) {
            contentType = '📋';
          } else if (lineLower.contains('contraindication') ||
              lineLower.contains('precaution')) {
            contentType = '⛔';
          } else if (lineLower.contains('interaction')) {
            contentType = '🔬';
          } else if (lineLower.contains('pharmacokinetics') ||
              lineLower.contains('mechanism')) {
            contentType = '🧪';
          }

          buffer.writeln('$contentType من ملف ($name):');
          buffer.writeln('"... ${line.trim()} ..."');
          buffer.writeln();
          foundCount++;
          if (foundCount > 10) break;
        }
      }
      if (foundCount > 10) break;
    }

    if (foundCount > 0) {
      return ChatResponse(
        text:
            '📚 معلومات من كتبك العلمية:\n\n${buffer.toString()}\n\n💡 المصطلحات الإنجليزية مترجمة تلقائياً.',
        intent: ChatIntent.smartChat,
      );
    }

    return ChatResponse(
      text:
          '❌ لم أجد معلومات عن "$query" في الكتب.\n\n💡 جرب كلمة أبسط أو اسأل حكيم مباشرة!',
      intent: ChatIntent.smartChat,
      success: false,
    );
  }

  // ── DuckDuckGo مجاني ──────────────────────────────────────────────────
  Future<ChatResponse> _callDuckDuckGo(String query) async {
    try {
      final url =
          'https://api.duckduckgo.com/?q=${Uri.encodeComponent("$query دواء")}&format=json&no_html=1&skip_disambig=1';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final abstract = d['AbstractText']?.toString() ?? '';
        final related = (d['RelatedTopics'] as List?)?.isNotEmpty == true
            ? ((d['RelatedTopics'][0] as Map)['Text']?.toString() ?? '')
            : '';
        final result = abstract.isNotEmpty ? abstract : related;
        if (result.length > 20) {
          return ChatResponse(
            text: '🌐 معلومات عن "$query":\n\n$result\n\n📌 المصدر: DuckDuckGo',
            intent: ChatIntent.smartChat,
          );
        }
      }
    } catch (_) {}
    return ChatResponse(
      text:
          '🔍 لم أجد معلومات عن "$query".\n\n💡 جرب إضافة API خاص من الإعدادات.',
      intent: ChatIntent.smartChat,
      success: false,
    );
  }

  // ── Gemini API ──────────────────────────────────────────────────
  Future<ChatResponse> _callGeminiApi(
      String apiKey,
      String query,
      List<String> files,
      String? pharmacyName,
      MessageType? messageType) async {
    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
      final systemPrompt = getPharmacistSystemPrompt(
          pharmacyName: pharmacyName, messageType: messageType);
      final userPrompt =
          query.isEmpty && files.isNotEmpty ? 'اشرح ما في هذه الملفات.' : query;

      final fullPrompt = '''
$systemPrompt

═══════════════════════════════════════════════════════════════════════════
▌ سؤال المستخدم: $userPrompt
═══════════════════════════════════════════════════════════════════════════
▌ قواعد الإجابة:
• أجب بالعربية فقط
• استخدم الإيموجي المناسب
• اختم بنصيحة مفيدة (💡)
• اذكر إذا لم تكن متأكداً من معلومة
═══════════════════════════════════════════════════════════════════════════
''';

      final parts = <Part>[TextPart(fullPrompt)];
      for (final path in files) {
        if (!File(path).existsSync()) continue;
        final bytes = File(path).readAsBytesSync();
        final ext = path.split('.').last.toLowerCase();
        String mime = 'image/jpeg';
        if (ext == 'png') mime = 'image/png';
        if (ext == 'pdf') mime = 'application/pdf';
        if (ext == 'xlsx')
          mime =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        if (ext == 'xls') mime = 'application/vnd.ms-excel';
        if (ext == 'csv') mime = 'text/csv';
        if (ext == 'docx')
          mime =
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        parts.add(DataPart(mime, bytes));
      }

      final response = await model.generateContent([Content.multi(parts)]);
      final text = response.text ?? 'عذراً، لم أتمكن من الإجابة.';
      return ChatResponse(
          text: '🤖 حكيم:\n\n$text', intent: ChatIntent.smartChat);
    } catch (e) {
      if (e.toString().contains('API_KEY')) {
        return ChatResponse(
            text:
                '🔑 مفتاح API غير صحيح.\n\n💡 تأكد من صحة المفتاح في الإعدادات.',
            intent: ChatIntent.smartChat,
            success: false);
      }
      if (e.toString().contains('quota') || e.toString().contains('limit')) {
        return ChatResponse(
            text: '⏳ تم تجاوز الحد المسموح.\n\n💡 انتظر قليلاً وحاول مرة أخرى.',
            intent: ChatIntent.smartChat,
            success: false);
      }
      return ChatResponse(
          text: '⚠️ حدث خطأ: $e\n\n💡 حاول مرة أخرى.',
          intent: ChatIntent.smartChat,
          success: false);
    }
  }

  // ── OpenAI API ──────────────────────────────────────────────────
  Future<ChatResponse> _callOpenAIApi(String url, String apiKey, String query,
      String? pharmacyName, MessageType? messageType) async {
    final endpoint =
        url.endsWith('/') ? '${url}chat/completions' : '$url/chat/completions';
    final systemPrompt = getPharmacistSystemPrompt(
        pharmacyName: pharmacyName, messageType: messageType);

    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'model': 'gpt-3.5-turbo',
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': query},
            ],
            'max_tokens': 500,
            'temperature': 0.7,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      final answer = d['choices']?[0]?['message']?['content'] ??
          'عذراً، لم أتمكن من الإجابة.';
      return ChatResponse(
          text: '🤖 حكيم:\n\n$answer', intent: ChatIntent.smartChat);
    }
    if (res.statusCode == 401)
      return ChatResponse(
          text: '🔑 مفتاح API غير صحيح.',
          intent: ChatIntent.smartChat,
          success: false);
    if (res.statusCode == 429)
      return ChatResponse(
          text: '⏳ تم تجاوز الحد المسموح.',
          intent: ChatIntent.smartChat,
          success: false);
    throw Exception('API Error ${res.statusCode}');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ اقتراح أسماء أدوية (autocomplete) - مدمج من v1 + v2
  // ════════════════════════════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> suggestDrugNames(String query) async {
    if (query.trim().length < 3) return [];
    final prefs = await SharedPreferences.getInstance();

    // ▌ 1️⃣ القاموس المفصّل (v2)
    final detailedMatches = _detailedDrugInfo.entries
        .where((e) =>
            e.key.contains(query.toLowerCase()) ||
            query.toLowerCase().contains(e.key))
        .map((e) => {
              'enName': e.key,
              'arName': e.value['arName'] ?? '',
              'source': 'detailed'
            })
        .toList();
    if (detailedMatches.isNotEmpty) return detailedMatches;

    // ▌ 2️⃣ الملفات المحلية
    final savedFiles = prefs.getStringList('custom_api_files') ?? [];
    if (savedFiles.isNotEmpty) {
      final results = await _findDrugNamesInFiles(query, savedFiles);
      if (results.isNotEmpty) return results;
    }

    // ▌ 3️⃣ القاموس المحلي
    final dictionaryResults = await _searchInLocalDictionary(query);
    if (dictionaryResults.isNotEmpty) return dictionaryResults;

    // ▌ 4️⃣ AI
    return await _getAiDrugSuggestions(query);
  }

  Future<List<Map<String, dynamic>>> _searchInLocalDictionary(
      String query) async {
    final dictStr =
        await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        final normalized = query.toLowerCase().trim();
        final results = <Map<String, dynamic>>[];
        for (final drug in decoded) {
          final en = drug['enName']?.toString() ?? '';
          final ar = drug['arName']?.toString() ?? '';
          if (en.toLowerCase().contains(normalized) ||
              ar.toLowerCase().contains(normalized) ||
              FuzzySearch.match(normalized, en)) {
            results.add({'enName': en, 'arName': ar, 'source': 'dictionary'});
            if (results.length >= 8) break;
          }
        }
        return results;
      } catch (_) {}
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> _findDrugNamesInFiles(
      String query, List<String> files) async {
    final results = <String>{};
    final normalized = query.toLowerCase().trim();
    for (final path in files) {
      if (!File(path).existsSync()) continue;
      final ext = path.split('.').last.toLowerCase();
      try {
        if (ext == 'xlsx' || ext == 'xls') {
          final bytes = File(path).readAsBytesSync();
          final excel = ex.Excel.decodeBytes(bytes);
          for (final table in excel.tables.keys) {
            for (final row in excel.tables[table]!.rows) {
              for (final cell in row) {
                final val = cell?.value?.toString() ?? '';
                if (val.length > 3 &&
                    (val.toLowerCase().contains(normalized) ||
                        FuzzySearch.match(normalized, val))) results.add(val.trim());
              }
            }
          }
        } else if (ext == 'csv' || ext == 'txt') {
          final lines = File(path).readAsStringSync(encoding: utf8).split('\n');
          for (final line in lines) {
            for (final part in line.split(',')) {
              final val = part.trim();
              if (val.length > 3 &&
                  (val.toLowerCase().contains(normalized) ||
                      FuzzySearch.match(normalized, val))) results.add(val);
            }
          }
        }
      } catch (_) {}
      if (results.length >= 8) break;
    }
    return results
        .take(8)
        .map((s) => {'enName': s, 'arName': '', 'source': 'file'})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _getAiDrugSuggestions(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('custom_api_key') ?? '';
    final type = prefs.getString('custom_api_type') ?? 'openai';

    if (key.isNotEmpty && type == 'gemini') {
      try {
        final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: key);
        final prompt =
            'اقترح أسماء أدوية حقيقية مطابقة أو مشابهة لـ: "$query"\n- كل اسم في سطر منفصل\n- بدون أرقام أو شروحات\n- من 3-8 نتائج فقط';
        final response = await model.generateContent(
            [Content.text(prompt)]).timeout(const Duration(seconds: 8));
        final text = response.text ?? '';
        return text
            .split('\n')
            .map((s) => s.replaceAll(RegExp(r'^[\d\-\.\*\)]+\s*'), '').trim())
            .where((s) => s.isNotEmpty && s.length > 2 && s.length < 50)
            .take(8)
            .map((s) => {'enName': s, 'arName': '', 'source': 'gemini'})
            .toList();
      } catch (_) {}
    }

    if (key.isNotEmpty && type == 'openai') {
      try {
        final url =
            prefs.getString('custom_api_url') ?? 'https://api.openai.com/v1';
        final endpoint = url.endsWith('/')
            ? '${url}chat/completions'
            : '$url/chat/completions';
        final res = await http
            .post(
              Uri.parse(endpoint),
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json'
              },
              body: jsonEncode({
                'model': 'gpt-3.5-turbo',
                'messages': [
                  {
                    'role': 'system',
                    'content': 'أنت مساعد صيدلي. اقترح أسماء أدوية حقيقية فقط.'
                  },
                  {
                    'role': 'user',
                    'content':
                        'اقترح أدوية مطابقة لـ: $query\nكل اسم في سطر منفصل بدون أرقام.'
                  },
                ],
                'max_tokens': 100,
                'temperature': 0.3,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final d = jsonDecode(res.body);
          final text = d['choices']?[0]?['message']?['content'] ?? '';
          return text
              .split('\n')
              .map((s) => s.replaceAll(RegExp(r'^[\d\-\.\*\)]+\s*'), '').trim())
              .where((s) => s.isNotEmpty && s.length > 2 && s.length < 50)
              .take(8)
              .map((s) => {'enName': s, 'arName': '', 'source': 'openai'})
              .toList();
        }
      } catch (_) {}
    }

    // DuckDuckGo fallback
    try {
      final ddgUrl =
          'https://api.duckduckgo.com/?q=${Uri.encodeComponent("$query drug name")}&format=json&no_html=1';
      final res =
          await http.get(Uri.parse(ddgUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final topics = d['RelatedTopics'] as List? ?? [];
        final results = <String>{};
        for (final t in topics) {
          final text = t['Text']?.toString() ?? '';
          if (text.contains(' - ')) {
            final name = text.split(' - ').first.split(':').first.trim();
            if (name.length > 2 &&
                name.length < 40 &&
                FuzzySearch.match(query.toLowerCase(), name)) results.add(name);
          }
        }
        if (results.isNotEmpty)
          return results
              .take(8)
              .map((s) => {'enName': s, 'arName': '', 'source': 'web'})
              .toList();
      }
    } catch (_) {}

    return _getCommonDrugSuggestions(query);
  }

  List<Map<String, dynamic>> _getCommonDrugSuggestions(String query) {
    const commonDrugs = [
      'Panadol', 'Panadol Extra', 'Brufen', 'Brufen 400', 'Advil',
      'Nurofen', 'Voltaren', 'Aspirin', 'Paracetamol', 'Acetaminophen',
      'Augmentin', 'Amoxicillin', 'Azithromycin', 'Ciproxin', 'Ciprofloxacin',
      'Omeprazole', 'Losec', 'Pantosec', 'Famotidine', 'Ranitidine',
      'Metformin', 'Glucophage', 'Sitagliptin', 'Janumet',
      'Atorvastatin', 'Lipitor', 'Rosuvastatin', 'Crestor',
      'Amlodipine', 'Norvasc', 'Amlor', 'Bisoprolol', 'Concor',
      'Lisinopril', 'Zestril', 'Enalapril', 'Renitec',
      'Vitamin C', 'Vitamin D', 'Vitamin B12', 'Folic Acid',
      'Calcium', 'Magnesium', 'Zinc', 'Iron',
      'Claritine', 'Cetirizine', 'Loratadine', 'Telfast',
      'Dexamethasone', 'Prednisolone', 'Cortisone',
      'Lasix', 'Furosemide', 'Aldactone', 'Spironolactone',
      'Glimepiride', 'Amaryl', 'Diabeta', 'Glibenclamide',
      // أدوية مصرية شائعة
      'ميوفين', 'أدول', 'نوفالدول', 'سيتال', 'ريفو',
      'أزيماك', 'فلوميديكس', 'لازال', 'زورتك', 'كونجستال',
    ];
    final normalized = query.toLowerCase();
    return commonDrugs
        .where((d) =>
            d.toLowerCase().contains(normalized) || FuzzySearch.match(normalized, d))
        .take(8)
        .map((d) => {'enName': d, 'arName': '', 'source': 'common'})
        .toList();
  }

  // ── نصوص المساعدة ──────────────────────────────────────────────────
  String _helpText() => '''
🤖 أنا مساعدك الذكي - حكيم

════════════════════════════════════════════════════════════════════
▌ ما أستطيع فعله:
═══════════════════════════════════════════════════════════════════

📋 إدارة النواقص:
• "أضف دواء [اسم]" ← إضافة للنواقص
• "النواقص" ← عرض الكل
• "النواقص المعلقة" ← فقط المعلقة
• "تم توفير [اسم]" ← تعليم كمتوفر

🔄 البحث والبدائل:
• "ابحث عن [اسم]" ← بحث في الإنترنت
• "بديل [اسم]" ← بدائل بنفس المادة الفعالة
• "تحليل النواقص" ← أنماط وتكرارات

💰 إدارة الديون:
• "الديون" ← عرض كل العملاء
• "دين [اسم العميل]" ← دين عميل محدد

👥 المندوبين:
• "المندوبين" ← عرض القائمة

📊 التقارير:
• "ملخص اليوم" ← إحصائيات سريعة

🖼️ استخراج من صور:
• أرفق صورة روشتة وأنا استخرج الأدوية منها

═══════════════════════════════════════════════════════════════════
▌ نصائح للاستخدام:
═══════════════════════════════════════════════════════════════════
💡 اختر نوع رسالتك من الأزرار أعلى الشات
💡 أرفق صور روشتات لاستخراج الأدوية تلقائياً
💡 اكتب "مساعدة" في أي وقت لعرض الأوامر
''';

  String _apiHelpText() => '''
⚙️ إعدادات الذكاء الاصطناعي

🔗 الأنواع المدعومة:
• 🌟 Gemini (Google) ← الأسهل والأفضل
• 🤖 OpenAI / ChatGPT ← مع دعم السياقات
• 🔧 أي API متوافق مع OpenAI

💡 للحصول على مفتاح:
• Gemini: aistudio.google.com
• OpenAI: platform.openai.com

📁 قاعدة المعرفة:
• ارفع ملفات PDF/Excel/Word
• يمكنني البحث فيها والإجابة منها
''';

  // ── إدارة إعدادات API ──────────────────────────────────────────────────
  Future<void> saveApiSettings({
    required String url,
    required String key,
    required String type,
    required String name,
    List<String> files = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_api_url', url);
    await prefs.setString('custom_api_key', key);
    await prefs.setString('custom_api_type', type);
    await prefs.setString('custom_api_name', name);
    await prefs.setStringList('custom_api_files', files);
  }

  Future<Map<String, dynamic>> getApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'url': prefs.getString('custom_api_url') ?? '',
      'key': prefs.getString('custom_api_key') ?? '',
      'type': prefs.getString('custom_api_type') ?? 'openai',
      'name': prefs.getString('custom_api_name') ?? '',
      'files': prefs.getStringList('custom_api_files') ?? [],
    };
  }

  Future<void> clearApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_api_url');
    await prefs.remove('custom_api_key');
    await prefs.remove('custom_api_type');
    await prefs.remove('custom_api_name');
    await prefs.remove('custom_api_files');
  }
}
