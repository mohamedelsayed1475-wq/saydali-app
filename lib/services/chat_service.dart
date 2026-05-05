import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import 'platform_service.dart';

// ── أنواع النوايا ──────────────────────────────────────────────────
enum ChatIntent {
  addShortage,
  showShortages,
  showPendingShortages,
  markCovered,
  deleteShortage,
  searchDrug,
  findAlternative,
  analyzePatterns,
  searchPlatform,
  showDebts,
  checkCustomerDebt,
  showReps,
  showStats,
  apiSettings,
  help,
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

// ── خدمة الشات بوت الرئيسية ──────────────────────────────────────────────────
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
  ChatIntent _classify(String text) {
    final n = _normalize(text);

    if (RegExp(r'(اضف|أضف|ضيف|سجل|دخل)').hasMatch(n) &&
        RegExp(r'(ناقص|نواقص|دواء|عقار|دوا)').hasMatch(n)) {
      return ChatIntent.addShortage;
    }
    if (RegExp(r'(تم|وجد|اتوفر|كامل|غطي|غطى|اتغطى|توفر)').hasMatch(n)) {
      return ChatIntent.markCovered;
    }
    if (RegExp(r'(معلق|انتظار)').hasMatch(n) &&
        RegExp(r'(نواقص|دواء)').hasMatch(n)) {
      return ChatIntent.showPendingShortages;
    }
    if (RegExp(r'(نواقص|الناقص|نواقصي)').hasMatch(n) &&
        !RegExp(r'(اضف|ضيف|سجل)').hasMatch(n)) {
      return ChatIntent.showShortages;
    }
    if (RegExp(r'(ديون|الدين|مدين|مديون|دين)').hasMatch(n)) {
      final words =
          n.split(' ').where((w) => w.length > 2).toList();
      final stopDebt = {'ديون', 'الدين', 'مدين', 'مديون', 'دين', 'كل', 'اجمالي', 'مجموع'};
      final hasName = words.any((w) => !stopDebt.contains(w));
      return hasName ? ChatIntent.checkCustomerDebt : ChatIntent.showDebts;
    }
    if (RegExp(r'(مندوب|مندوبين)').hasMatch(n)) {
      return ChatIntent.showReps;
    }
    if (RegExp(r'(احصاء|احصائيات|تقرير|ملخص|اليوم|الوضع)').hasMatch(n)) {
      return ChatIntent.showStats;
    }
    if (RegExp(r'(api|ايبيآي|مفتاح|ذكاء)').hasMatch(n)) {
      return ChatIntent.apiSettings;
    }
    if (RegExp(r'(بديل|بدائل|بدل|عوض)').hasMatch(n)) {
      return ChatIntent.findAlternative;
    }
    if (RegExp(r'(تحليل|انماط|نمط|تكرار|متكرر)').hasMatch(n)) {
      return ChatIntent.analyzePatterns;
    }
    if (RegExp(r'(ابحث|دور|سعر|اسعار|اطلب|طلب|منصة|منصات|شركة|شركات|اونلاين)').hasMatch(n) &&
        !RegExp(r'(ناقص|نواقص|اضف|معلق)').hasMatch(n)) {
      return ChatIntent.searchPlatform;
    }
    if (RegExp(r'(مساعده|مساعدة|ايه|ازاي|كيف|ايش|امر|اوامر)').hasMatch(n)) {
      return ChatIntent.help;
    }
    if (n.length > 2) return ChatIntent.searchDrug;
    return ChatIntent.unknown;
  }

  // ── تنفيذ الأمر ──────────────────────────────────────────────────
  Future<ChatResponse> execute(String text) async {
    final intent = _classify(text);
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
        return ChatResponse(text: _apiHelpText(), intent: ChatIntent.apiSettings);
      case ChatIntent.help:
        return ChatResponse(text: _helpText(), intent: ChatIntent.help);
      case ChatIntent.findAlternative:
        return _handleFindAlternative(text);
      case ChatIntent.analyzePatterns:
        return _handleAnalyzePatterns();
      case ChatIntent.searchPlatform:
        return _handleSearchPlatform(text);
      default:
        return _handleSearchDrug(text);
    }
  }

  // ── إضافة ناقص ──────────────────────────────────────────────────
  Future<ChatResponse> _handleAddShortage(String text) async {
    final n = _normalize(text);
    const stopWords = {
      'اضف','أضف','ضيف','سجل','دخل','ناقص','نواقص','دواء','عقار','في','الى','ل','دوا'
    };
    final words =
        n.split(' ').where((w) => !stopWords.contains(w) && w.length > 1).toList();
    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب اسم الدواء مثلاً:\n"أضف دواء باراسيتامول"',
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
      text: '✅ تم إضافة "$drugName" للنواقص!\n\nيمكنك إرساله للمندوبين من شاشة النواقص.',
      intent: ChatIntent.addShortage,
      success: true,
      actionData: {'drug': drugName, 'action': 'add_shortage'},
    );
  }

  // ── عرض النواقص ──────────────────────────────────────────────────
  Future<ChatResponse> _handleShowShortages({String? status}) async {
    final shortages = await DatabaseHelper.instance.getShortages(status: status);
    if (shortages.isEmpty) {
      return ChatResponse(
        text: status == 'pending'
            ? '🎉 مفيش نواقص معلقة حالياً!'
            : '📭 مفيش نواقص مسجلة حالياً.',
        intent: ChatIntent.showShortages,
      );
    }
    const statusIcons = {
      'pending': '⏳',
      'covered': '✅',
      'offered': '📦',
      'stubborn': '🔴',
    };
    final label = status == 'pending' ? 'المعلقة' : 'الكل';
    final lines = shortages.take(10).map((s) {
      final icon = statusIcons[s['status']] ?? '💊';
      return '$icon ${s['name']} | ${s['company']}';
    }).join('\n');
    final more = shortages.length > 10 ? '\n\n...و ${shortages.length - 10} أكثر' : '';
    return ChatResponse(
      text: '📋 النواقص $label (${shortages.length}):\n\n$lines$more',
      intent: ChatIntent.showShortages,
    );
  }

  // ── تعليم متوفر ──────────────────────────────────────────────────
  Future<ChatResponse> _handleMarkCovered(String text) async {
    final n = _normalize(text);
    const stop = {'تم','وجد','اتوفر','كامل','غطي','غطى','توفر','اتغطى'};
    final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب اسم الدواء مثلاً:\n"تم توفير باراسيتامول"',
        intent: ChatIntent.markCovered,
        success: false,
      );
    }
    final drugName = words.join(' ');
    final db = await DatabaseHelper.instance.database;
    final results = await db.query(
      'shortages',
      where: "name LIKE ? AND status != 'covered'",
      whereArgs: ['%$drugName%'],
    );
    if (results.isEmpty) {
      return ChatResponse(
        text: '❌ مش لاقي "$drugName" في النواقص المعلقة.',
        intent: ChatIntent.markCovered,
        success: false,
      );
    }
    for (final s in results) {
      await DatabaseHelper.instance
          .updateShortage(s['id'] as int, {'status': 'covered'});
    }
    return ChatResponse(
      text: '✅ تم تعليم "${results.first['name']}" كـ متوفر!',
      intent: ChatIntent.markCovered,
    );
  }

  // ── دين عميل ──────────────────────────────────────────────────
  Future<ChatResponse> _handleCustomerDebt(String text) async {
    final n = _normalize(text);
    const stop = {'ديون','دين','مدين','مديون','عميل','كام','بكام','فين'};
    final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) return _handleShowDebts();
    final name = words.join(' ');
    final db = await DatabaseHelper.instance.database;
    final results =
        await db.query('customers', where: 'name LIKE ?', whereArgs: ['%$name%']);
    if (results.isEmpty) {
      return ChatResponse(
        text: '❌ مش لاقي عميل باسم "$name".',
        intent: ChatIntent.checkCustomerDebt,
        success: false,
      );
    }
    final c = results.first;
    final debt = (c['total_debt'] as num).toDouble();
    final emoji = debt > 500 ? '🔴' : debt > 0 ? '🟡' : '✅';
    return ChatResponse(
      text: '$emoji العميل: ${c['name']}\n💰 الدين: ${debt.toStringAsFixed(2)} ج.م\n📱 ${c['phone'] ?? "مش محدد"}',
      intent: ChatIntent.checkCustomerDebt,
    );
  }

  // ── كل الديون ──────────────────────────────────────────────────
  Future<ChatResponse> _handleShowDebts() async {
    final customers = await DatabaseHelper.instance.getCustomers();
    final withDebt =
        customers.where((c) => (c['total_debt'] as num) > 0).toList();
    if (withDebt.isEmpty) {
      return ChatResponse(text: '🎉 مفيش ديون حالياً!', intent: ChatIntent.showDebts);
    }
    final total = withDebt.fold<double>(
        0, (sum, c) => sum + (c['total_debt'] as num).toDouble());
    final lines = withDebt
        .take(8)
        .map((c) =>
            '• ${c['name']}: ${(c['total_debt'] as num).toStringAsFixed(0)} ج.م')
        .join('\n');
    return ChatResponse(
      text: '💰 الديون المتراكمة:\n\n$lines\n\n📊 الإجمالي: ${total.toStringAsFixed(2)} ج.م',
      intent: ChatIntent.showDebts,
    );
  }

  // ── المندوبين ──────────────────────────────────────────────────
  Future<ChatResponse> _handleShowReps() async {
    final reps = await DatabaseHelper.instance.getReps();
    if (reps.isEmpty) {
      return ChatResponse(
        text: '📭 مفيش مندوبين مسجلين.\nأضفهم من شاشة المندوبين.',
        intent: ChatIntent.showReps,
      );
    }
    final lines = reps.take(6).map((r) {
      final stars = '⭐' * (((r['rating'] as int?) ?? 3).clamp(1, 5));
      return '👤 ${r['name']} | ${r['company'] ?? "غير محدد"}\n   $stars | غطى ${r['total_covered'] ?? 0} صنف';
    }).join('\n\n');
    return ChatResponse(
      text: '👥 المندوبون (${reps.length}):\n\n$lines',
      intent: ChatIntent.showReps,
    );
  }

  // ── الإحصائيات ──────────────────────────────────────────────────
  Future<ChatResponse> _handleShowStats() async {
    final stats = await DatabaseHelper.instance.getShortageStats();
    final totalDebt = await DatabaseHelper.instance.getTotalDebt();
    final currency = await DatabaseHelper.instance.getCurrency();
    return ChatResponse(
      text: '📊 ملخص اليوم:\n\n'
          '💊 النواقص: ${stats['total']} صنف\n'
          '  ⏳ معلق: ${stats['pending']}\n'
          '  ✅ متوفر: ${stats['covered']}\n'
          '  📦 مُعروض: ${stats['offered']}\n'
          '  🔴 عنيد: ${stats['stubborn']}\n\n'
          '💰 إجمالي الديون: ${totalDebt.toStringAsFixed(2)} $currency',
      intent: ChatIntent.showStats,
    );
  }

  // ── بدائل الأدوية ──────────────────────────────────────────────────
  Future<ChatResponse> _handleFindAlternative(String text) async {
    final n = _normalize(text);
    const stop = {'بديل','بدائل','بدل','عوض','لـ','ل','دواء','عقار'};
    final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب اسم الدواء مثلاً:\n"بديل بروفين"',
        intent: ChatIntent.findAlternative, success: false,
      );
    }
    final drugName = words.join(' ');
    final dictionary = await _loadDictionary();
    if (dictionary.isEmpty) {
      return ChatResponse(
        text: '📖 القاموس فارغ! ارفع قاموس الأدوية من الإعدادات أولاً.',
        intent: ChatIntent.findAlternative, success: false,
      );
    }
    final original = dictionary.where((d) {
      final en = d['enName']?.toString().toLowerCase() ?? '';
      final ar = d['arName']?.toString().toLowerCase() ?? '';
      return en.contains(drugName.toLowerCase()) || ar.contains(drugName.toLowerCase());
    }).toList();
    if (original.isEmpty) {
      return ChatResponse(
        text: '❌ مش لاقي "$drugName" في القاموس.',
        intent: ChatIntent.findAlternative, success: false,
      );
    }
    final activeIngredient = original.first['activeIngredient']?.toString() ?? '';
    if (activeIngredient.isEmpty) {
      return ChatResponse(
        text: '⚠️ "${original.first['enName']}" مش مسجل ليه مادة فعالة في القاموس.',
        intent: ChatIntent.findAlternative, success: false,
      );
    }
    final alternatives = dictionary.where((d) {
      final act = d['activeIngredient']?.toString().toLowerCase() ?? '';
      final en = d['enName']?.toString() ?? '';
      return act.contains(activeIngredient.toLowerCase()) && en != original.first['enName'];
    }).take(8).toList();
    if (alternatives.isEmpty) {
      return ChatResponse(
        text: '🔍 "${original.first['enName']}"\n🧪 المادة الفعالة: $activeIngredient\n\n❌ مفيش بدائل بنفس المادة الفعالة.',
        intent: ChatIntent.findAlternative,
      );
    }
    final lines = alternatives.map((d) {
      return '💊 ${d['enName']}${d['arName']?.toString().isNotEmpty == true ? " (${d['arName']})" : ""}';
    }).join('\n');
    return ChatResponse(
      text: '🔄 بدائل "${original.first['enName']}":\n🧪 المادة الفعالة: $activeIngredient\n\n$lines',
      intent: ChatIntent.findAlternative,
    );
  }

  // ── تحليل أنماط النواقص ──────────────────────────────────────────────────
  Future<ChatResponse> _handleAnalyzePatterns() async {
    final db = await DatabaseHelper.instance.database;
    final all = await db.query('shortages', orderBy: 'created_at DESC');
    if (all.isEmpty) {
      return ChatResponse(text: '📭 مفيش نواقص مسجلة للتحليل.', intent: ChatIntent.analyzePatterns);
    }
    final freq = <String, int>{};
    for (final s in all) {
      final name = s['name']?.toString() ?? '';
      freq[name] = (freq[name] ?? 0) + 1;
    }
    final sorted = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(10).toList();
    final stubborn = all.where((s) => s['status'] == 'stubborn').length;
    final covered = all.where((s) => s['status'] == 'covered').length;
    final rate = all.isNotEmpty ? ((covered / all.length) * 100).toStringAsFixed(0) : '0';
    final lines = top.asMap().entries.map((e) {
      final medal = e.key < 3 ? ['🥇','🥈','🥉'][e.key] : '${e.key + 1}.';
      return '$medal ${e.value.key} (${e.value.value} مرة)';
    }).join('\n');
    return ChatResponse(
      text: '📈 تحليل أنماط النواقص:\n\n'
          '🔢 إجمالي: ${all.length} صنف\n'
          '✅ نسبة التغطية: $rate%\n'
          '🔴 مستعصي: $stubborn صنف\n\n'
          '🏆 الأكثر تكراراً:\n$lines\n\n'
          '💡 نصيحة: خزّن الأدوية الأكثر تكراراً بكميات أكبر!',
      intent: ChatIntent.analyzePatterns,
    );
  }

  // ── البحث في منصات الأدوية ──────────────────────────────────────────────────
  Future<ChatResponse> _handleSearchPlatform(String text) async {
    final n = _normalize(text);
    const stop = {'ابحث','دور','عن','في','سعر','اسعار','اطلب','طلب','منصة','منصات','شركة','شركات','اونلاين','من','لي','لى','عاوز','عايز'};
    final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
    if (words.isEmpty) {
      return ChatResponse(
        text: '❓ اكتب اسم الدواء مثلاً:\n"ابحث عن بروفين"\n"سعر أموكسيسيللين"',
        intent: ChatIntent.searchPlatform, success: false,
      );
    }
    final drugName = words.join(' ');
    final platforms = await PlatformService.instance.getPlatforms();
    if (platforms.isEmpty) {
      return ChatResponse(
        text: '📱 مفيش منصات مضافة!\n\n'
            'روح الإعدادات ← منصات الأدوية\n'
            'وأضف منصات شركات الأدوية اللي بتتعامل معاها.\n\n'
            '💡 هتحتاج:\n'
            '• اسم المنصة\n'
            '• رابط الـ API\n'
            '• مفتاح الـ API (من حسابك في المنصة)',
        intent: ChatIntent.searchPlatform, success: false,
      );
    }

    final results = await PlatformService.instance.searchAll(drugName);
    if (results.isEmpty) {
      return ChatResponse(
        text: '🔍 بحثت في ${platforms.length} منصة عن "$drugName"\n\n'
            '❌ مش لاقي نتائج.\n'
            '💡 جرب اسم تاني أو تأكد من إعدادات المنصات.',
        intent: ChatIntent.searchPlatform,
      );
    }

    final buf = StringBuffer('🔍 نتائج "$drugName" من ${results.length} منصة:\n\n');
    for (final entry in results.entries) {
      buf.writeln('📦 ${entry.key}:');
      for (final r in entry.value) {
        final avail = r.available ? '✅' : '❌';
        final priceStr = '${r.price.toStringAsFixed(2)}';
        buf.write('  $avail ${r.drugName} - $priceStr');
        if (r.discount > 0) {
          buf.write(' (خصم ${r.discount.toStringAsFixed(0)}% → ${r.finalPrice.toStringAsFixed(2)})');
        }
        buf.writeln();
      }
      buf.writeln();
    }
    buf.writeln('💡 للطلب تواصل مع المنصة مباشرة من حسابك.');

    return ChatResponse(
      text: buf.toString().trim(),
      intent: ChatIntent.searchPlatform,
    );
  }

  // ── مطابقة ضبابية (fuzzy) ──────────────────────────────────────────────────
  bool _fuzzyMatch(String query, String text) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return false;
    final t = text.toLowerCase();
    if (t.contains(q)) return true;
    // مطابقة حروف متتابعة
    int i = 0;
    for (int j = 0; j < t.length && i < q.length; j++) {
      if (t[j] == q[i]) i++;
    }
    return i == q.length;
  }

  // ── تحميل القاموس من الإعدادات ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _loadDictionary() async {
    final dictStr =
        await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        return decoded.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    // محاولة القاموس القديم
    final oldStr =
        await DatabaseHelper.instance.getSetting('drug_dictionary');
    if (oldStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(oldStr);
        return decoded.map((s) => <String, dynamic>{'enName': s.toString()}).toList();
      } catch (_) {}
    }
    return [];
  }

  // ── البحث عن دواء: القاموس → النواقص → API ──────────────────────────────────
  Future<ChatResponse> _handleSearchDrug(String text) async {
    final n = _normalize(text);
    final terms = text.split(RegExp(r'[\s/]+')).where((t) => t.isNotEmpty).toList();

    // 1️⃣ البحث في القاموس أولاً
    final dictionary = await _loadDictionary();
    if (dictionary.isNotEmpty) {
      final matches = dictionary.where((drug) {
        final en = drug['enName']?.toString() ?? '';
        final ar = drug['arName']?.toString() ?? '';
        final act = drug['activeIngredient']?.toString() ?? '';
        final bar = drug['barcode']?.toString() ?? '';
        return terms.every((term) =>
            _fuzzyMatch(term, en) ||
            _fuzzyMatch(term, ar) ||
            _fuzzyMatch(term, act) ||
            _fuzzyMatch(term, bar));
      }).take(8).toList();

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
          text: '📖 وجدت في القاموس (${matches.length} نتيجة):\n\n$lines\n\n💡 جرب: "أضف دواء ${matches.first['enName']}"',
          intent: ChatIntent.searchDrug,
        );
      }
    }

    // 2️⃣ البحث في النواقص المحلية
    final db = await DatabaseHelper.instance.database;
    final localResults = await db.query(
      'shortages',
      where: 'name LIKE ?',
      whereArgs: ['%$n%'],
      limit: 5,
    );
    if (localResults.isNotEmpty) {
      const statusLabel = {
        'pending': '⏳ معلق',
        'covered': '✅ متوفر',
        'offered': '📦 مُعروض',
        'stubborn': '🔴 عنيد',
      };
      final lines = localResults
          .map((s) => '💊 ${s['name']} | ${statusLabel[s['status']] ?? s['status']}')
          .join('\n');
      return ChatResponse(
        text: '🗄️ وجدت في النواقص:\n\n$lines',
        intent: ChatIntent.searchDrug,
      );
    }

    // 3️⃣ البحث عبر API
    return _searchViaApi(text);
  }

  // ── البحث عبر API ──────────────────────────────────────────────────
  Future<ChatResponse> _searchViaApi(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('custom_api_url') ?? '';
    final customKey = prefs.getString('custom_api_key') ?? '';
    final customType = prefs.getString('custom_api_type') ?? 'openai';

    try {
      // API مخصص من المستخدم
      if (customUrl.isNotEmpty && customKey.isNotEmpty) {
        if (customType == 'openai') {
          return await _callOpenAIApi(customUrl, customKey, query);
        }
        final res = await http
            .post(
              Uri.parse(customUrl),
              headers: {
                'Authorization': 'Bearer $customKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'query': query, 'q': query}),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final d = jsonDecode(res.body);
          final answer = d['answer'] ?? d['response'] ?? d['text'] ?? d['AbstractText'] ?? res.body;
          return ChatResponse(
            text: '🌐 نتيجة البحث:\n\n$answer',
            intent: ChatIntent.searchDrug,
          );
        }
      }
      // API مجاني افتراضي
      return await _callDuckDuckGo(query);
    } catch (e) {
      return ChatResponse(
        text: '⚠️ "$query" مش موجود محلياً ومفيش اتصال.\n\nجرب: "أضف دواء $query"',
        intent: ChatIntent.searchDrug,
        success: false,
      );
    }
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
            intent: ChatIntent.searchDrug,
          );
        }
      }
    } catch (_) {}
    return ChatResponse(
      text: '🔍 "$query" مش موجود في قاعدة البيانات.\n\n'
          'مش لاقيش معلومات كافية أونلاين.\n\n'
          '💡 جرب:\n'
          '• "أضف دواء $query" لإضافته للنواقص\n'
          '• أضف API خاص من إعدادات الشات',
      intent: ChatIntent.searchDrug,
      success: false,
    );
  }

  // ── OpenAI Compatible ──────────────────────────────────────────────────
  Future<ChatResponse> _callOpenAIApi(
      String url, String apiKey, String query) async {
    final endpoint =
        url.endsWith('/') ? '${url}chat/completions' : '$url/chat/completions';
    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gpt-3.5-turbo',
            'messages': [
              {
                'role': 'system',
                'content': 'أنت مساعد صيدلي متخصص. أجب بالعربية بشكل مختصر ومفيد.'
              },
              {'role': 'user', 'content': query},
            ],
            'max_tokens': 400,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      final answer = d['choices']?[0]?['message']?['content'] ?? 'لا يوجد رد';
      return ChatResponse(
        text: '🤖 $answer',
        intent: ChatIntent.searchDrug,
      );
    }
    throw Exception('API Error ${res.statusCode}');
  }

  // ── نصوص المساعدة ──────────────────────────────────────────────────
  String _helpText() => '''🤖 أنا مساعدك الذكي - حكيم

📋 النواقص:
• "أضف دواء [اسم]" ← إضافة للنواقص
• "النواقص" ← عرض الكل
• "النواقص المعلقة" ← فقط المعلقة
• "تم توفير [اسم]" ← تعليم كمتوفر

🔄 البدائل:
• "بديل [اسم]" ← بدائل بنفس المادة الفعالة

📈 التحليل:
• "تحليل النواقص" ← أنماط وتكرارات

💰 الديون:
• "الديون" ← عرض الكل
• "دين [اسم العميل]" ← عميل محدد

👥 المندوبين:
• "المندوبين" ← عرض القائمة

📊 التقارير:
• "ملخص اليوم" ← إحصائيات

🔍 البحث:
• اكتب اسم الدواء مباشرة

⚙️ API:
• اضغط أيقونة ⚙️ لإضافة API خاص

📱 منصات الأدوية:
• "ابحث عن [اسم]" ← بحث في كل المنصات
• "سعر [اسم]" ← مقارنة الأسعار
• أضف منصاتك من الإعدادات''';

  String _apiHelpText() => '''⚙️ إعدادات الذكاء الاصطناعي

🔗 الأنواع المدعومة:
• OpenAI / ChatGPT
• أي API متوافق مع OpenAI
• APIs مخصصة (JSON)

💡 اضغط أيقونة ⚙️ في أعلى الشاشة لإضافة مفتاحك.''';

  // ── اقتراح أسماء أدوية عبر API (للـ autocomplete) ──────────────────────────
  Future<List<Map<String, dynamic>>> suggestDrugNames(String query) async {
    if (query.trim().length < 3) return [];
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('custom_api_url') ?? '';
    final key = prefs.getString('custom_api_key') ?? '';

    // OpenAI if available
    if (url.isNotEmpty && key.isNotEmpty) {
      try {
        final endpoint = url.endsWith('/')
            ? '${url}chat/completions'
            : '$url/chat/completions';
        final res = await http
            .post(Uri.parse(endpoint),
                headers: {
                  'Authorization': 'Bearer $key',
                  'Content-Type': 'application/json'
                },
                body: jsonEncode({
                  'model': 'gpt-3.5-turbo',
                  'messages': [
                    {
                      'role': 'system',
                      'content':
                          'أنت قاموس أدوية. أعطني 5 أسماء أدوية تجارية تطابق أو تشبه الاسم المطلوب. أعد كل اسم في سطر منفصل بدون ترقيم أو شرح.'
                    },
                    {'role': 'user', 'content': query},
                  ],
                  'max_tokens': 80,
                  'temperature': 0.3,
                }))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final d = jsonDecode(res.body);
          final text = d['choices']?[0]?['message']?['content'] ?? '';
          return text
              .toString()
              .split('\n')
              .map((s) => s.replaceAll(RegExp(r'^[\d\-\.\)]+\s*'), '').trim())
              .where((s) => s.isNotEmpty && s.length > 2)
              .take(5)
              .map((s) =>
                  <String, dynamic>{'enName': s, 'arName': '', 'source': 'ai'})
              .toList();
        }
      } catch (_) {}
    }

    // DuckDuckGo fallback
    try {
      final ddgUrl =
          'https://api.duckduckgo.com/?q=${Uri.encodeComponent("$query drug")}&format=json&no_html=1';
      final res = await http
          .get(Uri.parse(ddgUrl))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final topics = d['RelatedTopics'] as List? ?? [];
        return topics
            .take(5)
            .map((t) {
              final text = t['Text']?.toString() ?? '';
              final name = text.split(' - ').first.split(':').first.trim();
              return <String, dynamic>{
                'enName': name,
                'arName': '',
                'source': 'web'
              };
            })
            .where((m) => (m['enName'] as String).length > 2)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── إدارة إعدادات API ──────────────────────────────────────────────────
  Future<void> saveApiSettings({
    required String url,
    required String key,
    required String type,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_api_url', url);
    await prefs.setString('custom_api_key', key);
    await prefs.setString('custom_api_type', type);
    await prefs.setString('custom_api_name', name);
  }

  Future<Map<String, String>> getApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'url': prefs.getString('custom_api_url') ?? '',
      'key': prefs.getString('custom_api_key') ?? '',
      'type': prefs.getString('custom_api_type') ?? 'openai',
      'name': prefs.getString('custom_api_name') ?? '',
    };
  }

  Future<void> clearApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_api_url');
    await prefs.remove('custom_api_key');
    await prefs.remove('custom_api_type');
    await prefs.remove('custom_api_name');
  }
}
