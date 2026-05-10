import json

with open('lib/screens/rep_response_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_finish_day = """    for (final item in _response!.availableItems) {
      final key = item.drugName.trim().toLowerCase();
      if (shortageMap.containsKey(key)) {
        for (final id in shortageMap[key]!) {
          await db.updateShortage(id, {'status': 'covered'});
        }
      }
    }

    for (final item in _response!.unavailableItems) {
      final key = item.drugName.trim().toLowerCase();
      if (shortageMap.containsKey(key)) {
        for (final id in shortageMap[key]!) {
          await db.updateShortage(id, {'status': 'stubborn'});
        }
      }
    }"""

new_finish_day = """    // ▌ تحديث أسعار الأدوية في القاموس إذا زاد السعر
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
      
      // تحديث حالة النواقص
      if (shortageMap.containsKey(key)) {
        for (final id in shortageMap[key]!) {
          await db.updateShortage(id, {'status': 'covered'});
        }
      }

      // تحديث السعر في القاموس
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
      if (shortageMap.containsKey(key)) {
        for (final id in shortageMap[key]!) {
          await db.updateShortage(id, {'status': 'stubborn'});
        }
      }
    }"""

content = content.replace(old_finish_day, new_finish_day)

with open('lib/screens/rep_response_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
