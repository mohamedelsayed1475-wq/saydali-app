import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';
import '../providers/current_user_provider.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'rep_details_screen.dart';
import 'send_to_rep_screen.dart';
import 'shortages_screen.dart';

/// الشاشة الرئيسية الموحدة للمندوبين
/// تحتوي على تابان داخليان:
/// 1. "القائمة" — إدارة المندوبين وبياناتهم والطلبات المباشرة
/// 2. "الردود" — استقبال ومعالجة ردود المندوبين والمقارنة الذكية للأسعار
class RepsScreen extends StatefulWidget {
  final int initialTab;
  final String? initialCode;

  const RepsScreen({
    super.key,
    this.initialTab = 0,
    this.initialCode,
  });

  @override
  State<RepsScreen> createState() => _RepsScreenState();
}

class _RepsScreenState extends State<RepsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ─── متغيرات تاب "القائمة" ───
  List<Representative> _reps = [];
  bool _loadingReps = true;
  String _repsSearch = '';
  final _repsSearchController = TextEditingController();

  // ─── متغيرات تاب "الردود" ───
  late final TextEditingController _codeCtrl;
  bool _loadingResponse = false;
  String? _responseError;
  RepResponse? _response;
  String _responseSearchQuery = '';
  bool _showResponseSearch = false;
  String _currency = 'ج.م';
  String _pharmacyName = '';
  List<Map<String, dynamic>> _sentSessions = [];
  bool _loadingSessions = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: (widget.initialTab >= 0 && widget.initialTab < 2) ? widget.initialTab : 0,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _codeCtrl = TextEditingController(text: widget.initialCode ?? '');

    _loadReps();
    _loadCurrency();
    _loadPharmacyNameAndSessions();

    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tabController.animateTo(1);
        _fetchResponse();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _repsSearchController.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ==========================================
  // ─── دوال تاب "القائمة" (Reps Tab) ────────
  // ==========================================

  List<Representative> get _filteredReps {
    if (_repsSearch.isEmpty) return _reps;
    final q = _repsSearch.toLowerCase();
    return _reps.where((r) {
      return r.name.toLowerCase().contains(q) ||
          (r.company?.toLowerCase().contains(q) ?? false) ||
          (r.phone?.contains(q) ?? false);
    }).toList();
  }

  Future<void> _loadReps() async {
    if (mounted) {
      await context.read<RepsProvider>().load();
      if (mounted) {
        setState(() {
          _reps = context.read<RepsProvider>().reps;
          _loadingReps = false;
        });
      }
    }
  }

  Future<void> _showAddSheet({Representative? existing}) async {
    final userProvider = context.read<CurrentUserProvider>();
    if (!userProvider.canManageReps) {
      showSnack(context, '⛔ ليس لديك صلاحية إدارة المندوبين', isError: true);
      return;
    }
    final nameCtrl = TextEditingController(text: existing?.name);
    final companyCtrl = TextEditingController(text: existing?.company);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final notesCtrl = TextEditingController(text: existing?.notes);
    int rating = existing?.rating ?? 5;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                Text(existing == null ? '➕ إضافة مندوب' : '✏️ تعديل المندوب',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        if (await FlutterContacts.requestPermission(readonly: true)) {
                          final contact = await FlutterContacts.openExternalPick();
                          if (contact != null) {
                            final fullContact = await FlutterContacts.getContact(contact.id);
                            if (fullContact != null) {
                              setBS(() {
                                nameCtrl.text = fullContact.displayName;
                                if (fullContact.phones.isNotEmpty) {
                                  phoneCtrl.text = fullContact.phones.first.number;
                                }
                              });
                            }
                          }
                        } else {
                          showSnack(ctx, '⛔ تم رفض إذن جهات الاتصال', isError: true);
                        }
                      } catch (e) {
                        showSnack(ctx, 'تعذر فتح جهات الاتصال', isError: true);
                      }
                    },
                    icon: const Icon(Icons.contacts_rounded, size: 18),
                    label: const Text('إضافة من جهات الاتصال'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(hint: 'اسم المندوب *', controller: nameCtrl),
                const SizedBox(height: 10),
                AppTextField(hint: 'الشركة', controller: companyCtrl),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'رقم الهاتف',
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 10),
                AppTextField(
                    hint: 'ملاحظات', controller: notesCtrl, maxLines: 2),
                const SizedBox(height: 12),
                const Text('التقييم',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: List.generate(
                      5,
                      (i) => IconButton(
                            onPressed: () => setBS(() => rating = i + 1),
                            icon: Icon(
                              i < rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: AppColors.warning,
                              size: 30,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  text: existing == null ? 'إضافة' : 'حفظ',
                  onTap: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      showSnack(ctx, 'أدخل اسم المندوب', isError: true);
                      return;
                    }
                    final data = {
                      'name': name,
                      'company': companyCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'rating': rating,
                      'notes': notesCtrl.text.trim(),
                    };
                    if (existing == null) {
                      await context.read<RepsProvider>().add(data);
                    } else {
                      await context.read<RepsProvider>().update(existing.id!, data);
                    }
                    await DatabaseHelper.instance.logActivity(
                      assistantId: userProvider.currentAssistantId,
                      assistantName: userProvider.currentName,
                      action: existing == null ? 'إضافة مندوب' : 'تعديل مندوب',
                      details: '${existing == null ? "تم إضافة" : "تم تعديل"} المندوب: $name',
                      screen: 'reps',
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadReps();
                    if (mounted) {
                      showSnack(context, existing == null ? 'تم الإضافة ✅' : 'تم التعديل ✅');
                    }
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendShortages(Representative rep) async {
    final shortages = await DatabaseHelper.instance.getShortages(status: 'pending');
    if (shortages.isEmpty) {
      if (mounted) {
        showSnack(context, 'لا توجد نواقص بانتظار الرد', isError: true);
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ShortagesScreen()));
      }
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SendToRepScreen(rep: rep)),
    );
  }

  // ==========================================
  // ─── دوال تاب "الردود" (Response Tab) ─────
  // ==========================================

  Future<void> _loadPharmacyNameAndSessions() async {
    final name = await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدليتي';
    if (mounted) {
      setState(() {
        _pharmacyName = name;
      });
      await _fetchSentSessions();
    }
  }

  Future<void> _fetchSentSessions() async {
    if (_pharmacyName.isEmpty) return;
    if (mounted) setState(() => _loadingSessions = true);
    try {
      final sessions = await SupabaseService.instance.fetchPharmacySessions();
      if (mounted) {
        setState(() {
          _sentSessions = sessions;
          _loadingSessions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingSessions = false);
      }
    }
  }

  Future<void> _loadCurrency() async {
    final c = await DatabaseHelper.instance.getCurrency();
    if (mounted) setState(() => _currency = c);
  }

  Future<void> _searchGoogleImages(String query) async {
    if (query.trim().isEmpty) {
      showSnack(context, 'الرجاء إدخال اسم الدواء للبحث', isError: true);
      return;
    }
    final url = Uri.parse(
        'https://www.google.com/search?tbm=isch&q=${Uri.encodeComponent(query)}+دواء');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showSnack(context, 'تعذر فتح المتصفح', isError: true);
    }
  }

  Future<void> _fetchResponse() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length != 8) {
      setState(() => _responseError = 'الكود يجب أن يكون 8 أحرف');
      return;
    }

    setState(() {
      _loadingResponse = true;
      _responseError = null;
    });

    final result = await SupabaseService.instance.fetchResponseByCode(code);

    if (mounted) {
      setState(() {
        _loadingResponse = false;
        if (result.response != null) {
          _response = result.response;
        } else if (result.error != null) {
          _responseError = result.error;
        } else {
          _responseError = 'كود غير صحيح أو منتهي الصلاحية';
        }
      });

      if (result.response != null) {
        SupabaseService.instance.deleteSession(result.response!.sessionId);
      }
    }
  }

  Future<void> _processResponse(bool endDay) async {
    if (_response == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(endDay ? 'تأكيد إنهاء اليوم' : 'تأكيد الرد',
            style: const TextStyle(
                color: AppColors.textColor, fontWeight: FontWeight.w700)),
        content: Text(
          endDay
              ? 'سيتم:\n✅ تغطية ${_response!.availableItems.length} صنف متاح\n⚠️ تحويل ${_response!.unavailableItems.length} صنف لمستعصي'
              : 'سيتم:\n✅ تغطية ${_response!.availableItems.length} صنف متاح\n⏳ بقاء ${_response!.unavailableItems.length} صنف في قائمة الانتظار',
          style: const TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirm != true) return;

    final db = DatabaseHelper.instance;
    final shortagesData = await db.getShortages();

    final Map<String, List<int>> shortageMap = {};
    for (var s in shortagesData) {
      final key = s['name'].toString().trim().toLowerCase();
      shortageMap.putIfAbsent(key, () => []).add(s['id'] as int);
    }

    final dictStr = await db.getSetting('drug_dictionary_v2');
    bool dictUpdated = false;
    List<Map<String, dynamic>> dictionary = [];

    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        dictionary = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }

    for (final item in _response!.availableItems) {
      final key = item.drugName.trim().toLowerCase();
      if (shortageMap.containsKey(key)) {
        int remainingQty = item.quantity;
        for (final id in shortageMap[key]!) {
          if (remainingQty <= 0) break;
          final shortage = shortagesData.firstWhere((s) => s['id'] == id);
          final reqQty = (shortage['quantity'] as num?)?.toInt() ?? 1;

          if (remainingQty >= reqQty) {
            await db.updateShortage(id, {'status': 'covered'});
            remainingQty -= reqQty;
          } else {
            await db.updateShortage(id, {
              'status': 'covered',
              'quantity': remainingQty
            });

            await db.insertShortage({
              'name': shortage['name'],
              'company': shortage['company'],
              'quantity': reqQty - remainingQty,
              'status': 'pending',
              'is_urgent': shortage['is_urgent'],
              'notes': 'متبقي من طلبية سابقة (${_response!.repName})',
            });

            remainingQty = 0;
          }
        }
      }

      if (item.price > 0 && dictionary.isNotEmpty) {
        for (int i = 0; i < dictionary.length; i++) {
          final dictName = dictionary[i]['enName']?.toString().toLowerCase().trim() ?? '';
          if (dictName == key) {
            final currentPrice = double.tryParse(dictionary[i]['price']?.toString() ?? '0') ?? 0;
            if (item.price > currentPrice) {
              dictionary[i]['price'] = item.price;
              dictUpdated = true;
              debugPrint('✅ تم تحديث سعر ${item.drugName} من $currentPrice إلى ${item.price}');
            }
            break;
          }
        }
      }
    }

    if (dictUpdated) {
      await db.setSetting('drug_dictionary_v2', jsonEncode(dictionary));
    }

    for (final item in _response!.unavailableItems) {
      final key = item.drugName.trim().toLowerCase();
      if (item.repAlternative != null && item.repAlternative!.trim().isNotEmpty) {
        try {
          await db.addAlternativeIfNotExists(item.drugName, item.repAlternative!);
        } catch (e) {
          debugPrint('⚠️ خطأ في حفظ البديل محلياً: $e');
        }
      }

      if (shortageMap.containsKey(key)) {
        for (final id in shortageMap[key]!) {
          await db.updateShortage(id, {'status': endDay ? 'stubborn' : 'pending'});
        }
      } else {
        await db.insertShortage({
          'name': item.drugName.trim(),
          'company': item.company.isNotEmpty ? item.company : 'غير محدد',
          'quantity': item.quantity,
          'status': 'pending',
          'is_urgent': 0,
          'notes': 'تم الإضافة تلقائياً - قال المندوب ${_response!.repName}: مش موجود',
        });
      }
    }

    if (_response!.availableItems.isNotEmpty) {
      final orderItems = _response!.availableItems.map((item) => {
        'name': item.drugName,
        'company': item.company,
        'quantity': item.quantity,
        'price': item.price,
        'discount': item.discount,
        'finalPrice': item.finalPrice,
        'totalPrice': item.totalPrice,
      }).toList();

      final total = _response!.availableItems.fold(0.0, (s, i) => s + i.totalPrice);

      await db.insertRepOrder({
        'rep_name': _response!.repName,
        'items': jsonEncode(orderItems),
        'total': total,
        'is_paid': 0,
      });
    }

    if (mounted) {
      showSnack(context, endDay ? 'تم إنهاء اليوم ✅' : 'تم قبول الرد بنجاح ✅');

      if (_response!.availableItems.isNotEmpty) {
        await _comparePricesWithOtherReps();
      }

      setState(() {
        _response = null;
        _codeCtrl.clear();
      });
      _fetchSentSessions();
    }
  }

  Future<void> _comparePricesWithOtherReps() async {
    if (_response == null) return;
    final db = DatabaseHelper.instance;

    final daysStr = await db.getSetting('comparison_days') ?? '30';
    final comparisonDays = int.tryParse(daysStr) ?? 30;

    final allOrders = await db.getAllRepOrders(withinDays: comparisonDays);
    final Map<String, List<Map<String, dynamic>>> priceMap = {};

    for (var order in allOrders) {
      final repName = order['rep_name'] as String;
      final orderDate = order['created_at'] as String? ?? '';
      try {
        final items = jsonDecode(order['items'] as String) as List;
        for (var item in items) {
          final name = (item['name'] as String).trim().toLowerCase();
          final finalPrice = (item['finalPrice'] as num?)?.toDouble() ?? 
                             (item['price'] as num?)?.toDouble() ?? 0;
          final discount = (item['discount'] as num?)?.toDouble() ?? 0;
          final price = (item['price'] as num?)?.toDouble() ?? 0;

          if (finalPrice <= 0) continue;

          priceMap.putIfAbsent(name, () => []);
          priceMap[name]!.removeWhere((e) => e['repName'] == repName);
          priceMap[name]!.add({
            'repName': repName,
            'finalPrice': finalPrice,
            'discount': discount,
            'price': price,
            'date': orderDate,
          });
        }
      } catch (_) {}
    }

    final List<Map<String, dynamic>> alerts = [];

    for (var item in _response!.availableItems) {
      final key = item.drugName.trim().toLowerCase();
      final currentNet = item.finalPrice;

      if (!priceMap.containsKey(key)) continue;

      final offers = priceMap[key]!;
      if (offers.length < 2) continue;

      offers.sort((a, b) => (a['finalPrice'] as double).compareTo(b['finalPrice'] as double));
      final best = offers.first;
      final bestPrice = best['finalPrice'] as double;
      final bestRep = best['repName'] as String;

      if (bestPrice < currentNet && bestRep != _response!.repName) {
        final saving = currentNet - bestPrice;
        alerts.add({
          'drugName': item.drugName,
          'currentRep': _response!.repName,
          'currentPrice': currentNet,
          'currentDiscount': item.discount,
          'bestRep': bestRep,
          'bestPrice': bestPrice,
          'bestDiscount': best['discount'] as double,
          'saving': saving,
          'allOffers': offers,
        });
      }
    }

    if (alerts.isEmpty || !mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🔔', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('ركّز! فيه عروض أفضل 💰',
                      style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                InkWell(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _changeComparisonPeriod();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.settings, color: AppColors.textMuted, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '📅 مقارنة آخر $comparisonDays يوم',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: alerts.length,
            itemBuilder: (ctx, i) {
              final a = alerts[i];
              final allOffers = a['allOffers'] as List<Map<String, dynamic>>;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🔸 ${a['drugName']}',
                        style: const TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 8),
                    ...allOffers.map((offer) {
                      final isBest = offer == allOffers.first;
                      final isCurrent = offer['repName'] == _response!.repName;
                      String dateText = '';
                      try {
                        final d = DateTime.tryParse(offer['date']?.toString() ?? '');
                        if (d != null) {
                          final diff = DateTime.now().difference(d).inDays;
                          dateText = diff == 0 ? 'اليوم' : 'من $diff يوم';
                        }
                      } catch (e) {
                        debugPrint('Error: $e');
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isBest
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : isCurrent
                                  ? AppColors.danger.withValues(alpha: 0.1)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isBest ? Border.all(color: AppColors.primary.withValues(alpha: 0.4)) : null,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(isBest ? '👑' : isCurrent ? '📍' : '  ', style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(offer['repName'] as String,
                                      style: TextStyle(
                                        color: isBest ? AppColors.primary : AppColors.textLight,
                                        fontWeight: isBest ? FontWeight.w800 : FontWeight.w500,
                                        fontSize: 12,
                                      )),
                                ),
                                Text('خصم ${(offer['discount'] as double).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: isBest ? AppColors.primary : AppColors.textMuted,
                                      fontSize: 11,
                                    )),
                                const SizedBox(width: 10),
                                Text('${(offer['finalPrice'] as double).toStringAsFixed(1)} $_currency',
                                    style: TextStyle(
                                      color: isBest ? AppColors.primary : AppColors.textLight,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                            if (dateText.isNotEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 24, top: 2),
                                  child: Text(dateText,
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '💡 توفير ${(a['saving'] as double).toStringAsFixed(1)} $_currency/علبة مع "${a['bestRep']}"',
                        style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _shareComparisonPDF(alerts, comparisonDays);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('PDF', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _shareComparisonText(alerts, comparisonDays);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
            ),
            icon: const Icon(Icons.share, size: 16),
            label: const Text('نص', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('فهمت ✅', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareComparisonPDF(List<Map<String, dynamic>> alerts, int comparisonDays) async {
    final pdf = pw.Document();
    final pharmacyName = await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدلي PRO';
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
      textDirection: pw.TextDirection.rtl,
      header: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('📊 تقرير مقارنة الأسعار',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(pharmacyName,
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('فترة المقارنة: آخر $comparisonDays يوم',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
                  pw.Text('التاريخ: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 8),
        ],
      ),
      build: (pw.Context context) {
        final widgets = <pw.Widget>[];

        for (int i = 0; i < alerts.length; i++) {
          final a = alerts[i];
          final allOffers = a['allOffers'] as List<Map<String, dynamic>>;

          widgets.add(pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 16),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('${i + 1}. ${a['drugName']}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.5),
                    1: const pw.FlexColumnWidth(2.5),
                    2: const pw.FlexColumnWidth(1.2),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1.2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: ['#', 'المندوب', 'الخصم %', 'السعر الصافي', 'التاريخ']
                          .map((h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(h,
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                              ))
                          .toList(),
                    ),
                    ...allOffers.asMap().entries.map((e) {
                      final idx = e.key;
                      final offer = e.value;
                      String dateText = '';
                      final d = DateTime.tryParse(offer['date']?.toString() ?? '');
                      dateText = d != null ? '${d.day}/${d.month}/${d.year}' : '-';
                      final isBest = idx == 0;
                      return pw.TableRow(
                        decoration: isBest ? const pw.BoxDecoration(color: PdfColors.green50) : null,
                        children: [
                          isBest ? '👑' : '${idx + 1}',
                          offer['repName'] as String,
                          '${(offer['discount'] as double).toStringAsFixed(0)}%',
                          '${(offer['finalPrice'] as double).toStringAsFixed(2)} $_currency',
                          dateText,
                        ].map((t) => pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(t, style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: t.startsWith('👑') ? pw.FontWeight.bold : pw.FontWeight.normal,
                              )),
                            )).toList(),
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.green50,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'التوفير: ${(a['saving'] as double).toStringAsFixed(2)} $_currency/علبة عند الشراء من "${a['bestRep']}" بدلاً من "${a['currentRep']}"',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
                  ),
                ),
              ],
            ),
          ));
        }

        widgets.add(pw.SizedBox(height: 12));
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.amber50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: PdfColors.amber200),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('📋 ملخص التقرير',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('عدد الأصناف التي وُجد لها عروض أفضل: ${alerts.length} صنف',
                  style: const pw.TextStyle(fontSize: 11)),
              pw.Text(
                'إجمالي التوفير الممكن: ${alerts.fold(0.0, (s, a) => s + (a['saving'] as double)).toStringAsFixed(2)} $_currency/علبة',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ));

        widgets.add(pw.SizedBox(height: 20));
        widgets.add(pw.Center(
          child: pw.Text('تم إنشاء هذا التقرير بواسطة تطبيق صيدلي PRO',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        ));

        return widgets;
      },
    ));

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'price_comparison_report.pdf');
  }

  void _shareComparisonText(List<Map<String, dynamic>> alerts, int comparisonDays) {
    String msg = '📊 تقرير مقارنة أسعار المندوبين\n';
    msg += '📅 فترة المقارنة: آخر $comparisonDays يوم\n';
    msg += '━━━━━━━━━━━━━━━━━━━━\n\n';

    for (int i = 0; i < alerts.length; i++) {
      final a = alerts[i];
      final allOffers = a['allOffers'] as List<Map<String, dynamic>>;

      msg += '🔸 ${i + 1}. ${a['drugName']}\n';
      for (var offer in allOffers) {
        final isBest = offer == allOffers.first;
        final icon = isBest ? '👑' : '  ';
        String dateText = '';
        final d = DateTime.tryParse(offer['date']?.toString() ?? '');
        if (d != null) {
          final diff = DateTime.now().difference(d).inDays;
          dateText = diff == 0 ? '(اليوم)' : '(من $diff يوم)';
        }
        msg += '$icon ${offer['repName']} - خصم ${(offer['discount'] as double).toStringAsFixed(0)}% - ${(offer['finalPrice'] as double).toStringAsFixed(2)} $_currency $dateText\n';
      }
      msg += '💡 توفير: ${(a['saving'] as double).toStringAsFixed(2)} $_currency/علبة\n\n';
    }

    final totalSaving = alerts.fold(0.0, (s, a) => s + (a['saving'] as double));
    msg += '━━━━━━━━━━━━━━━━━━━━\n';
    msg += '📋 إجمالي التوفير الممكن: ${totalSaving.toStringAsFixed(2)} $_currency/علبة\n';
    msg += '\nتم الإرسال عبر صيدلي PRO';

    Share.share(msg);
  }

  Future<void> _changeComparisonPeriod() async {
    final db = DatabaseHelper.instance;
    final currentStr = await db.getSetting('comparison_days') ?? '30';
    final current = int.tryParse(currentStr) ?? 30;

    final options = [7, 14, 30, 60, 90, 180, 365];

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚙️ فترة المقارنة',
            style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختر الفترة الزمنية لمقارنة الأسعار بين المندوبين:',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            ...options.map((days) {
              final isSelected = days == current;
              String label;
              if (days == 7) {
                label = 'أسبوع';
              } else if (days == 14) {
                label = 'أسبوعين';
              } else if (days == 30) {
                label = 'شهر';
              } else if (days == 60) {
                label = 'شهرين';
              } else if (days == 90) {
                label = '3 شهور';
              } else if (days == 180) {
                label = '6 شهور';
              } else {
                label = 'سنة';
              }

              return InkWell(
                onTap: () async {
                  await db.setSetting('comparison_days', days.toString());
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    showSnack(context, 'تم تعيين فترة المقارنة: $label ✅');
                  }
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.dark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.darkBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? AppColors.primary : AppColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(label,
                          style: TextStyle(
                            color: isSelected ? AppColors.primary : AppColors.textLight,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          )),
                      const Spacer(),
                      Text('$days يوم',
                          style: TextStyle(
                            color: isSelected ? AppColors.primary : AppColors.textMuted,
                            fontSize: 12,
                          )),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPDF() async {
    if (_response == null) return;

    final pdf = pw.Document();
    final pharmacyName =
        await DatabaseHelper.instance.getSetting('pharmacy_name') ?? 'صيدليتي';

    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
      textDirection: pw.TextDirection.rtl,
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('صيدلي PRO',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(pharmacyName,
                      style: const pw.TextStyle(
                          fontSize: 14, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('رد المندوب: ${_response!.repName}',
                      style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('التاريخ: ${_formatDate(_response!.respondedAt)}',
                      style: const pw.TextStyle(
                          fontSize: 11, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 10),
          if (_response!.availableItems.isNotEmpty) ...[
            pw.Text('✅ الأصناف المتاحة (${_response!.availableItems.length})',
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1.2),
                5: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children:
                      ['الصنف', 'الكمية', 'السعر', 'الخصم', 'الصافي', 'الإجمالي']
                          .map((h) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(h,
                                    style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 9)),
                              ))
                          .toList(),
                ),
                ..._response!.availableItems.map((item) => pw.TableRow(
                      children: [
                        '${item.drugName}\n(${item.company})',
                        '${item.quantity}',
                        item.price.toStringAsFixed(2),
                        '${item.discount.toStringAsFixed(0)}%',
                        item.finalPrice.toStringAsFixed(2),
                        '${item.totalPrice.toStringAsFixed(2)} $_currency',
                      ]
                          .map((t) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(t,
                                    style: const pw.TextStyle(fontSize: 9)),
                              ))
                          .toList(),
                    )),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                'إجمالي: ${_response!.availableItems.fold(0.0, (s, i) => s + i.totalPrice).toStringAsFixed(2)} $_currency',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                    color: PdfColors.green700),
              ),
            ),
            pw.SizedBox(height: 16),
          ],
          if (_response!.unavailableItems.isNotEmpty) ...[
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(
                '❌ الأصناف غير المتاحة (${_response!.unavailableItems.length})',
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700)),
            pw.SizedBox(height: 8),
            ..._response!.unavailableItems.map((item) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                          '• ${item.drugName} (${item.company}) - ${item.quantity} علبة',
                          style: const pw.TextStyle(fontSize: 11)),
                      if (item.repAlternative != null && item.repAlternative!.isNotEmpty)
                        pw.Text(
                            '  💡 بديل المندوب: ${item.repAlternative}',
                            style: const pw.TextStyle(
                                fontSize: 10, color: PdfColors.blue700)),
                    ],
                  ),
                )),
          ],
          pw.Spacer(),
          pw.Divider(),
          pw.Center(
            child: pw.Text('تم إنشاء هذا التقرير بواسطة تطبيق صيدلي PRO',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          ),
        ],
      ),
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  void _shareAsText() {
    if (_response == null) return;
    final r = _response!;
    String msg = '📦 تقرير رد المندوب: ${r.repName}\n';
    msg += '📅 التاريخ: ${_formatDate(r.respondedAt)}\n';
    msg += '--------------------------\n';

    if (r.availableItems.isNotEmpty) {
      msg += '✅ الأصناف المتاحة:\n';
      for (var item in r.availableItems) {
        msg += '- ${item.drugName} (${item.quantity} علبة)\n';
        msg += '  سعر: ${item.price.toStringAsFixed(2)} | خصم: ${item.discount.toStringAsFixed(0)}% | صافي: ${item.finalPrice.toStringAsFixed(2)} | إجمالي: ${item.totalPrice.toStringAsFixed(2)} $_currency\n';
      }
      msg +=
          '\n💰 الإجمالي: ${r.availableItems.fold(0.0, (s, i) => s + i.totalPrice).toStringAsFixed(2)} $_currency\n';
    }

    if (r.unavailableItems.isNotEmpty) {
      msg += '\n❌ غير متاحة (تحتاج مندوب آخر):\n';
      for (var item in r.unavailableItems) {
        msg += '- ${item.drugName}';
        if (item.repAlternative != null && item.repAlternative!.isNotEmpty) {
          msg += ' (بديل مقترح من المندوب: ${item.repAlternative})';
        }
        msg += '\n';
      }
    }

    msg += '\nتم الإرسال عبر صيدلي PRO';
    Share.share(msg);
  }

  Future<void> _handleAlternativeTap(ResponseItem item) async {
    if (item.repAlternative == null || item.repAlternative!.isEmpty) return;

    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    int chosenQty = item.quantity;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.darkBorder,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '💡 معالجة البديل المقترح',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'الصنف الأصلي الناقص: ${item.drugName}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'البديل المقترح من المندوب: ${item.repAlternative}',
                  style: const TextStyle(
                    color: Color(0xFF93C5FD),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'حدد الكمية المطلوبة:',
                  style: TextStyle(color: AppColors.textLight, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary, size: 28),
                      onPressed: () {
                        if (chosenQty > 1) {
                          setBS(() {
                            chosenQty--;
                            qtyCtrl.text = chosenQty.toString();
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: 'الكمية',
                          filled: true,
                          fillColor: AppColors.dark,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.darkBorder),
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            chosenQty = parsed;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 28),
                      onPressed: () {
                        setBS(() {
                          chosenQty++;
                          qtyCtrl.text = chosenQty.toString();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'اختر الإجراء المطلوب:',
                  style: TextStyle(color: AppColors.textLight, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _processAlternativeAction(item, chosenQty, replaceOld: true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
                    label: Text(
                      'استبدال القديم بـ "${item.repAlternative}"',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _processAlternativeAction(item, chosenQty, replaceOld: false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF60A5FA),
                      side: const BorderSide(color: Color(0xFF60A5FA)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: Text(
                      'إضافة "${item.repAlternative}" كصنف جديد',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _processAlternativeAction(ResponseItem item, int quantity, {required bool replaceOld}) async {
    final db = DatabaseHelper.instance;
    final nowStr = DateTime.now().toIso8601String();

    try {
      if (replaceOld) {
        final shortages = await db.getShortages(status: 'pending');
        final originalShortage = shortages.firstWhere(
          (s) => s['name'].toString().toLowerCase() == item.drugName.toLowerCase(),
          orElse: () => <String, dynamic>{},
        );

        if (originalShortage.isNotEmpty) {
          final originalId = originalShortage['id'] as int;
          await db.updateShortage(originalId, {
            'name': item.repAlternative!,
            'company': item.company,
            'quantity': quantity,
            'is_synced': 0,
            'updated_at': nowStr,
          });
        } else {
          await db.insertShortage({
            'name': item.repAlternative!,
            'company': item.company,
            'quantity': quantity,
            'status': 'pending',
            'is_urgent': 0,
            'created_at': nowStr,
            'updated_at': nowStr,
            'is_synced': 0,
            'created_by': 'المالك',
          });
        }
      } else {
        await db.insertShortage({
          'name': item.repAlternative!,
          'company': item.company,
          'quantity': quantity,
          'status': 'pending',
          'is_urgent': 0,
          'created_at': nowStr,
          'updated_at': nowStr,
          'is_synced': 0,
          'created_by': 'المالك',
        });
      }

      await SyncService.instance.syncAll();

      if (mounted) {
        showSnack(context, 'تم حفظ التعديل والمزامنة بنجاح! ✅');
      }

      if (mounted) {
        await _promptToSendUpdatedShortages();
      }
    } catch (e) {
      debugPrint('Error processing alternative action: $e');
      if (mounted) {
        showSnack(context, '❌ حدث خطأ أثناء المعالجة: $e', isError: true);
      }
    }
  }

  Future<void> _promptToSendUpdatedShortages() async {
    if (_response == null) return;
    final r = _response!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('📲', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('تحديث الطلب مع المندوب',
                style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          'تم تحديث النواقص بنجاح. هل تريد الانتقال إلى شاشة الإرسال لإرسال الرابط المحدث للمندوب (${r.repName}) الآن؟',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ليس الآن', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('نعم، أرسل الرابط المحدث', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final db = DatabaseHelper.instance;
      final reps = await db.getReps();
      Representative? targetRep;

      for (final rMap in reps) {
        final rep = Representative.fromMap(rMap);
        if (rep.name.trim() == r.repName.trim() ||
            (rep.phone != null &&
                rep.phone!.isNotEmpty &&
                r.repPhone.isNotEmpty &&
                rep.phone!.replaceAll(' ', '') == r.repPhone.replaceAll(' ', ''))) {
          targetRep = rep;
          break;
        }
      }

      if (targetRep == null) {
        targetRep = Representative(
          name: r.repName,
          phone: r.repPhone,
          createdAt: DateTime.now(),
        );
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SendToRepScreen(rep: targetRep!),
          ),
        );
      }
    }
  }

  // ==========================================
  // ─── بناء واجهة المستخدم (UI Build) ───────
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        backgroundColor: AppColors.darkCard,
        elevation: 0,
        title: _buildAppBarTitle(),
        actions: _buildAppBarActions(),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
          tabs: const [
            Tab(
              icon: Icon(Icons.people_alt_outlined),
              text: 'قائمة المندوبين',
            ),
            Tab(
              icon: Icon(Icons.mark_chat_unread_outlined),
              text: 'ردود المندوبين',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRepsListTab(),
          _buildResponseTab(),
        ],
      ),
      floatingActionButton: _buildFab(),
      bottomNavigationBar: (_tabController.index == 1 && _response != null)
          ? _buildResponseBottomBar()
          : null,
    );
  }

  Widget _buildAppBarTitle() {
    if (_tabController.index == 1 && _showResponseSearch) {
      return TextField(
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
            hintText: 'ابحث عن صنف في الرد...',
            hintStyle: TextStyle(color: Colors.white60),
            border: InputBorder.none),
        onChanged: (val) => setState(() => _responseSearchQuery = val),
        autofocus: true,
      );
    }

    if (_tabController.index == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('المندوبين',
              style: TextStyle(
                  color: AppColors.textColor, fontWeight: FontWeight.w700)),
          Text('عدد المندوبين ${_reps.length}',
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12)),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('استقبال ردود المندوبين',
              style: TextStyle(
                  color: AppColors.textColor, fontWeight: FontWeight.w700)),
          Text(
            _response == null ? 'أدخل كود الرد أو اختر من الجلسات' : 'رد: ${_response!.repName}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      );
    }
  }

  List<Widget> _buildAppBarActions() {
    if (_tabController.index == 0) {
      return [
        IconButton(
          icon: const Icon(Icons.contacts_rounded, color: AppColors.textColor),
          tooltip: 'استيراد من جهات الاتصال',
          onPressed: () => _showAddSheet(),
        ),
      ];
    } else {
      if (_response != null) {
        return [
          IconButton(
            icon: Icon(_showResponseSearch ? Icons.close : Icons.search, color: AppColors.primary),
            onPressed: () {
              setState(() {
                _showResponseSearch = !_showResponseSearch;
                if (!_showResponseSearch) _responseSearchQuery = '';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.accent),
            tooltip: 'مشاركة نص',
            onPressed: _shareAsText,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.danger),
            tooltip: 'إغلاق الرد',
            onPressed: () {
              setState(() {
                _response = null;
                _codeCtrl.clear();
              });
              _fetchSentSessions();
            },
          ),
        ];
      }
      return [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          tooltip: 'تحديث الجلسات',
          onPressed: _fetchSentSessions,
        ),
      ];
    }
  }

  Widget? _buildFab() {
    if (_tabController.index == 0) {
      return FloatingActionButton.extended(
        heroTag: 'reps_list_fab',
        onPressed: () => _showAddSheet(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('مندوب جديد',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo')),
      );
    }
    return null;
  }

  // ─── واجهة تاب "القائمة" ───
  Widget _buildRepsListTab() {
    if (_loadingReps) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _repsSearchController,
            onChanged: (v) => setState(() => _repsSearch = v),
            style: const TextStyle(color: AppColors.textColor),
            decoration: InputDecoration(
              hintText: 'ابحث عن مندوب...',
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
              suffixIcon: _repsSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 20),
                      onPressed: () {
                        _repsSearchController.clear();
                        setState(() => _repsSearch = '');
                      },
                    )
                  : const Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
            ),
          ),
        ),
        Expanded(
          child: _reps.isEmpty
              ? const EmptyState(
                  emoji: '👥',
                  title: 'لا يوجد مندوبون',
                  subtitle: 'أضف مندوبين لإرسال النواقص')
              : _filteredReps.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              color: AppColors.textMuted, size: 48),
                          SizedBox(height: 12),
                          Text('لا توجد نتائج',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 15)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadReps,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: _filteredReps.length,
                        itemBuilder: (ctx, i) =>
                            _buildRepCard(_filteredReps[i], i),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildRepCard(Representative rep, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _showAddSheet(existing: rep),
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              icon: Icons.edit_rounded,
              label: 'تعديل',
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(14)),
            ),
            SlidableAction(
              onPressed: (_) async {
                final userProvider = context.read<CurrentUserProvider>();
                if (!userProvider.canDelete) {
                  showSnack(context, '⛔ ليس لديك صلاحية الحذف', isError: true);
                  return;
                }
                final confirm = await showDeleteDialog(context, rep.name);
                if (confirm == true) {
                  await context.read<RepsProvider>().delete(rep.id!);
                  await DatabaseHelper.instance.logActivity(
                    assistantId: userProvider.currentAssistantId,
                    assistantName: userProvider.currentName,
                    action: 'حذف مندوب',
                    details: 'تم حذف المندوب: ${rep.name}',
                    screen: 'reps',
                  );
                  if (mounted) showSnack(context, 'تم الحذف');
                }
              },
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              icon: Icons.delete_rounded,
              label: 'حذف',
            ),
          ],
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RepDetailsScreen(rep: rep)),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border(
                top: BorderSide(
                    color: index == 0 ? AppColors.warning : AppColors.darkBorder,
                    width: index == 0 ? 2 : 1),
                bottom: const BorderSide(color: AppColors.darkBorder),
                left: const BorderSide(color: AppColors.darkBorder),
                right: const BorderSide(color: AppColors.darkBorder),
              ),
              boxShadow: index < 3 ? [
                BoxShadow(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ] : null,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark]),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Center(
                          child: Text(rep.name.isNotEmpty ? rep.name[0] : '؟',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(rep.name,
                                    style: const TextStyle(
                                        color: AppColors.textColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle,
                                        color: AppColors.primary, size: 7),
                                    SizedBox(width: 4),
                                    Text('نشط',
                                        style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.textMuted, size: 18),
                            ],
                          ),
                          StarRating(count: rep.rating),
                          if (rep.phone != null && rep.phone!.isNotEmpty)
                            Row(
                              children: [
                                const Icon(Icons.phone_rounded,
                                    color: AppColors.textMuted, size: 12),
                                const SizedBox(width: 4),
                                Text(rep.phone!,
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _statBox('التغطية', '${rep.totalCovered} صنف', false),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _statBox('الطلبات', '${rep.totalCovered * 3} طلب', false),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _sendShortages(rep),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.qr_code, size: 18),
                    label: const Text('إرسال النواقص بـ QR',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statBox(String label, String value, bool highlight) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.darkBorder)),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: highlight ? AppColors.primary : AppColors.textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }

  // ─── واجهة تاب "الردود" ───
  Widget _buildResponseTab() {
    if (_response == null) {
      return _buildCodeEntryView();
    }
    return _buildResponseDetailsView();
  }

  Widget _buildCodeEntryView() {
    return RefreshIndicator(
      onRefresh: _fetchSentSessions,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: Text('📲', style: TextStyle(fontSize: 48))),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'أدخل كود الرد المكون من 8 أحرف',
              style: TextStyle(
                color: AppColors.textColor,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 6),
            maxLength: 8,
            decoration: InputDecoration(
              hintText: '--------',
              hintStyle: const TextStyle(
                  color: AppColors.darkBorder, letterSpacing: 6, fontSize: 22),
              errorText: _responseError,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onSubmitted: (_) => _fetchResponse(),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            text: 'جلب الرد',
            isLoading: _loadingResponse,
            icon: Icons.search_rounded,
            onTap: _fetchResponse,
          ),
          const SizedBox(height: 20),
          const Divider(color: AppColors.darkBorder),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الطلبات المرسلة للمندوبين 📨',
                style: TextStyle(
                  color: AppColors.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_loadingSessions)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
                  onPressed: _fetchSentSessions,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_loadingSessions && _sentSessions.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: const Center(
                child: Text(
                  'لا توجد طلبات مرسلة نشطة حالياً.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            )
          else
            ..._sentSessions.map((session) {
              final isResponded = session['responded_at'] != null || session['status'] == 'responded';
              final repName = session['rep_name'] ?? 'مندوب';
              final code = session['session_code'] ?? '';
              
              return Card(
                color: AppColors.darkCard,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isResponded 
                        ? AppColors.primary.withValues(alpha: 0.4) 
                        : AppColors.darkBorder
                  ),
                ),
                child: InkWell(
                  onTap: () {
                    _codeCtrl.text = code;
                    _fetchResponse();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isResponded 
                                ? AppColors.primary.withValues(alpha: 0.15) 
                                : AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(child: Text('👤', style: TextStyle(fontSize: 16))),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                repName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13
                                ),
                              ),
                              Text(
                                'كود الطلب: $code',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isResponded 
                                ? AppColors.primary.withValues(alpha: 0.1) 
                                : AppColors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isResponded ? Icons.check_circle : Icons.hourglass_empty_rounded,
                                size: 12,
                                color: isResponded ? AppColors.primary : AppColors.warning,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isResponded ? 'تم الرد! استلم' : 'قيد الانتظار',
                                style: TextStyle(
                                  color: isResponded ? AppColors.primary : AppColors.warning,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildResponseDetailsView() {
    final r = _response!;
    final filteredAvailable = r.availableItems
        .where((i) =>
            i.drugName.toLowerCase().contains(_responseSearchQuery.toLowerCase()))
        .toList();
    final filteredUnavailable = r.unavailableItems
        .where((i) =>
            i.drugName.toLowerCase().contains(_responseSearchQuery.toLowerCase()))
        .toList();
    final total = filteredAvailable.fold(0.0, (s, i) => s + i.totalPrice);

    return ListView(
      padding: const EdgeInsets.all(16).copyWith(bottom: 120),
      children: [
        if (!_showResponseSearch) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF0D2E1C), Color(0xFF0A3525)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primaryDark),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark]),
                      borderRadius: BorderRadius.circular(99)),
                  child: Center(
                      child: Text(r.repName.isNotEmpty ? r.repName[0] : '؟',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.repName,
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      Text('رد في ${_formatDate(r.respondedAt)}',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                      '${r.availableItems.length + r.unavailableItems.length} صنف',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (filteredAvailable.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('✅ متاح (${filteredAvailable.length})',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
              Text('${total.toStringAsFixed(2)} $_currency',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ...filteredAvailable.map((item) => _buildAvailableCard(item)),
          const SizedBox(height: 12),
        ],
        if (filteredUnavailable.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('⏳', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text('لديها فرصة (${filteredUnavailable.length})',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                    'هذه الأصناف غير متاحة من هذا المندوب - يمكن إرسالها لمندوب آخر',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...filteredUnavailable.map((item) => _buildUnavailableCard(item)),
        ],
        if (filteredAvailable.isEmpty && filteredUnavailable.isEmpty)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('لا توجد نتائج بحث مطابقة',
                      style: TextStyle(color: AppColors.textMuted)))),
      ],
    );
  }

  Widget _buildAvailableCard(ResponseItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(item.drugName,
                              style: const TextStyle(
                                  color: AppColors.textColor,
                                  fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 18),
                          onPressed: () => _searchGoogleImages(item.drugName),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          constraints: const BoxConstraints(),
                          tooltip: 'بحث في جوجل (صور)',
                        ),
                      ],
                    ),
                    Text('${item.company} · ${item.quantity} علبة',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 4),
                    if (item.discount > 0) ...[
                      Text('سعر القطعة الأساسي: ${item.price.toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, decoration: TextDecoration.lineThrough)),
                      Text('الصافي للقطعة: ${item.finalPrice.toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
                      Text('الإجمالي قبل الخصم: ${(item.price * item.quantity).toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, decoration: TextDecoration.lineThrough)),
                    ] else ...[
                      Text('سعر القطعة: ${item.price.toStringAsFixed(2)} $_currency', style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
                    ]
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('الإجمالي', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  Text('${item.totalPrice.toStringAsFixed(2)} $_currency',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  if (item.discount > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('خصم ${item.discount.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.notes!,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildUnavailableCard(ResponseItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(item.drugName,
                              style: const TextStyle(
                                  color: AppColors.textLight,
                                  fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 18),
                          onPressed: () => _searchGoogleImages(item.drugName),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          constraints: const BoxConstraints(),
                          tooltip: 'بحث في جوجل (صور)',
                        ),
                      ],
                    ),
                    Text('${item.company} · ${item.quantity} علبة',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('⏳ لديها فرصة',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (item.repAlternative != null && item.repAlternative!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 28),
              child: InkWell(
                onTap: () => _handleAlternativeTap(item),
                borderRadius: BorderRadius.circular(8),
                splashColor: const Color(0xFF60A5FA).withValues(alpha: 0.2),
                highlightColor: const Color(0xFF60A5FA).withValues(alpha: 0.1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF60A5FA).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF60A5FA).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_rounded,
                          color: Color(0xFF60A5FA), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                           '🔸 بديل مقترح من المندوب: ${item.repAlternative}',
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper.instance.getAlternativesFor(item.drugName),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              final alts = snapshot.data!.map((row) {
                final med = row['medication_name']?.toString() ?? '';
                final alt = row['alternative_name']?.toString() ?? '';
                if (med.toLowerCase() == item.drugName.toLowerCase()) {
                  return alt;
                }
                return med;
              }).where((name) => name.isNotEmpty).toSet().toList();

              if (alts.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(top: 8, right: 28),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '💡 بدائل محلية مقترحة: ${alts.join(" ، ")}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResponseBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.darkCard,
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportPDF,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('PDF',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareAsText,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('نص',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => _processResponse(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('تم (مع إبقاء النواقص)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () => _processResponse(true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('إنهاء اليوم',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
