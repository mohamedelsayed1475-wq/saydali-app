import re

with open('lib/screens/invoice_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Replace _loadSuggestions
old_load = """  Future<void> _loadSuggestions() async {
    // ▌ تحميل قائمة منتجات من قاعدة البيانات
    final products = await DatabaseHelper.instance.getSetting('products_list');
    if (products != null) {
      try {
        final List<dynamic> decoded = jsonDecode(products);
        setState(() {
          _suggestions = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      } catch (_) {}
    }
  }"""
new_load = """  Future<void> _loadSuggestions() async {
    final dictStr = await DatabaseHelper.instance.getSetting('drug_dictionary_v2');
    if (dictStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dictStr);
        if (mounted) setState(() => _suggestions = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      } catch (_) {}
    } else {
      final oldDictStr = await DatabaseHelper.instance.getSetting('drug_dictionary');
      if (oldDictStr != null) {
        try {
          final List<dynamic> decoded = jsonDecode(oldDictStr);
          if (mounted) setState(() => _suggestions = decoded.map((s) => {'enName': s.toString()}).toList());
        } catch (_) {}
      }
    }
  }

  bool _fuzzyMatch(String query, String text) {
    String q = query.toLowerCase().replaceAll(RegExp(r'\\s+'), '');
    if (q.isEmpty) return true;
    String t = text.toLowerCase().replaceAll(RegExp(r'\\s+'), '');
    if (t.contains(q)) return true;
    int i = 0;
    for (int j = 0; j < t.length && i < q.length; j++) {
      if (t[j] == q[i]) i++;
    }
    return i == q.length;
  }"""
content = content.replace(old_load, new_load)

# 2. Replace subtotals and displays
content = content.replace("double subtotal = items.fold(0, (s, i) => s + (i['price'] * i['qty']));", 
                          "double subtotal = items.fold(0, (s, i) => s + (i['line_total'] ?? (i['price'] * i['qty'])));")

content = content.replace("'${item['qty']} × ${item['price'].toStringAsFixed(2)} $_currency',", 
                          "'${item['qty_text'] ?? item['qty']} × ${item['price'].toStringAsFixed(2)} $_currency',")

content = content.replace("'${(item['qty'] * item['price']).toStringAsFixed(2)}',", 
                          "'${(item['line_total'] ?? (item['qty'] * item['price'])).toStringAsFixed(2)}',")

content = content.replace("Text('${item['name']} × ${item['qty']}',", 
                          "Text('${item['name']} × ${item['qty_text'] ?? item['qty']}',")

content = content.replace("Text('${(item['price'] * item['qty']).toStringAsFixed(2)}',", 
                          "Text('${(item['line_total'] ?? (item['price'] * item['qty'])).toStringAsFixed(2)}',")


# 3. Replace _addItem function
old_add_item_start = """  void _addItem(
      BuildContext ctx, List<Map<String, dynamic>> items, StateSetter setBS) {"""
old_add_item_end = """              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }"""

add_item_pattern = re.compile(re.escape(old_add_item_start) + r'.*?' + re.escape(old_add_item_end), re.DOTALL)

new_add_item = r"""  void _addItem(BuildContext ctx, List<Map<String, dynamic>> items, StateSetter setBS) {
    _showAddItemDialog(ctx, (newItem) {
      setBS(() => items.add(newItem));
    });
  }

  void _addItemToExisting(BuildContext ctx, List<Map<String, dynamic>> items, StateSetter setBS) {
    _showAddItemDialog(ctx, (newItem) {
      setBS(() => items.add(newItem));
    });
  }

  void _showAddItemDialog(BuildContext ctx, Function(Map<String, dynamic>) onAdd) {
    final itemNameCtrl = TextEditingController();
    TextEditingController? autoCtrl;
    final priceCtrl = TextEditingController();
    final boxesCtrl = TextEditingController(text: '1');
    final stripsCtrl = TextEditingController(text: '0');
    final stripsPerBoxCtrl = TextEditingController(text: '3');

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDBS) => AlertDialog(
          backgroundColor: AppColors.darkCard,
          title: Row(
            children: [
              const Text('إضافة صنف', style: TextStyle(color: AppColors.primary, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                tooltip: 'مسح QR/باركود',
                onPressed: () async {
                  final code = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(builder: (_) => const ScannerScreen()),
                  );
                  if (code != null) {
                    itemNameCtrl.text = code;
                    if (autoCtrl != null) autoCtrl!.text = code;
                    setDBS(() {});
                  }
                },
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Autocomplete for items
                Row(
                  children: [
                    Expanded(
                      child: Autocomplete<Map<String, dynamic>>(
                        optionsBuilder: (v) {
                          if (v.text.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                          final terms = v.text.split(RegExp(r'[\s/]+')).where((t) => t.isNotEmpty);
                          return _suggestions.where((s) {
                            final en = s['enName']?.toString() ?? '';
                            final ar = s['arName']?.toString() ?? '';
                            final act = s['activeIngredient']?.toString() ?? '';
                            final bar = s['barcode']?.toString() ?? '';
                            return terms.every((term) =>
                                _fuzzyMatch(term, en) ||
                                _fuzzyMatch(term, ar) ||
                                _fuzzyMatch(term, act) ||
                                _fuzzyMatch(term, bar));
                          });
                        },
                        displayStringForOption: (option) => option['enName']?.toString() ?? '',
                        onSelected: (s) {
                          itemNameCtrl.text = s['enName']?.toString() ?? '';
                          if (s['price'] != null && s['price'].toString().isNotEmpty && s['price'].toString() != '0') {
                            priceCtrl.text = s['price'].toString();
                          }
                        },
                        fieldViewBuilder: (ctx, ctrl, fn, onSubmit) {
                          autoCtrl = ctrl;
                          return AppTextField(
                            hint: 'اسم الصنف',
                            controller: ctrl,
                            focusNode: fn,
                            onSubmitted: (_) => onSubmit(),
                            onChanged: (val) => itemNameCtrl.text = val,
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              color: AppColors.darkCard,
                              elevation: 4.0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: AppColors.darkBorder),
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250, maxWidth: 280),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final option = options.elementAt(index);
                                    final en = option['enName']?.toString() ?? '';
                                    final ar = option['arName']?.toString() ?? '';
                                    final price = option['price']?.toString() ?? '';
                                    return InkWell(
                                      onTap: () => onSelected(option),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(en, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                            if (ar.isNotEmpty) Text(ar, style: const TextStyle(color: AppColors.primary, fontSize: 11)),
                                            if (price.isNotEmpty && price != '0') Text('$price $_currency', style: const TextStyle(color: AppColors.warning, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppTextField(hint: 'سعر العلبة', controller: priceCtrl, keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(hint: 'العلب', controller: boxesCtrl, keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: AppTextField(hint: 'الشرايط', controller: stripsCtrl, keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('شرايط/علبة:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(width: 8),
                    SizedBox(width: 60, child: AppTextField(hint: '3', controller: stripsPerBoxCtrl, keyboardType: TextInputType.number)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                final name = itemNameCtrl.text.trim();
                final price = double.tryParse(priceCtrl.text) ?? 0;
                final boxes = int.tryParse(boxesCtrl.text) ?? 0;
                final strips = int.tryParse(stripsCtrl.text) ?? 0;
                final stripsPerBox = int.tryParse(stripsPerBoxCtrl.text) ?? 3;

                if (name.isEmpty) {
                  showSnack(dCtx, 'أدخل اسم الصنف', isError: true);
                  return;
                }
                if (price <= 0) {
                  showSnack(dCtx, 'أدخل السعر', isError: true);
                  return;
                }
                if (boxes == 0 && strips == 0) {
                  showSnack(dCtx, 'أدخل الكمية', isError: true);
                  return;
                }

                final safeStripsPerBox = stripsPerBox > 0 ? stripsPerBox : 3;
                final lineTotal = (boxes * price) + (strips * (price / safeStripsPerBox));

                String qtyText = '';
                if (boxes > 0) qtyText += '$boxes علبة';
                if (strips > 0) qtyText += (qtyText.isEmpty ? '' : ' و ') + '$strips شريط';

                onAdd({
                  'name': name,
                  'price': price,
                  'qty': 1,
                  'qty_text': qtyText,
                  'line_total': lineTotal,
                  'boxes': boxes,
                  'strips': strips,
                });
                Navigator.pop(dCtx);
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }"""

content = add_item_pattern.sub(lambda m: new_add_item, content)

# 4. Remove the old _addItemToExisting
old_add_existing = """  // ▌ إضافة صنف للفاتورة المعدلة
  void _addItemToExisting(BuildContext ctx, List<Map<String, dynamic>> items, StateSetter setBS) {
    final itemNameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('إضافة صنف', style: TextStyle(color: AppColors.primary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(hint: 'اسم الصنف', controller: itemNameCtrl),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: AppTextField(hint: 'السعر', controller: priceCtrl, keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(child: AppTextField(hint: 'الكمية', controller: qtyCtrl, keyboardType: TextInputType.number)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final name = itemNameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text) ?? 0;
              final rawQty = int.tryParse(qtyCtrl.text) ?? 1;
              final qty = rawQty.clamp(1, 9999);
              if (name.isEmpty || price <= 0) return;
              setBS(() => items.add({'name': name, 'price': price, 'qty': qty}));
              Navigator.pop(dCtx);
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }"""

content = content.replace(old_add_existing, "")

# 5. Fix PDF generation
old_pdf_row = """                    final lineTotal = item['price'] * item['qty'];
                    return pw.TableRow(
                      children: [
                        '${i + 1}',
                        item['name'],
                        '${item['qty']}',
                        '${item['price'].toStringAsFixed(2)}',
                        '${lineTotal.toStringAsFixed(2)}',
                      ]"""

new_pdf_row = """                    final lineTotal = item['line_total'] ?? (item['price'] * item['qty']);
                    return pw.TableRow(
                      children: [
                        '${i + 1}',
                        item['name'],
                        '${item['qty_text'] ?? item['qty']}',
                        '${item['price'].toStringAsFixed(2)}',
                        '${lineTotal.toStringAsFixed(2)}',
                      ]"""

content = content.replace(old_pdf_row, new_pdf_row)

with open('lib/screens/invoice_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

