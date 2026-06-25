// ── نموذج الناقص ──────────────────────────────────────────────────
class Shortage {
  final int? id;
  final String name;
  final String company;
  final int quantity;
  final String status; // pending, offered, covered, stubborn
  final bool isUrgent;
  final String? notes;
  final String? createdBy; // ← اسم من أضاف الناقص
  final DateTime createdAt;
  final DateTime updatedAt;

  Shortage({
    this.id,
    required this.name,
    this.company = 'غير محدد',
    this.quantity = 1,
    this.status = 'pending',
    this.isUrgent = false,
    this.notes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Shortage.fromMap(Map<String, dynamic> map) => Shortage(
        id: map['id'],
        name: map['name'],
        company: map['company'] ?? 'غير محدد',
        quantity: map['quantity'] ?? 1,
        status: map['status'] ?? 'pending',
        isUrgent: (map['is_urgent'] ?? 0) == 1,
        notes: map['notes'],
        createdBy: map['created_by'],
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'company': company,
        'quantity': quantity,
        'status': status,
        'is_urgent': isUrgent ? 1 : 0,
        'notes': notes,
      };

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'بانتظار رد';
      case 'offered':
        return 'عرض موصول';
      case 'covered':
        return 'تمت التغطية';
      case 'stubborn':
        return 'مستعصي';
      default:
        return status;
    }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return 'منذ $m ${m <= 10 ? 'دقائق' : 'دقيقة'}';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return 'منذ $h ${h <= 10 ? 'ساعات' : 'ساعة'}';
    }
    if (diff.inDays == 1) return 'أمس';
    return 'منذ ${diff.inDays} ${diff.inDays <= 10 ? 'أيام' : 'يوم'}';
  }

  Shortage copyWith({
    int? id,
    String? name,
    String? company,
    int? quantity,
    String? status,
    bool? isUrgent,
    String? notes,
  }) =>
      Shortage(
        id: id ?? this.id,
        name: name ?? this.name,
        company: company ?? this.company,
        quantity: quantity ?? this.quantity,
        status: status ?? this.status,
        isUrgent: isUrgent ?? this.isUrgent,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

// ── نموذج المندوب ──────────────────────────────────────────────────
class Representative {
  final int? id;
  final String name;
  final String? company;
  final String? phone;
  final int rating;
  final int totalCovered;
  final String? notes;
  final DateTime createdAt;

  Representative({
    this.id,
    required this.name,
    this.company,
    this.phone,
    this.rating = 5,
    this.totalCovered = 0,
    this.notes,
    required this.createdAt,
  });

  factory Representative.fromMap(Map<String, dynamic> map) => Representative(
        id: map['id'],
        name: map['name'],
        company: map['company'],
        phone: map['phone'],
        rating: map['rating'] ?? 5,
        totalCovered: map['total_covered'] ?? 0,
        notes: map['notes'],
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'company': company,
        'phone': phone,
        'rating': rating,
        'total_covered': totalCovered,
        'notes': notes,
      };
}

// ── نموذج العميل ──────────────────────────────────────────────────
class Customer {
  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final double totalDebt;
  final DateTime? dueDate;
  final String? photoUrl;
  final String? createdBy; // ← اسم من أضاف العميل
  final DateTime createdAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.totalDebt = 0.0,
    this.dueDate,
    this.photoUrl,
    this.createdBy,
    required this.createdAt,
  });

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'],
        name: map['name'],
        phone: map['phone'],
        address: map['address'],
        totalDebt: (map['total_debt'] as num?)?.toDouble() ?? 0.0,
        dueDate: map['due_date'] != null ? DateTime.tryParse(map['due_date']) : null,
        photoUrl: map['photo_url'],
        createdBy: map['created_by'],
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'total_debt': totalDebt,
        'due_date': dueDate?.toIso8601String(),
        'photo_url': photoUrl,
      };
}

// ── نموذج معاملة الدين ──────────────────────────────────────────────────
class DebtTransaction {
  final int? id;
  final int customerId;
  final double amount;
  final String type; // debt أو payment
  final String? description;
  final String? receiptUrl;
  final String? createdBy; // ← اسم من سجّل المعاملة
  final DateTime transactionDate;

  DebtTransaction({
    this.id,
    required this.customerId,
    required this.amount,
    required this.type,
    this.description,
    this.receiptUrl,
    this.createdBy,
    required this.transactionDate,
  });

  factory DebtTransaction.fromMap(Map<String, dynamic> map) => DebtTransaction(
        id: map['id'],
        customerId: map['customer_id'],
        amount: (map['amount'] as num).toDouble(),
        type: map['type'],
        description: map['description'],
        receiptUrl: map['receipt_url'],
        createdBy: map['created_by'],
        transactionDate: DateTime.tryParse(map['transaction_date']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'customer_id': customerId,
        'amount': amount,
        'type': type,
        'description': description,
        'receipt_url': receiptUrl,
      };
}

// ── نموذج المساعد ──────────────────────────────────────────────────
class Assistant {
  final int? id;
  final String name;
  final String? phone;
  final String pin;
  final String role; // owner, assistant
  final bool canAddDebt;
  final bool canEditDebt;
  final bool canDelete;
  final bool canViewReports;
  final bool canManageInvoices;
  final bool canManageShortages;
  final bool canManageReps;
  final bool isActive;
  final DateTime? subscriptionExpiry;
  final int subscriptionDurationDays;
  final DateTime createdAt;

  Assistant({
    this.id,
    required this.name,
    this.phone,
    required this.pin,
    this.role = 'assistant',
    this.canAddDebt = true,
    this.canEditDebt = false,
    this.canDelete = false,
    this.canViewReports = false,
    this.canManageInvoices = true,
    this.canManageShortages = true,
    this.canManageReps = false,
    this.isActive = true,
    this.subscriptionExpiry,
    this.subscriptionDurationDays = 30,
    required this.createdAt,
  });

  factory Assistant.fromMap(Map<String, dynamic> map) => Assistant(
        id: map['id'],
        name: map['name'],
        phone: map['phone'],
        pin: map['pin'],
        role: map['role'] ?? 'assistant',
        canAddDebt: (map['can_add_debt'] ?? 1) == 1,
        canEditDebt: (map['can_edit_debt'] ?? 0) == 1,
        canDelete: (map['can_delete'] ?? 0) == 1,
        canViewReports: (map['can_view_reports'] ?? 0) == 1,
        canManageInvoices: (map['can_manage_invoices'] ?? 1) == 1,
        canManageShortages: (map['can_manage_shortages'] ?? 1) == 1,
        canManageReps: (map['can_manage_reps'] ?? 0) == 1,
        isActive: (map['is_active'] ?? 1) == 1,
        subscriptionExpiry: map['subscription_expiry'] != null
            ? DateTime.tryParse(map['subscription_expiry'].toString())
            : null,
        subscriptionDurationDays: map['subscription_duration_days'] ?? 30,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'pin': pin,
        'role': role,
        'can_add_debt': canAddDebt ? 1 : 0,
        'can_edit_debt': canEditDebt ? 1 : 0,
        'can_delete': canDelete ? 1 : 0,
        'can_view_reports': canViewReports ? 1 : 0,
        'can_manage_invoices': canManageInvoices ? 1 : 0,
        'can_manage_shortages': canManageShortages ? 1 : 0,
        'can_manage_reps': canManageReps ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'subscription_expiry': subscriptionExpiry?.toIso8601String(),
        'subscription_duration_days': subscriptionDurationDays,
      };

  // ── ميزة المساعدين مفتوحة للجميع مجاناً ──
  bool get isSubscriptionExpired => false;

  String get roleLabel => role == 'owner' ? 'المالك 👑' : 'مساعد 👤';

  String get permissionsSummary {
    final perms = <String>[];
    if (canAddDebt) perms.add('إضافة ديون');
    if (canEditDebt) perms.add('تعديل ديون');
    if (canDelete) perms.add('حذف');
    if (canViewReports) perms.add('تقارير');
    if (canManageInvoices) perms.add('فواتير');
    if (canManageShortages) perms.add('نواقص');
    if (canManageReps) perms.add('مندوبين');
    return perms.isEmpty ? 'بدون صلاحيات' : perms.join(' · ');
  }
}

// ── نموذج سجل النشاط ──────────────────────────────────────────────────
class ActivityLogEntry {
  final int? id;
  final int? assistantId;
  final String assistantName;
  final String action;
  final String? details;
  final String? screen;
  final DateTime createdAt;

  ActivityLogEntry({
    this.id,
    this.assistantId,
    required this.assistantName,
    required this.action,
    this.details,
    this.screen,
    required this.createdAt,
  });

  factory ActivityLogEntry.fromMap(Map<String, dynamic> map) => ActivityLogEntry(
        id: map['id'],
        assistantId: map['assistant_id'],
        assistantName: map['assistant_name'] ?? '',
        action: map['action'] ?? '',
        details: map['details'],
        screen: map['screen'],
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays == 1) return 'أمس';
    return 'منذ ${diff.inDays} يوم';
  }
}

// ── نموذج صلاحية الدواء ──────────────────────────────────────────────────
class MedicationExpiry {
  final int? id;
  final String name;
  final int quantity;
  final DateTime expiryDate;
  final String? supplierName;
  final String? notes;
  final String? cloudId;
  final bool isSynced;
  final String? createdBy;
  final DateTime createdAt;

  MedicationExpiry({
    this.id,
    required this.name,
    this.quantity = 1,
    required this.expiryDate,
    this.supplierName,
    this.notes,
    this.cloudId,
    this.isSynced = false,
    this.createdBy,
    required this.createdAt,
  });

  factory MedicationExpiry.fromMap(Map<String, dynamic> map) => MedicationExpiry(
        id: map['id'],
        name: map['name'] ?? '',
        quantity: map['quantity'] ?? 1,
        expiryDate: DateTime.tryParse(map['expiry_date']?.toString() ?? '') ?? DateTime.now(),
        supplierName: map['supplier_name'],
        notes: map['notes'],
        cloudId: map['cloud_id'],
        isSynced: (map['is_synced'] ?? 0) == 1,
        createdBy: map['created_by'],
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'quantity': quantity,
        'expiry_date': expiryDate.toIso8601String().substring(0, 10), // حفظ التاريخ بصيغة YYYY-MM-DD
        'supplier_name': supplierName,
        'notes': notes,
        'cloud_id': cloudId,
        'is_synced': isSynced ? 1 : 0,
        'created_by': createdBy,
      };

  bool isNearExpiry(int months) {
    final limit = DateTime.now().add(Duration(days: months * 30));
    return expiryDate.isBefore(limit) && expiryDate.isAfter(DateTime.now());
  }

  bool get isExpired => expiryDate.isBefore(DateTime.now());
}

// ── نموذج المصروفات ──────────────────────────────────────────────────
class Expense {
  final int? id;
  final String category;
  final double amount;
  final String? description;
  final DateTime expenseDate;
  final DateTime createdAt;

  Expense({
    this.id,
    required this.category,
    required this.amount,
    this.description,
    required this.expenseDate,
    required this.createdAt,
  });

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'],
        category: map['category'] ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        description: map['description'],
        expenseDate: DateTime.tryParse(map['expense_date']?.toString() ?? '') ?? DateTime.now(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'category': category,
        'amount': amount,
        'description': description,
        'expense_date': expenseDate.toIso8601String().substring(0, 10),
      };
}

// ── نموذج بدائل الأدوية ──────────────────────────────────────────────────
class Alternative {
  final int? id;
  final String medicationName;
  final String alternativeName;
  final String? activeIngredient;

  Alternative({
    this.id,
    required this.medicationName,
    required this.alternativeName,
    this.activeIngredient,
  });

  factory Alternative.fromMap(Map<String, dynamic> map) => Alternative(
        id: map['id'],
        medicationName: map['medication_name'] ?? '',
        alternativeName: map['alternative_name'] ?? '',
        activeIngredient: map['active_ingredient'],
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'medication_name': medicationName,
        'alternative_name': alternativeName,
        'active_ingredient': activeIngredient,
      };
}
