import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<Map<String, dynamic>> _documents = [];
  bool _loading = true;
  final ImagePicker _picker = ImagePicker();

  // ▌ تصنيفات المستندات
  final Map<String, String> _categories = {
    'license': '🪪 تراخيص',
    'ministry': '🏛️ ملفات الوزارة',
    'invoice': '🧾 فواتير',
    'prescription': '💊 روشتات',
    'id': '🆔 هويات/بطاقات',
    'other': '📄 أخرى',
  };

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loading = true);
    final docs = await DatabaseHelper.instance.getSetting('saved_documents');
    if (docs != null) {
      try {
        final List<dynamic> decoded = await _decodeJsonSafe(docs);
        setState(() {
          _documents = decoded.cast<Map<String, dynamic>>();
          _documents.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
        });
      } catch (_) {}
    }
    setState(() => _loading = false);
  }

  Future<List<dynamic>> _decodeJsonSafe(String json) async {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveDocuments() async {
    await DatabaseHelper.instance.setSetting('saved_documents', jsonEncode(_documents));
  }

  Future<void> _pickImage({required bool fromCamera}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      // ▌ نسخ الصورة لمجلد التطبيق
      final appDir = await getApplicationDocumentsDirectory();
      final docsDir = Directory('${appDir.path}/documents');
      if (!await docsDir.exists()) {
        await docsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = image.path.split('.').last;
      final newPath = '${docsDir.path}/doc_$timestamp.$ext';

      await File(image.path).copy(newPath);

      if (!mounted) return;
      await _showAddDocumentDialog(newPath);
    } catch (e) {
      if (mounted) showSnack(context, 'فشل في اختيار الصورة: $e', isError: true);
    }
  }

  Future<void> _showAddDocumentDialog(String imagePath) async {
    String selectedCategory = 'other';
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

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
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('📷 إضافة مستند جديد',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),

              // ▌ اختيار التصنيف
              const Text('التصنيف:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.entries.map((e) {
                  final isSelected = selectedCategory == e.key;
                  return ChoiceChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => setBS(() => selectedCategory = e.key),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.dark,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textMuted,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              AppTextField(hint: 'عنوان المستند *', controller: titleCtrl),
              const SizedBox(height: 10),
              AppTextField(hint: 'ملاحظات (اختياري)', controller: notesCtrl, maxLines: 2),
              const SizedBox(height: 16),

              PrimaryButton(
                text: '💾 حفظ المستند',
                onTap: () {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) {
                    showSnack(ctx, 'أدخل عنوان المستند', isError: true);
                    return;
                  }

                  setState(() {
                    _documents.add({
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'title': title,
                      'path': imagePath,
                      'category': selectedCategory,
                      'notes': notesCtrl.text.trim(),
                      'created_at': DateTime.now().toIso8601String(),
                    });
                  });

                  _saveDocuments();
                  Navigator.pop(ctx);
                  showSnack(context, 'تم حفظ المستند ✅');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewDocument(Map<String, dynamic> doc) {
    final file = File(doc['path'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.image, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc['title'] ?? '',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      Text(_categories[doc['category']] ?? doc['category'] ?? '',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),

          // Image
          if (file.existsSync())
            Expanded(
              child: InteractiveViewer(
                child: Image.file(file, fit: BoxFit.contain),
              ),
            )
          else
            const Expanded(
              child: Center(
                child: Text('❌ الملف غير موجود',
                    style: TextStyle(color: AppColors.danger)),
              ),
            ),

          // Actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareDocument(doc),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('مشاركة'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _deleteDocument(doc),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('حذف'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareDocument(Map<String, dynamic> doc) async {
    final path = doc['path'] ?? '';
    if (path.isEmpty) {
      showSnack(context, 'الملف غير موجود', isError: true);
      return;
    }

    await Share.shareXFiles(
      [XFile(path)],
      text: doc['title'] ?? 'مستند من صيدلي',
    );
  }

  Future<void> _deleteDocument(Map<String, dynamic> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('حذف المستند', style: TextStyle(color: AppColors.danger)),
        content: Text('هل تريد حذف "${doc['title']}"؟\n⚠️ لا يمكن التراجع.',
            style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // ▌ حذف الملف من المجلد
      try {
        final file = File(doc['path'] ?? '');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}

      // ▌ حذف من القائمة
      setState(() {
        _documents.removeWhere((d) => d['id'] == doc['id']);
      });
      await _saveDocuments();

      if (mounted) showSnack(context, 'تم حذف المستند ✅');
    }
  }

  Future<void> _showAddOptions() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('➕ إضافة مستند',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.camera_alt,
                    title: '📷 كاميرا',
                    subtitle: 'تصوير مستند جديد',
                    color: AppColors.primary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(fromCamera: true);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.photo_library,
                    title: '🖼️ من المعرض',
                    subtitle: 'اختيار من الصور',
                    color: AppColors.accent,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(fromCamera: false);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ▌ تجميع حسب التصنيف
    final groupedDocs = <String, List<Map<String, dynamic>>>{};
    for (final doc in _documents) {
      final cat = doc['category'] ?? 'other';
      groupedDocs.putIfAbsent(cat, () => []).add(doc);
    }

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('📁 المستندات والصور',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.darkCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _documents.isEmpty
              ? EmptyState(
                  emoji: '📷',
                  title: 'لا توجد مستندات',
                  subtitle: 'أضف صور وفواتير ومستندات\nالتي تحتاجها للوزارة أو للتخزين',
                  buttonText: 'إضافة مستند',
                  onButton: _showAddOptions,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groupedDocs.length,
                  itemBuilder: (ctx, i) {
                    final category = groupedDocs.keys.elementAt(i);
                    final docs = groupedDocs[category]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ▌ Header التصنيف
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Text(_categories[category] ?? category,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  )),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('${docs.length}',
                                    style: const TextStyle(color: AppColors.primary, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),

                        // ▌ صور التصنيف
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                          itemCount: docs.length,
                          itemBuilder: (ctx, j) {
                            final doc = docs[j];
                            final file = File(doc['path'] ?? '');

                            return GestureDetector(
                              onTap: () => _viewDocument(doc),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.darkCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.darkBorder),
                                ),
                                child: Stack(
                                  children: [
                                    // ▌ الصورة
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: file.existsSync()
                                          ? Image.file(file, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                                          : const Center(
                                              child: Icon(Icons.broken_image, color: AppColors.textMuted, size: 32),
                                            ),
                                    ),

                                    // ▌ العنوان
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.7),
                                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                        ),
                                        child: Text(
                                          doc['title'] ?? '',
                                          style: const TextStyle(color: Colors.white, fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'documents_fab',
        onPressed: _showAddOptions,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_photo_alternate, color: Colors.white),
        label: const Text('إضافة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ▌ بطاقة اختيار الإجراء
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
