import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// ── خدمة Google Drive للنسخ الاحتياطي ──
/// تتيح رفع واستعادة قاعدة البيانات من Google Drive
class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._();
  GoogleDriveService._();

  static const _scopes = [drive.DriveApi.driveFileScope];
  static const _backupFolder = 'SaydaliPRO_Backup';
  static const _dbFileName = 'saydali_pro.db';

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  GoogleSignInAccount? _currentUser;

  /// هل المستخدم مسجل دخول؟
  bool get isSignedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;
  String? get userName => _currentUser?.displayName;

  /// تسجيل الدخول بـ Google
  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser != null;
    } catch (e) {
      return false;
    }
  }

  /// تسجيل الخروج
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  /// الحصول على Drive API client
  Future<drive.DriveApi?> _getDriveApi() async {
    if (_currentUser == null) {
      final success = await signIn();
      if (!success) return null;
    }
    final httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) return null;
    return drive.DriveApi(httpClient);
  }

  /// البحث أو إنشاء مجلد النسخ الاحتياطي
  Future<String?> _getOrCreateFolder(drive.DriveApi driveApi) async {
    // البحث عن المجلد
    final query =
        "name = '$_backupFolder' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await driveApi.files.list(q: query, spaces: 'drive');
    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id;
    }

    // إنشاء مجلد جديد
    final folder = drive.File()
      ..name = _backupFolder
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await driveApi.files.create(folder);
    return created.id;
  }

  /// رفع نسخة احتياطية على Google Drive
  Future<({bool success, String message})> uploadBackup() async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) {
        return (success: false, message: 'فشل تسجيل الدخول بـ Google');
      }

      // الحصول على مسار قاعدة البيانات
      final dbPath = await getDatabasesPath();
      final localPath = p.join(dbPath, _dbFileName);
      final file = File(localPath);

      if (!await file.exists()) {
        return (success: false, message: 'قاعدة البيانات غير موجودة');
      }

      // الحصول أو إنشاء المجلد
      final folderId = await _getOrCreateFolder(driveApi);
      if (folderId == null) {
        return (success: false, message: 'فشل إنشاء مجلد النسخ الاحتياطي');
      }

      // حذف النسخة القديمة إن وجدت
      final existing = await driveApi.files.list(
        q: "name = '$_dbFileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      if (existing.files != null) {
        for (final f in existing.files!) {
          await driveApi.files.delete(f.id!);
        }
      }

      // رفع الملف الجديد
      final driveFile = drive.File()
        ..name = _dbFileName
        ..parents = [folderId]
        ..description =
            'نسخة احتياطية من صيدلي PRO - ${DateTime.now().toIso8601String()}';

      final fileSize = await file.length();
      await driveApi.files.create(
        driveFile,
        uploadMedia:
            drive.Media(file.openRead(), fileSize),
      );

      return (
        success: true,
        message: 'تم رفع النسخة الاحتياطية بنجاح على Google Drive ✅'
      );
    } catch (e) {
      return (success: false, message: 'خطأ: $e');
    }
  }

  /// استعادة نسخة احتياطية من Google Drive
  Future<({bool success, String message})> downloadBackup() async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) {
        return (success: false, message: 'فشل تسجيل الدخول بـ Google');
      }

      // البحث عن المجلد
      final folderId = await _getOrCreateFolder(driveApi);
      if (folderId == null) {
        return (success: false, message: 'مجلد النسخ الاحتياطي غير موجود');
      }

      // البحث عن الملف
      final result = await driveApi.files.list(
        q: "name = '$_dbFileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );

      if (result.files == null || result.files!.isEmpty) {
        return (success: false, message: 'لا توجد نسخة احتياطية على Google Drive');
      }

      final fileId = result.files!.first.id!;

      // تحميل الملف
      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // حفظ الملف محلياً
      final dbPath = await getDatabasesPath();
      final localPath = p.join(dbPath, _dbFileName);
      final localFile = File(localPath);

      final List<int> bytes = [];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }
      await localFile.writeAsBytes(bytes);

      return (
        success: true,
        message: 'تم استعادة النسخة الاحتياطية بنجاح ✅\nأعد تشغيل التطبيق لتحديث البيانات'
      );
    } catch (e) {
      return (success: false, message: 'خطأ: $e');
    }
  }

  /// حذف النسخة الاحتياطية من Drive
  Future<bool> deleteBackup() async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return false;

      final folderId = await _getOrCreateFolder(driveApi);
      if (folderId == null) return false;

      final result = await driveApi.files.list(
        q: "name = '$_dbFileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );

      if (result.files != null) {
        for (final f in result.files!) {
          await driveApi.files.delete(f.id!);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// فحص وجود نسخة احتياطية
  Future<String?> checkBackupDate() async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;

      final folderId = await _getOrCreateFolder(driveApi);
      if (folderId == null) return null;

      final result = await driveApi.files.list(
        q: "name = '$_dbFileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, description)',
      );

      if (result.files == null || result.files!.isEmpty) return null;
      final modified = result.files!.first.modifiedTime;
      return modified?.toLocal().toString().substring(0, 16);
    } catch (_) {
      return null;
    }
  }
}
