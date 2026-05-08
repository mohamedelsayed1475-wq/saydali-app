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
addCustomer,
addShortagesFromImage,
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
if (RegExp(r'(اعمل|ضيف|سجل|انشئ|أنشئ)').hasMatch(n) &&
RegExp(r'(حساب|عميل|زبون)').hasMatch(n)) {
return ChatIntent.addCustomer;
}
if (RegExp(r'(ضيف|اضف|سجل|استخرج)').hasMatch(n) &&
RegExp(r'(الاصناف|النواقص|الادوية|الادويه|الصور|الصوره|الصورة|روشته|روشتة|الصنف|صنف|صوره)').hasMatch(n)) {
return ChatIntent.addShortagesFromImage;
}
if (n.length > 2) return ChatIntent.searchDrug;
return ChatIntent.unknown;
}

// ── تنفيذ الأمر ──────────────────────────────────────────────────
Future<ChatResponse> execute(String text, {List<String>? filePaths}) async {
final intent = _classify(text);

if (intent == ChatIntent.addShortagesFromImage) {
return _extractAndAddItemsFromImage(text, filePaths);
}

if (filePaths != null && filePaths.isNotEmpty && intent != ChatIntent.addShortagesFromImage) {
return _searchViaApi(text, filePaths: filePaths);
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
return ChatResponse(text: _apiHelpText(), intent: ChatIntent.apiSettings);
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
text: '❓ اكتب اسم الدواء مثلاً:\n\n"أضف دواء باراسيتامول"',
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
}).join('\n\n');
final more = shortages.length > 10 ? '\n\n...و ${shortages.length - 10} أكثر' : '';
return ChatResponse(
text: '📋 النواقص $label (${shortages.length}):\n\n$lines$more',
intent: ChatIntent.showShortages,
);
}

// ── إضافة عميل ──────────────────────────────────────────────────
Future<ChatResponse> _handleAddCustomer(String text) async {
final nameRegex = RegExp(r'(?:باسم|اسم|اسمه)\s+([^\s\d]+(?:\s+[^\s\d]+)*)');
final phoneRegex = RegExp(r'(?:ورقمه|رقم|رقمه|تليفونه|موبايله)\s+([\d\-\+]+)');

final nameMatch = nameRegex.firstMatch(text);
final phoneMatch = phoneRegex.firstMatch(text);

if (nameMatch == null) {
return ChatResponse(
text: '❓ يرجى كتابة الأمر بوضوح مثل:\n\n"اعمل حساب باسم محمد السيد ورقمه 01012345678"', 
intent: ChatIntent.addCustomer, 
success: false
);
}

final name = nameMatch.group(1)!.trim();
final phone = phoneMatch != null ? phoneMatch.group(1)!.trim() : '';

await DatabaseHelper.instance.insertCustomer({
'name': name,
'phone': phone,
'address': '',
});

return ChatResponse(
text: '✅ تم إنشاء حساب للعميل "$name" ${phone.isNotEmpty ? "برقم $phone" : ""} بنجاح!',
intent: ChatIntent.addCustomer,
);
}

// ── استخراج النواقص من صورة ──────────────────────────────────────────────────
Future<ChatResponse> _extractAndAddItemsFromImage(String text, List<String>? filePaths) async {
final prefs = await SharedPreferences.getInstance();
final customKey = prefs.getString('custom_api_key') ?? '';
final customType = prefs.getString('custom_api_type') ?? 'openai';

if (filePaths == null || filePaths.isEmpty) {
return ChatResponse(text: '❓ أين الصورة؟ قم بإرفاق صورة أولاً مع رسالتك.', intent: ChatIntent.addShortagesFromImage, success: false);
}

// محاولة استخدام Gemini أولاً لو موجود (لأنه الأذكى في الاستخراج المنسق)
if (customKey.isNotEmpty && customType == 'gemini') {
try {
final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: customKey);
final prompt = 'استخرج جميع أسماء الأدوية أو الأصناف من هذه الصورة وضعها في قائمة JSON بالضبط بهذا الشكل: [{"name": "اسم الدواء", "company": "اسم الشركة", "quantity": 1}]. لا تقم بإضافة أي نصوص أو شروحات إضافية غير مصفوفة الـ JSON فقط.';

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
final quantity = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

await DatabaseHelper.instance.insertShortage({
'name': name,
'company': company,
'quantity': quantity,
'status': 'pending',
'is_urgent': 0,
'notes': 'مستخرج من صورة عبر ذكاء اصطناعي',
});
buffer.writeln('💊 $name | $company');
added++;
}
if (added > 0) {
return ChatResponse(text: '✅ تم استخراج وإضافة $added صنف للنواقص بنجاح!\n\n${buffer.toString()}', intent: ChatIntent.addShortagesFromImage);
}
}
} catch (e) {
// Fallback to offline...
}
}

// الاستخراج المحلي (بدون إنترنت/بدون API)
try {
final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
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
// تجاهل السطور القصيرة جداً والأرقام
if (line.isEmpty || line.length <= 2 || RegExp(r'^\d+$').hasMatch(line)) continue;

// بعض الفلاتر البسيطة
if (line.toLowerCase().contains('total') || line.toLowerCase().contains('discount')) continue;

await DatabaseHelper.instance.insertShortage({
'name': line,
'company': 'غير محدد',
'quantity': 1,
'status': 'pending',
'is_urgent': 0,
'notes': 'مستخرج من صورة محلياً (تأكد من صحة الاسم)',
});
buffer.writeln('💊 $line');
added++;
if(added >= 20) break; // للحد من إضافة نصوص عشوائية كثيرة
}
}
}
textRecognizer.close();

if (added > 0) {
return ChatResponse(text: '✅ قرأت الصورة محلياً (بدون نت) وتم استخراج $added سطر ووضعه في النواقص:\n\n${buffer.toString()}\n\n💡 ملاحظة: راجع شاشة النواقص لتعديل الأسماء أو حذف المكتوب بالخطأ.', intent: ChatIntent.addShortagesFromImage);
} else {
return ChatResponse(text: '❌ لم أستطع إيجاد نصوص واضحة في الصورة.', intent: ChatIntent.addShortagesFromImage, success: false);
}
} catch (e) {
return ChatResponse(text: '⚠️ استخراج البيانات محلياً فشل. $e', intent: ChatIntent.addShortagesFromImage, success: false);
}
}

// ── تعليم متوفر ──────────────────────────────────────────────────
Future<ChatResponse> _handleMarkCovered(String text) async {
final n = _normalize(text);
const stop = {'تم','وجد','اتوفر','كامل','غطي','غطى','توفر','اتغطى'};
final words = n.split(' ').where((w) => !stop.contains(w) && w.length > 1).toList();
if (words.isEmpty) {
return ChatResponse(
text: '❓ اكتب اسم الدواء مثلاً:\n\n"تم توفير باراسيتامول"',
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
text: '$emoji العميل: ${c['name']}\n\n💰 الدين: ${debt.toStringAsFixed(2)} ج.م\n\n📱 ${c['phone'] ?? "مش محدد"}',
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
.join('\n\n');
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
text: '📭 مفيش مندوبين مسجلين.\n\nأضفهم من شاشة المندوبين.',
intent: ChatIntent.showReps,
);
}
final lines = reps.take(6).map((r) {
final stars = '⭐' * (((r['rating'] as int?) ?? 3).clamp(1, 5));
return '👤 ${r['name']} | ${r['company'] ?? "غير محدد"}\n\n   $stars | غطى ${r['total_covered'] ?? 0} صنف';
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
'💊 النواقص: ${stats['total']} صنف\n\n'
'  ⏳ معلق: ${stats['pending']}\n\n'
'  ✅ متوفر: ${stats['covered']}\n\n'
'  📦 مُعروض: ${stats['offered']}\n\n'
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
text: '❓ اكتب اسم الدواء مثلاً:\n\n"بديل بروفين"',
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
text: '🔍 "${original.first['enName']}"\n\n🧪 المادة الفعالة: $activeIngredient\n\n❌ مفيش بدائل بنفس المادة الفعالة.',
intent: ChatIntent.findAlternative,
);
}
final lines = alternatives.map((d) {
return '💊 ${d['enName']}${d['arName']?.toString().isNotEmpty == true ? " (${d['arName']})" : ""}';
}).join('\n\n');
return ChatResponse(
text: '🔄 بدائل "${original.first['enName']}":\n\n🧪 المادة الفعالة: $activeIngredient\n\n$lines',
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
}).join('\n\n');
return ChatResponse(
text: '📈 تحليل أنماط النواقص:\n\n'
'🔢 إجمالي: ${all.length} صنف\n\n'
'✅ نسبة التغطية: $rate%\n\n'
'🔴 مستعصي: $stubborn صنف\n\n'
'🏆 الأكثر تكراراً:\n\n$lines\n\n'
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
text: '❓ اكتب اسم الدواء مثلاً:\n\n"ابحث عن بروفين"\n\n"سعر أموكسيسيللين"',
intent: ChatIntent.searchPlatform, success: false,
);
}
final drugName = words.join(' ');
final platforms = await PlatformService.instance.getPlatforms();
if (platforms.isEmpty) {
return ChatResponse(
text: '📱 مفيش منصات مضافة!\n\n'
'روح الإعدادات ← منصات الأدوية\n\n'
'وأضف منصات شركات الأدوية اللي بتتعامل معاها.\n\n'
'💡 هتحتاج:\n\n'
'• اسم المنصة\n\n'
'• رابط الـ API\n\n'
'• مفتاح الـ API (من حسابك في المنصة)',
intent: ChatIntent.searchPlatform, success: false,
);
}

final results = await PlatformService.instance.searchAll(drugName);
if (results.isEmpty) {
return ChatResponse(
text: '🔍 بحثت في ${platforms.length} منصة عن "$drugName"\n\n'
'❌ مش لاقي نتائج.\n\n'
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
String q = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
if (q.isEmpty) return true;
String t = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
if (t.contains(q)) return true;

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
return parts.join('\n\n');
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
.join('\n\n');
return ChatResponse(
text: '🗄️ وجدت في النواقص:\n\n$lines',
intent: ChatIntent.searchDrug,
);
}

// 3️⃣ البحث عبر API
return _searchViaApi(text);
}

// ── البحث عبر API ──────────────────────────────────────────────────
Future<ChatResponse> _searchViaApi(String query, {List<String>? filePaths}) async {
final prefs = await SharedPreferences.getInstance();
final customUrl = prefs.getString('custom_api_url') ?? '';
final customKey = prefs.getString('custom_api_key') ?? '';
final customType = prefs.getString('custom_api_type') ?? 'openai';
final savedFiles = prefs.getStringList('custom_api_files') ?? [];

final allFiles = <String>[];
if (filePaths != null) allFiles.addAll(filePaths);
allFiles.addAll(savedFiles);

// 💡 بحث محلي وذكي داخل الملفات أولاً (سريع ومجاني)
if (allFiles.isNotEmpty) {
final localRes = await _searchLocalFiles(query.isEmpty ? 'ملخص' : query, allFiles);
if (localRes.success) {
return localRes; // إذا وجدها في الملفات، يعرضها مباشرة
}
}

try {
if (customKey.isNotEmpty && customType == 'gemini') {
final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: customKey);
final prompt = query.isEmpty && allFiles.isNotEmpty ? 'اشرح ما في هذه الملفات.' : query;
final parts = <Part>[TextPart(prompt)];

for (final path in allFiles) {
if (!File(path).existsSync()) continue;
final bytes = File(path).readAsBytesSync();
final ext = path.split('.').last.toLowerCase();
String mime = 'image/jpeg';
if (ext == 'png') mime = 'image/png';
if (ext == 'pdf') mime = 'application/pdf';
if (ext == 'xlsx') mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
if (ext == 'xls') mime = 'application/vnd.ms-excel';
if (ext == 'csv') mime = 'text/csv';
if (ext == 'doc') mime = 'application/msword';
if (ext == 'docx') mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
parts.add(DataPart(mime, bytes));
}

final response = await model.generateContent([Content.multi(parts)]);
return ChatResponse(
text: response.text ?? 'لا توجد إجابة',
intent: ChatIntent.searchDrug,
);
}

// API مخصص من المستخدم (OpenAI)
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

// ── بحث ذكي ومحلي داخل الملفات المرفوعة ───────────────────────────────
Future<ChatResponse> _searchLocalFiles(String query, List<String> files) async {
final buffer = StringBuffer();
int foundCount = 0;

final terms = query.toLowerCase().split(' ').where((w) => w.length > 2).toList();
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
} else if (ext == 'xlsx' || ext == 'xls') {
final bytes = file.readAsBytesSync();
final excel = ex.Excel.decodeBytes(bytes);
final tb = StringBuffer();
for (final table in excel.tables.keys) {
for (final row in excel.tables[table]!.rows) {
tb.writeln(row.map((e) => e?.value?.toString() ?? '').join(' | '));
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
} else if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp') {
final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
final inputImage = InputImage.fromFilePath(path);
final recognizedText = await textRecognizer.processImage(inputImage);
text = recognizedText.text;
textRecognizer.close();
}
} catch (_) {}

if (text.isEmpty) continue;

final lines = text.split(RegExp(r'\n|\r|\. '));
for (final line in lines) {
// نستخدم البحث التقريبي المتقدم بدلاً من البحث الحرفي
bool matches = false;
if (terms.length == 1) {
matches = _fuzzyMatch(terms.first, line);
} else {
matches = terms.every((term) => line.toLowerCase().contains(term));
}

if (matches) {
if (buffer.length < 2000) {
final name = path.split(Platform.pathSeparator).last;
buffer.writeln('📄 من ملف ($name):');
buffer.writeln('"... ${line.trim()} ..."');
buffer.writeln();
foundCount++;
if (foundCount > 7) break;
}
}
}
if (foundCount > 7) break;
}

if (foundCount > 0) {
return ChatResponse(
text: '📚 بحثت محلياً (بدون إنترنت) في ملفاتك المرفقة ووجدت:\n\n${buffer.toString()}',
intent: ChatIntent.searchDrug,
);
}

return ChatResponse(
text: '❌ لم أجد أي معلومات عن "$query" داخل الملفات التي رفعتها.\n\n💡 جرب كلمة بحث أبسط.',
intent: ChatIntent.searchDrug,
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
intent: ChatIntent.searchDrug,
);
}
}
} catch (_) {}
return ChatResponse(
text: '🔍 "$query" مش موجود في قاعدة البيانات.\n\n'
'مش لاقيش معلومات كافية أونلاين.\n\n'
'💡 جرب:\n\n'
'• "أضف دواء $query" لإضافته للنواقص\n\n'
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

// 💡 1️⃣ البحث المحلي السريع في الملفات المرفوعة (مثل الإكسيل) 💡
final savedFiles = prefs.getStringList('custom_api_files') ?? [];
if (savedFiles.isNotEmpty) {
final localRes = await _searchLocalFiles(query, savedFiles);
if (localRes.success && localRes.text.contains('📄')) {
final lines = localRes.text.split('\n');
final foundItems = <String>{};
for (final line in lines) {
if (line.contains('"...') && _fuzzyMatch(query, line)) {
var clean = line.replaceAll('"...', '').replaceAll('..."', '').trim();
if (clean.contains('|')) {
clean = clean.split('|').firstWhere((p) => _fuzzyMatch(query, p), orElse: () => clean.split('|').first).trim();
}
if (clean.length > 2) foundItems.add(clean);
}
}
if (foundItems.isNotEmpty) {
return foundItems.take(5).map((s) => <String, dynamic>{'enName': s, 'arName': '', 'source': 'local_file'}).toList();
}
}
}

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
.timeout(const Duration(seconds: 2));
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
