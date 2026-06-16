import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';
import '../services/supabase_service.dart';
import '../providers/current_user_provider.dart';
import '../widgets/common_widgets.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  final _picker = ImagePicker();
  final _contentController = TextEditingController();
  File? _selectedImage;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadPosts(silent: false);
    // تحديث تلقائي كل 15 ثانية لجلب المنشورات الجديدة
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadPosts(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final posts = await SupabaseService.instance.fetchCommunityPosts();
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading community posts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1080,
      );
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'تعذر اختيار الصورة', isError: true);
      }
    }
  }

  Future<void> _createNewPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImage == null) {
      showSnack(context, 'يرجى كتابة نص أو اختيار صورة للمنشور', isError: true);
      return;
    }

    setState(() => _isSending = true);

    try {
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await SupabaseService.instance.uploadCommunityPhoto(_selectedImage!.path);
        if (imageUrl == null) {
          if (mounted) {
            showSnack(context, 'فشل رفع الصورة، يرجى التحقق من اتصال السحابة', isError: true);
          }
          setState(() => _isSending = false);
          return;
        }
      }

      final userProvider = context.read<CurrentUserProvider>();
      final senderName = userProvider.currentName;

      final success = await SupabaseService.instance.insertCommunityPost(
        senderName: senderName,
        content: content,
        imageUrl: imageUrl,
      );

      if (success) {
        _contentController.clear();
        setState(() {
          _selectedImage = null;
        });
        if (mounted) {
          showSnack(context, 'تم نشر منشورك بنجاح 🎉');
        }
        await _loadPosts(silent: false);
      } else {
        if (mounted) {
          showSnack(context, 'حدث خطأ أثناء النشر، حاول لاحقاً', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'حدث خطأ في الاتصال بالشبكة', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('حذف المنشور', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('هل أنت متأكد من رغبتك في حذف هذا المنشور نهائياً؟', style: TextStyle(color: AppColors.textLight)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final success = await SupabaseService.instance.deleteCommunityPost(postId);
      if (success) {
        if (mounted) showSnack(context, 'تم حذف المنشور بنجاح');
        await _loadPosts(silent: false);
      } else {
        if (mounted) {
          showSnack(context, 'فشل حذف المنشور. قد لا تمتلك الصلاحية الكافية', isError: true);
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<CurrentUserProvider>();

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مجتمع الصيدلية',
                style: TextStyle(color: AppColors.textColor, fontWeight: FontWeight.w700)),
            Text('مساحة تواصل داخلية لأعضاء الصيدلية',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
      body: Column(
        children: [
          // شريط كتابة منشور جديد
          _buildNewPostArea(context),
          const Divider(color: AppColors.darkBorder, height: 1),
          // قائمة المنشورات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _posts.isEmpty
                    ? const EmptyState(
                        emoji: '💬',
                        title: 'المجتمع هادئ حالياً',
                        subtitle: 'اكتب أول منشور وشاركه مع فريق الصيدلية!',
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadPosts(silent: false),
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _posts.length,
                          itemBuilder: (ctx, i) => _buildPostCard(ctx, _posts[i], userProvider),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewPostArea(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.darkCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.2),
                child: const Text('✍️', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _contentController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'ماذا يدور في صيدليتك اليوم؟ اكتب منشوراً...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 12),
            Stack(
              alignment: Alignment.topLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _selectedImage!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _selectedImage = null),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                    tooltip: 'معرض الصور',
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_rounded, color: AppColors.warning),
                    tooltip: 'الكاميرا',
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                ],
              ),
              _isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                    )
                  : ElevatedButton.icon(
                      onPressed: _createNewPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text(
                        'نشر',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, Map<String, dynamic> post, CurrentUserProvider userProvider) {
    final senderName = post['sender_name']?.toString() ?? 'مجهول';
    final content = post['content']?.toString() ?? '';
    final imageUrl = post['image_url']?.toString();
    final createdAtStr = post['created_at']?.toString();
    
    DateTime? createdAt;
    if (createdAtStr != null) {
      try {
        createdAt = DateTime.parse(createdAtStr).toLocal();
      } catch (_) {}
    }

    final timeFormatted = createdAt != null
        ? DateFormat('yyyy-MM-dd hh:mm a').format(createdAt)
        : 'منذ قليل';

    // التحقق من إمكانية حذف هذا المنشور (المالك، أو صاحب المنشور نفسه)
    final bool canDeletePost = userProvider.isOwner || (userProvider.currentName == senderName);
    
    final bool isSenderOwner = senderName == 'المالك';

    return Card(
      color: AppColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isSenderOwner 
                      ? AppColors.warning.withOpacity(0.2) 
                      : AppColors.primary.withOpacity(0.2),
                  child: Text(
                    senderName.isNotEmpty ? senderName[0] : '👤',
                    style: TextStyle(
                      color: isSenderOwner ? AppColors.warning : AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            senderName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSenderOwner 
                                  ? AppColors.warning.withOpacity(0.15) 
                                  : AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSenderOwner 
                                    ? AppColors.warning.withOpacity(0.3) 
                                    : AppColors.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              isSenderOwner ? 'المالك' : 'مساعد',
                              style: TextStyle(
                                color: isSenderOwner ? AppColors.warning : AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeFormatted,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canDeletePost)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                    onPressed: () => _deletePost(post['id'].toString()),
                  ),
              ],
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(
                content,
                style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: AppColors.darkBorder.withOpacity(0.5),
                      child: const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 150,
                      color: AppColors.darkBorder.withOpacity(0.5),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_rounded, color: AppColors.danger, size: 36),
                            SizedBox(height: 8),
                            Text(
                              'تعذر تحميل الصورة',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
