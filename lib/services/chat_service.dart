import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:excel/excel.dart' as ex;
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'package:archive/archive.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../database/database_helper.dart';
import '../utils/fuzzy_search.dart';
import 'platform_service.dart';
import 'groq_service.dart';
import 'openfda_service.dart';
import 'rxnorm_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// ▌ نظام المساعد الذكي "حكيم" - v5.0
// ▌ مجاني 100% - Groq + OpenFDA + RxNorm
// ════════════════════════════════════════════════════════════════════════════

enum ChatIntent {
  addShortage, showShortages, showPendingShortages, markCovered, deleteShortage,
  searchDrug, findAlternative, analyzePatterns, searchPlatform,
  addCustomer, showDebts, checkCustomerDebt, addDebt, recordPayment,
  showReps, addRep,
  showStats, generateReport,
  apiSettings, help,
  addShortagesFromImage, smartChat,
  drugInquiry, priceInquiry, availabilityInquiry,
  generalQuestion, complaint, suggestion,
  setup, unknown,
}

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

enum MessageType {
  drug, alternative, shortage, debt, rep, stats, general, image,
}

extension MessageTypeExtension on MessageType {
  String get emoji {
    switch (this) {
      case MessageType.drug: return '💊';
      case MessageType.alternative: return '🔄';
      case MessageType.shortage: return '📋';
      case MessageType.debt: return '💰';
      case MessageType.rep: return '👥';
      case MessageType.stats: return '📊';
      case MessageType.general: return '❓';
      case MessageType.image: return '🖼️';
    }
  }

  String get label {
    switch (this) {
      case MessageType.drug: return 'استفسار دواء';
      case MessageType.alternative: return 'طلب بديل';
      case MessageType.shortage: return 'إضافة ناقص';
      case MessageType.debt: return 'سؤال عن دين';
      case MessageType.rep: return 'سؤال عن مندوب';
      case MessageType.stats: return 'إحصائيات';
      case MessageType.general: return 'سؤال عام';
      case MessageType.image: return 'صورة روشتة';
    }
  }

  String get hint {
    switch (this) {
      case MessageType.drug: return 'اكتب اسم الدواء...';
      case MessageType.alternative: return 'اكتب اسم الدواء للبحث عن بديل...';
      case MessageType.shortage: return 'اكتب اسم الدواء الناقص...';
      case MessageType.debt: return 'اكتب اسم العميل أو الأمر...';
      case MessageType.rep: return 'اكتب سؤالك عن المندوبين...';
      case MessageType.stats: return 'اكتب طلبك للإحصائيات...';
      case MessageType.general: return 'اكتب سؤالك هنا...';
      case MessageType.image: return 'أرفق صورة الروشتة...';
    }
  }

  List<String> get sampleCommands {
    switch (this) {
      case MessageType.drug: return ['باراسيتامول', 'بروفين 400', 'أدول'];
      case MessageType.alternative: return ['بديل بروفين', 'بديل ادول', 'عوض عن'];
      case MessageType.shortage: return ['أضف ناقص', 'سجل دواء ناقص', 'ضيف'];
      case MessageType.debt: return ['الديون', 'دين احمد', 'ضيف دين'];
      case MessageType.rep: return ['المندوبين', 'أضف مندوب', 'تقييم'];
      case MessageType.stats: return ['ملخص', 'إحصائيات', 'تقرير'];
      case MessageType.general: return ['مساعدة', 'ازاي أستخدم', 'الأوامر'];
      case MessageType.image: return [];
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ System Prompt لـ Groq
// ════════════════════════════════════════════════════════════════════════════

String getPharmacistSystemPrompt({String? pharmacyName, MessageType? messageType}) {
  return '''
أنت "حكيم" - مساعد صيدلي محترف متخصص في السوق المصري والعربي.

شخصيتك:
• صيدلي خبير، تتحدث بالعربية الفصحى السهلة
• ودود ومهني، تستخدم الإيموجي بشكل مناسب
• تقدم نصائح دقيقة ومفيدة

قواعد الرد:
1. ابدأ دائماً بأيقونة مناسبة (💊 🔍 📋 💰 ✅ ⚠️)
2. عند ذكر دواء: اذكر الاسم التجاري، المادة الفعالة، الاستخدامات، التحذيرات
3. اذكر أن الأسعار تقريبية وتتغير
4. اختم بنصيحة مفيدة (💡)
5. لا تقدم نصائح طبية بديلة للطبيب

سياق التطبيق:
• الصيدلية: ${pharmacyName ?? 'صيدليتك'}
• العملة: جنيه مصري
• المنطقة: مصر
''';
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ خدمة الشات بوت الرئيسية - v5.0
// ════════════════════════════════════════════════════════════════════════════

class ChatService {
  static final ChatService instance = ChatService._();
  ChatService._();

  // ── تطبيع النص ──────────────────────────────────────────────────
  String _normalize(String s) => s
      .replaceAll(RegExp(r'[إأآا]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[؟!.,،]'), '')
      .toLowerCase()
      .trim();

  // ── التحقق من اكتمال الإعداد ──────────────────────────────────────────────────
  Future<bool> isSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('setup_complete') ?? false;
  }

  // ── جلب Groq API Key ──────────────────────────────────────────────────
  Future<String> _getGroqKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('groq_api_key') ?? '';
  }

  // ── تصنيف النية ──────────────────────────────────────────────────
  ChatIntent _classify(String text, {MessageType? forcedType}) {
    if (forcedType != null) {
      switch (forcedType) {
        case MessageType.drug: return ChatIntent.drugInquiry;
        case MessageType.alternative: return ChatIntent.findAlternative;
        case MessageType.shortage: return ChatIntent.addShortage;
        case MessageType.debt: return ChatIntent.showDebts;
        case MessageType.rep: return ChatIntent.showReps;
        case MessageType.stats: return ChatIntent.showStats;
        case MessageType.general: return ChatIntent.generalQuestion;
        case MessageType.image: return ChatIntent.addShortagesFromImage;
      }
    }

    final n = _normalize(text);

    if (RegExp(r'(اضف|أضف|ضيف|سجل|دخل)').hasMatch(n) &&
        RegExp(r'(ناقص|نواقص|دواء|عقار|دوا)').hasMatch(n))
      return ChatIntent.addShortage;
    if (RegExp(r'(تم|وجد|اتوفر|كامل|غطي|غطى|اتغطى|توفر)').hasMatch(n))
      return ChatIntent.markCovered;
    if (RegExp(r'(معلق|انتظار)').hasMatch(n) && RegExp(r'(نواقص|دواء)').hasMatch(n))
      return ChatIntent.showPendingShortages;
    if (RegExp(r'(نواقص|الناقص|نواقصي)').hasMatch(n) &&
        !RegExp(r'(اضف|ضيف|سجل)').hasMatch(n))
      return ChatIntent.showShortages;

    if (RegExp(r'(ديون|الدين|مدين|مديون|دين)').hasMatch(n)) {
      final words = n.split(' ').where((w) => w.length > 2).toList();
      const stopDebt = {'ديون', 'الدين', 'مدين', 'مديون', 'دين', 'كل', 'اجمالي', 'مجموع'};
      final hasName = words.any((w) => !stopDebt.contains(w));
      return hasName ? ChatIntent.checkCustomerDebt : ChatIntent.showDebts;
    }

    if (RegExp(r'(مندوب|مندوبين)').hasMatch(n)) return ChatIntent.showReps;
    if (RegExp(r'(احصاء|احصائيات|تقرير|ملخص|اليوم|الوضع)').hasMatch(n))
      return ChatIntent.showStats;
    if (RegExp(r'(بديل|بدائل|بدل|عوض)').hasMatch(n))
      return ChatIntent.findAlternative;
    if (RegExp(r'(تحليل|انماط|نمط|تكرار|متكرر)').hasMatch(n))
      return ChatIntent.analyzePatterns;
    if (RegExp(r'(ابحث|دور|سعر|اسعار|اطلب|طلب|منصة|منصات)').hasMatch(n) &&
        !RegExp(r'(ناقص|نواقص|اضف|معلق)').hasMatch(n))
      return ChatIntent.searchPlatform;
    if (RegExp(r'(مساعده|مساعدة|ايه|ازاي|كيف|امر|اوامر)').hasMatch(n))
      return ChatIntent.help;
    if (RegExp(r'(اعمل|ضيف|سجل|انشئ|أنشئ)').hasMatch(n) &&
        RegExp(r'(حساب|عميل|زبون)').hasMatch(n))
      return ChatIntent.addCustomer;
    if (RegExp(r'(ضيف|اضف|سجل|استخرج)').hasMatch(n) &&
        RegExp(r'(الاصناف|النواقص|الادوية|الصور|روشته|روشتة|صوره)').hasMatch(n))
      return ChatIntent.addShortagesFromImage;

    if (n.length > 2) return ChatIntent.smartChat;
    return ChatIntent.unknown;
  }

  // ── تنفيذ الأمر ──────────────────────────────────────────────────
  Future<ChatResponse> execute(String text,
      {List<String>? filePaths, MessageType? messageType}) async {

    final intent = _classify(text, forcedType: messageType);

    if (intent == ChatIntent.addShortagesFromImage)
      return _extractAndAddItemsFromImage(text, filePaths);

    switch (intent) {
      case ChatIntent.addShortage: return _handleAddShortage(text);
      case ChatIntent.showShortages: return _handleShowShortages();
      case ChatIntent.showPendingShortages: return _handleShowShortages(status: 'pending');
      case ChatIntent.markCovered: return _handleMarkCovered(text);
      case ChatIntent.checkCustomerDebt: return _handleCustomerDebt(text);
      case ChatIntent.showDebts: return _handleShowDebts();
      case ChatIntent.showReps: return _handleShowReps();
      case ChatIntent.showStats: return _handleShowStats();
      case ChatIntent.help: return ChatResponse(text: _helpText(), intent: ChatIntent.help);
      case ChatIntent.findAlternative: return _handleFindAlternative(text);
      case ChatIntent.analyzePatterns: return _handleAnalyzePatterns();
      case ChatIntent.searchPlatform: return _handleSearchPlatform(text);
      case ChatIntent.addCustomer: return _handleAddCustomer(text);
      case ChatIntent.drugInquiry: return _handleDrugInquiry(text);
      case ChatIntent.generalQuestion:
      case ChatIntent.smartChat: return _handleSmartChat(text, messageType: messageType);
      default: return _handleSearchDrug(text);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ البحث عن دواء - يمر على 3 مستويات مجانية
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleDrugInquiry(String text) async {
    final n = _normalize(text);
    final stopWords = {'ما', 'هو', 'عن', 'دواء', 'عقار', 'معلومات', 'اشرح', 'اخبرني'};
    final words = n.split(' ').where((w) => !stopWords.contains(w) && w.length > 2).toList();
    final drugName = words.isNotEmpty ? words.join(' ') : text;

    // ▌ المستوى 1: القاموس المحلي
    final localResult = await _searchLocalDictionary(drugName);
    if (localResult != null) return localResult;

    // ▌ المستوى 2: OpenFDA (مجاني)
    final fdaInfo = await OpenFDAService.instance.searchDrug(drugName);
    if (fdaInfo != null) {
      return ChatResponse(
        text: '💊 معلومات "$drugName" من FDA:\n\n${fdaInfo.toArabicText()}\n\n'
            '💡 هذه المعلومات من قاعدة بيانات FDA الرسمية.',
        intent: ChatIntent.drugInquiry,
      );
    }

    // ▌ المستوى 3: Groq AI (مجاني)
    return _askGroq(
      query: text,
      intent: ChatIntent.drugInquiry,
      messageType: MessageType.drug,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ البدائل - RxNorm أولاً ثم Groq
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleFindAlternative(String text) async {
    final n = _normalize(text);
    const stop = {'بديل', 'بدائل', 'بدل', 'عوض', 'لـ', 'ل', 'دواء', 'عقار'};
    final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();

    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب: "بديل [اسم الدواء]"\n\n📌 مثال: "بديل بروفين"',
        intent: ChatIntent.findAlternative,
        success: false,
      );
    }

    final drugName = words.join(' ');

    // ▌ المستوى 1: القاموس المحلي
    final localAlt = await _findAlternativeLocal(drugName);
    if (localAlt != null) return localAlt;

    // ▌ المستوى 2: RxNorm (مجاني)
    try {
      final alternatives = await RxNormService.instance.getAlternatives(drugName);
      if (alternatives.isNotEmpty) {
        final text = RxNormService.instance.alternativesToArabicText(alternatives, drugName);
        return ChatResponse(
          text: '$text\n\n📌 المصدر: RxNorm (NIH) - قاعدة بيانات رسمية مجانية',
          intent: ChatIntent.findAlternative,
        );
      }
    } catch (_) {}

    // ▌ المستوى 3: Groq AI
    return _askGroq(
      query: 'أعطني بدائل دواء $drugName بنفس المادة الفعالة',
      intent: ChatIntent.findAlternative,
      messageType: MessageType.alternative,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ المحادثة الذكية - Groq أولاً
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleSmartChat(String text, {MessageType? messageType}) async {
    return _askGroq(
      query: text,
      intent: ChatIntent.smartChat,
      messageType: messageType ?? MessageType.general,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ Groq - المحرك الرئيسي المجاني
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _askGroq({
    required String query,
    required ChatIntent intent,
    MessageType? messageType,
  }) async {
    final groqKey = await _getGroqKey();

    if (groqKey.isEmpty) {
      return ChatResponse(
        text: '⚙️ حكيم محتاج إعداد!\n\n'
            '💡 اضغط على أيقونة الإعدادات لإضافة Groq API Key مجاناً.\n\n'
            '📌 Groq مجاني بالكامل ولا يحتاج بطاقة بنكية.',
        intent: ChatIntent.setup,
        success: false,
      );
    }

    try {
      final pharmacyName = await DatabaseHelper.instance.getSetting('pharmacy_name');
      final systemPrompt = getPharmacistSystemPrompt(
        pharmacyName: pharmacyName,
        messageType: messageType,
      );

      final answer = await GroqService.instance.ask(
        apiKey: groqKey,
        systemPrompt: systemPrompt,
        userMessage: query,
      );

      if (answer != null && answer.isNotEmpty) {
        return ChatResponse(
          text: '🤖 حكيم:\n\n$answer',
          intent: intent,
        );
      }
    } on GroqException catch (e) {
      if (e.message.contains('غير صحيح')) {
        return ChatResponse(
          text: '🔑 مفتاح Groq غير صحيح.\n\n💡 اذهب للإعدادات وأضف مفتاح جديد.',
          intent: ChatIntent.setup,
          success: false,
        );
      }
      if (e.message.contains('انتظر')) {
        // fallback لـ Gemini لو موجود
        final geminiResult = await _tryGemini(query, messageType);
        if (geminiResult != null) return geminiResult;

        return ChatResponse(
          text: '⏳ ${e.message}\n\n💡 جرب تاني بعد ثواني.',
          intent: intent,
          success: false,
        );
      }
    } catch (_) {}

    return ChatResponse(
      text: '❌ تعذر الاتصال.\n\n💡 تأكد من الإنترنت وحاول تاني.',
      intent: intent,
      success: false,
    );
  }

  // ── Gemini كـ Fallback فقط لو المستخدم حاطه ──────────────────────────────────────────────────
  Future<ChatResponse?> _tryGemini(String query, MessageType? messageType) async {
    final prefs = await SharedPreferences.getInstance();
    final geminiKey = prefs.getString('custom_api_key') ?? '';
    final apiType = prefs.getString('custom_api_type') ?? '';

    if (geminiKey.isEmpty || apiType != 'gemini') return null;

    try {
      final pharmacyName = await DatabaseHelper.instance.getSetting('pharmacy_name');
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: geminiKey);
      final systemPrompt = getPharmacistSystemPrompt(pharmacyName: pharmacyName, messageType: messageType);
      final response = await model.generateContent([Content.text('$systemPrompt\n\n$query')]);
      final text = response.text ?? '';
      if (text.isNotEmpty) {
        return ChatResponse(text: '🤖 حكيم:\n\n$text', intent: ChatIntent.smartChat);
      }
    } catch (_) {}
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ البحث عن دواء - المستويات المحلية
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleSearchDrug(String text) async {
    final localResult = await _searchLocalDictionary(text);
    if (localResult != null) return localResult;

    // بحث في النواقص المحلية
    final db = await DatabaseHelper.instance.database;
    final n = _normalize(text);
    final localResults = await db.query('shortages',
        where: 'name LIKE ?', whereArgs: ['%$n%'], limit: 5);

    if (localResults.isNotEmpty) {
      const statusLabel = {
        'pending': '⏳ معلق', 'covered': '✅ متوفر',
        'offered': '📦 مُعروض', 'stubborn': '🔴 عنيد'
      };
      final lines = localResults
          .map((s) => '💊 ${s['name']} | ${statusLabel[s['status']] ?? s['status']}')
          .join('\n');
      return ChatResponse(text: '🗄️ موجود في النواقص:\n\n$lines', intent: ChatIntent.searchDrug);
    }

    // OpenFDA
    final fdaInfo = await OpenFDAService.instance.searchDrug(text);
    if (fdaInfo != null) {
      return ChatResponse(
        text: '💊 معلومات من FDA:\n\n${fdaInfo.toArabicText()}',
        intent: ChatIntent.searchDrug,
      );
    }

    return _askGroq(query: text, intent: ChatIntent.searchDrug, messageType: MessageType.drug);
  }

  // ── البحث في القاموس المحلي ──────────────────────────────────────────────────
  Future<ChatResponse?> _searchLocalDictionary(String drugName) async {
    final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr == null) return null;

    try {
      final List<dynamic> decoded = jsonDecode(dictStr);
      final normalized = drugName.toLowerCase().trim();
      final matches = decoded.where((drug) {
        final en = drug['enName']?.toString().toLowerCase() ?? '';
        final ar = drug['arName']?.toString().toLowerCase() ?? '';
        return en.contains(normalized) || ar.contains(normalized) || FuzzySearch.match(normalized, en);
      }).take(5).toList();

      if (matches.isEmpty) return null;

      final drug = matches.first;
      final en = drug['enName'] ?? '';
      final ar = drug['arName'] ?? '';
      final active = drug['activeIngredient'] ?? '';
      final company = drug['company'] ?? '';

      String details = '💊 $en';
      if (ar.toString().isNotEmpty) details += ' ($ar)';
      details += '\n';
      if (active.toString().isNotEmpty) details += '🧪 المادة الفعالة: $active\n';
      if (company.toString().isNotEmpty) details += '🏭 الشركة: $company\n';
      details += '\n💡 اكتب "بديل $en" للبحث عن بدائل.';

      return ChatResponse(text: details, intent: ChatIntent.drugInquiry);
    } catch (_) {
      return null;
    }
  }

  // ── بحث البدائل في القاموس المحلي ──────────────────────────────────────────────────
  Future<ChatResponse?> _findAlternativeLocal(String drugName) async {
    final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr == null) return null;

    try {
      final List<dynamic> decoded = jsonDecode(dictStr);
      final normalized = drugName.toLowerCase();

      final original = decoded.where((d) {
        final en = d['enName']?.toString().toLowerCase() ?? '';
        final ar = d['arName']?.toString().toLowerCase() ?? '';
        return en.contains(normalized) || ar.contains(normalized);
      }).toList();

      if (original.isEmpty) return null;

      final activeIngredient = original.first['activeIngredient']?.toString() ?? '';
      if (activeIngredient.isEmpty) return null;

      final alternatives = decoded.where((d) {
        final act = d['activeIngredient']?.toString().toLowerCase() ?? '';
        final en = d['enName']?.toString() ?? '';
        return act.contains(activeIngredient.toLowerCase()) && en != original.first['enName'];
      }).take(8).toList();

      if (alternatives.isEmpty) return null;

      final lines = alternatives.map((d) =>
          '💊 ${d['enName']}${d['arName']?.toString().isNotEmpty == true ? " (${d['arName']})" : ""}')
          .join('\n');

      return ChatResponse(
        text: '🔄 بدائل "${original.first['enName']}":\n\n🧪 المادة الفعالة: $activeIngredient\n\n$lines\n\n'
            '💡 كل البدائل بنفس المادة الفعالة.',
        intent: ChatIntent.findAlternative,
      );
    } catch (_) {
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ إدارة النواقص
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleAddShortage(String text) async {
    final n = _normalize(text);
    const stopWords = {'اضف', 'أضف', 'ضيف', 'سجل', 'دخل', 'ناقص', 'نواقص', 'دواء', 'عقار', 'دوا'};
    final words = n.split(' ').where((w) => !stopWords.contains(w) && w.length > 1).toList();

    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب: "أضف دواء [اسم الدواء]"\n\n📌 مثال: "أضف دواء باراسيتامول"',
        intent: ChatIntent.addShortage,
        success: false,
      );
    }

    final drugName = words.join(' ');
    await DatabaseHelper.instance.insertShortage({
      'name': drugName, 'company': 'غير محدد', 'quantity': 1,
      'status': 'pending', 'is_urgent': 0, 'notes': 'أُضيف عن طريق حكيم',
    });

    return ChatResponse(
      text: '✅ تم إضافة "$drugName" للنواقص!\n\n📋 يمكنك:\n• إرساله للمندوبين\n'
          '• تعليمه كمتوفر عند توفره\n• البحث عن بديل\n\n'
          '💡 اكتب "بديل $drugName" للبحث عن بدائل.',
      intent: ChatIntent.addShortage,
      success: true,
      actionData: {'drug': drugName, 'action': 'add_shortage'},
    );
  }

  Future<ChatResponse> _handleShowShortages({String? status}) async {
    final shortages = await DatabaseHelper.instance.getShortages(status: status);
    if (shortages.isEmpty) {
      return ChatResponse(
        text: status == 'pending'
            ? '🎉 لا توجد نواقص معلقة حالياً!'
            : '📭 لا توجد نواقص مسجلة.',
        intent: ChatIntent.showShortages,
      );
    }

    const statusIcons = {'pending': '⏳', 'covered': '✅', 'offered': '📦', 'stubborn': '🔴'};
    const statusLabels = {'pending': 'معلق', 'covered': 'متوفر', 'offered': 'مُعروض', 'stubborn': 'عنيد'};
    final label = status == 'pending' ? 'المعلقة' : 'الكل';

    final lines = shortages.take(10).map((s) {
      final icon = statusIcons[s['status']] ?? '💊';
      final statusLabel = statusLabels[s['status']] ?? s['status'];
      return '$icon ${s['name']} | ${s['company']}\n   📌 الحالة: $statusLabel';
    }).join('\n\n');

    final more = shortages.length > 10 ? '\n\n...و ${shortages.length - 10} أدوية أخرى' : '';
    return ChatResponse(
      text: '📋 قائمة النواقص $label (${shortages.length}):\n\n$lines$more',
      intent: ChatIntent.showShortages,
    );
  }

  Future<ChatResponse> _handleMarkCovered(String text) async {
    final n = _normalize(text);
    const stop = {'تم', 'وجد', 'اتوفر', 'كامل', 'غطي', 'غطى', 'توفر', 'اتغطى'};
    final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();

    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب: "تم توفير [اسم الدواء]"',
        intent: ChatIntent.markCovered,
        success: false,
      );
    }

    final drugName = words.join(' ');
    final db = await DatabaseHelper.instance.database;
    final results = await db.query('shortages',
        where: "name LIKE ? AND status != 'covered'", whereArgs: ['%$drugName%']);

    if (results.isEmpty) {
      return ChatResponse(
        text: '🔍 لم أجد "$drugName" في النواقص المعلقة.',
        intent: ChatIntent.markCovered,
        success: false,
      );
    }

    for (final s in results) {
      await DatabaseHelper.instance.updateShortage(s['id'] as int, {'status': 'covered'});
    }

    return ChatResponse(
      text: '✅ تم تعليم "${results.first['name']}" كـ متوفر!',
      intent: ChatIntent.markCovered,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ إدارة الديون
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleCustomerDebt(String text) async {
    final n = _normalize(text);
    const stop = {'ديون', 'دين', 'مدين', 'مديون', 'عميل', 'كام', 'بكام'};
    final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) return _handleShowDebts();

    final name = words.join(' ');
    final db = await DatabaseHelper.instance.database;
    final results = await db.query('customers', where: 'name LIKE ?', whereArgs: ['%$name%']);

    if (results.isEmpty) {
      return ChatResponse(
        text: '🔍 لم أجد عميل باسم "$name".',
        intent: ChatIntent.checkCustomerDebt,
        success: false,
      );
    }

    final c = results.first;
    final debt = (c['total_debt'] as num).toDouble();
    final emoji = debt > 500 ? '🔴' : debt > 0 ? '🟡' : '✅';
    final status = debt > 500 ? 'مرتفع' : debt > 0 ? 'معتدل' : 'منتهي';

    return ChatResponse(
      text: '$emoji العميل: ${c['name']}\n\n💰 الدين: ${debt.toStringAsFixed(2)} ج.م\n📌 الحالة: $status',
      intent: ChatIntent.checkCustomerDebt,
    );
  }

  Future<ChatResponse> _handleShowDebts() async {
    final customers = await DatabaseHelper.instance.getCustomers();
    final withDebt = customers.where((c) => (c['total_debt'] as num) > 0).toList();

    if (withDebt.isEmpty) {
      return ChatResponse(text: '🎉 لا توجد ديون حالياً!', intent: ChatIntent.showDebts);
    }

    final total = withDebt.fold<double>(0, (sum, c) => sum + (c['total_debt'] as num).toDouble());
    final lines = withDebt.take(8).map((c) {
      final debt = (c['total_debt'] as num).toDouble();
      final emoji = debt > 500 ? '🔴' : '🟡';
      return '$emoji ${c['name']}: ${debt.toStringAsFixed(0)} ج.م';
    }).join('\n');

    return ChatResponse(
      text: '💰 الديون (${withDebt.length} عميل):\n\n$lines\n\n📊 الإجمالي: ${total.toStringAsFixed(2)} ج.م',
      intent: ChatIntent.showDebts,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ المندوبين والإحصائيات
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _handleShowReps() async {
    final reps = await DatabaseHelper.instance.getReps();
    if (reps.isEmpty) {
      return ChatResponse(
        text: '📭 لا يوجد مندوبين مسجلين.\n\n💡 أضف المندوبين من شاشة المندوبين.',
        intent: ChatIntent.showReps,
      );
    }

    final lines = reps.take(6).map((r) {
      final stars = '⭐' * (((r['rating'] as int?) ?? 3).clamp(1, 5));
      return '👤 ${r['name']} | ${r['company'] ?? "غير محدد"}\n   $stars';
    }).join('\n\n');

    return ChatResponse(text: '👥 المندوبون (${reps.length}):\n\n$lines', intent: ChatIntent.showReps);
  }

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
          '   🔴 عنيد: ${stats['stubborn']}\n\n'
          '📈 نسبة التغطية: $rate%\n\n'
          '💰 إجمالي الديون: ${totalDebt.toStringAsFixed(2)} $currency',
      intent: ChatIntent.showStats,
    );
  }

  Future<ChatResponse> _handleAnalyzePatterns() async {
    final db = await DatabaseHelper.instance.database;
    final all = await db.query('shortages', orderBy: 'created_at DESC');

    if (all.isEmpty) {
      return ChatResponse(text: '📭 لا توجد نواقص للتحليل.', intent: ChatIntent.analyzePatterns);
    }

    final freq = <String, int>{};
    for (final s in all) {
      final name = s['name']?.toString() ?? '';
      freq[name] = (freq[name] ?? 0) + 1;
    }

    final sorted = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(10).toList();
    final covered = all.where((s) => s['status'] == 'covered').length;
    final rate = ((covered / all.length) * 100).toStringAsFixed(0);

    final lines = top.asMap().entries.map((e) {
      final medal = e.key < 3 ? ['🥇', '🥈', '🥉'][e.key] : '${e.key + 1}.';
      return '$medal ${e.value.key} (${e.value.value} مرة)';
    }).join('\n');

    return ChatResponse(
      text: '📈 تحليل النواقص:\n\n✅ نسبة التغطية: $rate%\n\n🏆 الأكثر تكراراً:\n$lines\n\n'
          '💡 خزّن الأكثر تكراراً بكميات أكبر!',
      intent: ChatIntent.analyzePatterns,
    );
  }

  Future<ChatResponse> _handleSearchPlatform(String text) async {
    final platforms = await PlatformService.instance.getPlatforms();
    if (platforms.isEmpty) {
      return ChatResponse(
        text: '📱 لا توجد منصات مضافة!\n\n💡 أضف منصات من الإعدادات.',
        intent: ChatIntent.searchPlatform,
        success: false,
      );
    }

    final n = _normalize(text);
    const stop = {'ابحث', 'دور', 'عن', 'في', 'سعر', 'اسعار', 'منصة', 'شركة'};
    final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب: "ابحث عن [اسم الدواء]"',
        intent: ChatIntent.searchPlatform,
        success: false,
      );
    }

    final drugName = words.join(' ');
    final results = await PlatformService.instance.searchAll(drugName);

    if (results.isEmpty) {
      return ChatResponse(
        text: '🔍 بحثت في ${platforms.length} منصة عن "$drugName"\n\n❌ لم أجد نتائج.',
        intent: ChatIntent.searchPlatform,
      );
    }

    final buf = StringBuffer('🔍 نتائج "$drugName":\n\n');
    for (final entry in results.entries) {
      buf.writeln('📦 ${entry.key}:');
      for (final r in entry.value) {
        buf.writeln('  ${r.available ? "✅" : "❌"} ${r.drugName} - ${r.price.toStringAsFixed(2)}');
      }
      buf.writeln();
    }

    return ChatResponse(text: buf.toString().trim(), intent: ChatIntent.searchPlatform);
  }

  Future<ChatResponse> _handleAddCustomer(String text) async {
    final patterns = [
      RegExp(r'(?:باسم|اسم)\s+([^\s\d]+(?:\s+[^\s\d]+)*)'),
      RegExp(r'(?:أضف|ضيف)\s+(?:عميل\s+)?([^\s\d]+(?:\s+[^\s\d]+)*)', caseSensitive: false),
    ];

    String? extractedName;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        extractedName = match.group(1)?.trim();
        break;
      }
    }

    if (extractedName == null || extractedName.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب: "أضف عميل [الاسم]"',
        intent: ChatIntent.addCustomer,
        success: false,
      );
    }

    try {
      await DatabaseHelper.instance.insertCustomer({'name': extractedName, 'phone': '', 'address': ''});
      return ChatResponse(
        text: '✅ تم إنشاء حساب "$extractedName" بنجاح!',
        intent: ChatIntent.addCustomer,
      );
    } catch (_) {
      return ChatResponse(
        text: '⚠️ حدث خطأ. حاول مرة أخرى.',
        intent: ChatIntent.addCustomer,
        success: false,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ استخراج من صور
  // ════════════════════════════════════════════════════════════════════════════
  Future<ChatResponse> _extractAndAddItemsFromImage(String text, List<String>? filePaths) async {
    if (filePaths == null || filePaths.isEmpty) {
      return ChatResponse(
        text: '📷 أرفق صورة الروشتة أو قائمة الأدوية مع رسالتك.',
        intent: ChatIntent.addShortagesFromImage,
        success: false,
      );
    }

    final groqKey = await _getGroqKey();

    // ▌ محاولة Groq مع صورة (عبر base64 إن أمكن)
    // ▌ الاستخراج المحلي
    try {
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      int added = 0;
      final buffer = StringBuffer();

      for (final path in filePaths) {
        if (!File(path).existsSync()) continue;
        final ext = path.split('.').last.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
          final inputImage = InputImage.fromFilePath(path);
          final recognizedText = await textRecognizer.processImage(inputImage);
          for (var line in recognizedText.text.split('\n')) {
            line = line.trim();
            if (line.isEmpty || line.length <= 2 || RegExp(r'^\d+$').hasMatch(line)) continue;
            await DatabaseHelper.instance.insertShortage({
              'name': line, 'company': 'غير محدد', 'quantity': 1,
              'status': 'pending', 'is_urgent': 0, 'notes': 'مستخرج من صورة',
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
          text: '✅ تم استخراج $added صنف:\n\n${buffer.toString()}\n\n⚠️ راجع الأسماء.',
          intent: ChatIntent.addShortagesFromImage,
        );
      }
    } catch (_) {}

    return ChatResponse(
      text: '❌ لم أجد نصوص واضحة.\n\n💡 جرب صورة أوضح أو أضف يدوياً.',
      intent: ChatIntent.addShortagesFromImage,
      success: false,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ Autocomplete
  // ════════════════════════════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> suggestDrugNames(String query) async {
    if (query.trim().length < 3) return [];

    // القاموس المحلي
    final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        final normalized = query.toLowerCase().trim();
        final results = <Map<String, dynamic>>[];
        for (final drug in decoded) {
          final en = drug['enName']?.toString() ?? '';
          final ar = drug['arName']?.toString() ?? '';
          if (en.toLowerCase().contains(normalized) || ar.toLowerCase().contains(normalized)) {
            results.add({'enName': en, 'arName': ar, 'source': 'dictionary'});
            if (results.length >= 8) break;
          }
        }
        if (results.isNotEmpty) return results;
      } catch (_) {}
    }

    return _getCommonDrugSuggestions(query);
  }

  List<Map<String, dynamic>> _getCommonDrugSuggestions(String query) {
    const commonDrugs = [
      'Panadol', 'Panadol Extra', 'Brufen', 'Brufen 400', 'Advil',
      'Nurofen', 'Voltaren', 'Aspirin', 'Paracetamol',
      'Augmentin', 'Amoxicillin', 'Azithromycin', 'Ciproxin',
      'Omeprazole', 'Losec', 'Metformin', 'Glucophage',
      'Atorvastatin', 'Amlodipine', 'Losartan',
      'ميوفين', 'أدول', 'نوفالدول', 'سيتال', 'أزيماك',
    ];

    final normalized = query.toLowerCase();
    return commonDrugs
        .where((d) => d.toLowerCase().contains(normalized))
        .take(8)
        .map((d) => {'enName': d, 'arName': '', 'source': 'common'})
        .toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ▌ إعدادات API
  // ════════════════════════════════════════════════════════════════════════════
  Future<void> saveGroqKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('groq_api_key', key);
  }

  Future<String> getGroqKey() => _getGroqKey();

  Future<void> saveApiSettings({
    required String url, required String key,
    required String type, required String name,
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
      'groq_key': prefs.getString('groq_api_key') ?? '',
      'url': prefs.getString('custom_api_url') ?? '',
      'key': prefs.getString('custom_api_key') ?? '',
      'type': prefs.getString('custom_api_type') ?? 'openai',
      'name': prefs.getString('custom_api_name') ?? '',
      'files': prefs.getStringList('custom_api_files') ?? [],
    };
  }

  Future<void> clearApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('groq_api_key');
    await prefs.remove('custom_api_url');
    await prefs.remove('custom_api_key');
    await prefs.remove('custom_api_type');
    await prefs.remove('custom_api_name');
    await prefs.remove('custom_api_files');
  }

  // ── نص المساعدة ──────────────────────────────────────────────────
  String _helpText() => '''
🤖 أنا حكيم - مساعدك الذكي

💊 الأدوية:
• اكتب اسم الدواء للبحث عن معلوماته
• "بديل [الاسم]" للبحث عن بدائل

📋 النواقص:
• "أضف دواء [الاسم]"
• "النواقص" لعرض الكل
• "تم توفير [الاسم]"

💰 الديون:
• "الديون" لعرض الكل
• "دين [اسم العميل]"

📊 الإحصائيات:
• "ملخص" أو "إحصائيات"

💡 حكيم يستخدم Groq AI + OpenFDA + RxNorm
   كلها مجانية بالكامل!
''';
}
