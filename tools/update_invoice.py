import re

with open('lib/screens/invoice_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_add_item = """  void _showAddItemDialog(BuildContext ctx, Function(Map<String, dynamic>) onAdd) {
    final itemNameCtrl = TextEditingController();
    TextEditingController? autoCtrl;
    final priceCtrl = TextEditingController();
    final boxesCtrl = TextEditingController(text: '1');
    final stripsCtrl = TextEditingController(text: '0');
    final stripsPerBoxCtrl = TextEditingController(text: '3');"""

new_add_item = """  void _showAddItemDialog(BuildContext ctx, Function(Map<String, dynamic>) onAdd) {
    final itemNameCtrl = TextEditingController();
    TextEditingController? autoCtrl;
    final priceCtrl = TextEditingController(); // Box Price
    final stripPriceCtrl = TextEditingController(); // Strip Price
    final boxesCtrl = TextEditingController(text: '1');
    final stripsCtrl = TextEditingController(text: '0');"""

content = content.replace(old_add_item, new_add_item)

old_ui = """                const SizedBox(height: 10),
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
                ),"""

new_ui = """                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(hint: 'سعر العلبة', controller: priceCtrl, keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: AppTextField(hint: 'عدد العلب', controller: boxesCtrl, keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(hint: 'سعر الشريط', controller: stripPriceCtrl, keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: AppTextField(hint: 'عدد الشرايط', controller: stripsCtrl, keyboardType: TextInputType.number)),
                  ],
                ),"""

content = content.replace(old_ui, new_ui)

old_logic = """                final name = itemNameCtrl.text.trim();
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
                final lineTotal = (boxes * price) + (strips * (price / safeStripsPerBox));"""

new_logic = """                final name = itemNameCtrl.text.trim();
                final boxPrice = double.tryParse(priceCtrl.text) ?? 0;
                final stripPrice = double.tryParse(stripPriceCtrl.text) ?? 0;
                final boxes = int.tryParse(boxesCtrl.text) ?? 0;
                final strips = int.tryParse(stripsCtrl.text) ?? 0;

                if (name.isEmpty) {
                  showSnack(dCtx, 'أدخل اسم الصنف', isError: true);
                  return;
                }
                if (boxPrice <= 0 && stripPrice <= 0) {
                  showSnack(dCtx, 'أدخل السعر', isError: true);
                  return;
                }
                if (boxes == 0 && strips == 0) {
                  showSnack(dCtx, 'أدخل الكمية', isError: true);
                  return;
                }

                final lineTotal = (boxes * boxPrice) + (strips * stripPrice);
                final mainPrice = boxPrice > 0 ? boxPrice : stripPrice;"""

content = content.replace(old_logic, new_logic)

old_add = """                onAdd({
                  'name': name,
                  'price': price,
                  'qty': 1,
                  'qty_text': qtyText,
                  'line_total': lineTotal,
                  'boxes': boxes,
                  'strips': strips,
                });"""

new_add = """                onAdd({
                  'name': name,
                  'price': mainPrice,
                  'qty': 1,
                  'qty_text': qtyText,
                  'line_total': lineTotal,
                  'boxes': boxes,
                  'strips': strips,
                });"""

content = content.replace(old_add, new_add)

with open('lib/screens/invoice_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
