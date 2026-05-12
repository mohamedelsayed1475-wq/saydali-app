import 'package:flutter/material.dart';
import '../models/models.dart';

/// Provider لتتبع المستخدم الحالي (المالك أو المساعد)
class CurrentUserProvider extends ChangeNotifier {
  Assistant? _currentUser;
  bool _isOwner = true;

  /// المستخدم الحالي (null = المالك)
  Assistant? get currentUser => _currentUser;

  /// هل المستخدم الحالي هو المالك؟
  bool get isOwner => _isOwner;

  /// اسم المستخدم الحالي
  String get currentName => _isOwner ? 'المالك' : (_currentUser?.name ?? 'مساعد');

  /// معرّف المساعد الحالي (null للمالك)
  int? get currentAssistantId => _currentUser?.id;

  // ── تسجيل الدخول كمالك ──
  void loginAsOwner() {
    _currentUser = null;
    _isOwner = true;
    notifyListeners();
  }

  // ── تسجيل الدخول كمساعد ──
  void loginAsAssistant(Assistant assistant) {
    _currentUser = assistant;
    _isOwner = false;
    notifyListeners();
  }

  // ── تسجيل الخروج ──
  void logout() {
    _currentUser = null;
    _isOwner = true;
    notifyListeners();
  }

  // ── فحص الصلاحيات ──

  /// هل يمكنه إضافة ديون؟
  bool get canAddDebt => _isOwner || (_currentUser?.canAddDebt ?? false);

  /// هل يمكنه تعديل ديون؟
  bool get canEditDebt => _isOwner || (_currentUser?.canEditDebt ?? false);

  /// هل يمكنه الحذف؟
  bool get canDelete => _isOwner || (_currentUser?.canDelete ?? false);

  /// هل يمكنه عرض التقارير؟
  bool get canViewReports => _isOwner || (_currentUser?.canViewReports ?? false);

  /// هل يمكنه إدارة الفواتير؟
  bool get canManageInvoices => _isOwner || (_currentUser?.canManageInvoices ?? false);

  /// فحص صلاحية بالاسم
  bool hasPermission(String permission) {
    if (_isOwner) return true;
    switch (permission) {
      case 'add_debt':
        return canAddDebt;
      case 'edit_debt':
        return canEditDebt;
      case 'delete':
        return canDelete;
      case 'view_reports':
        return canViewReports;
      case 'manage_invoices':
        return canManageInvoices;
      default:
        return false;
    }
  }
}
