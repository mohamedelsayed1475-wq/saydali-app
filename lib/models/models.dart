// ── نموذج الناقص ──────────────────────────────────────────────────
class Shortage {
  final int? id;
  final String name;
  final String company;
  final int quantity;
  final String status; // pending, offered, covered, stubborn
  final bool isUrgent;
  final String? notes;
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
        createdAt: DateTime.parse(map['created_at']),
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
  final DateTime createdAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.totalDebt = 0.0,
    this.dueDate,
    this.photoUrl,
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
        createdAt: DateTime.parse(map['created_at']),
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
  final DateTime transactionDate;

  DebtTransaction({
    this.id,
    required this.customerId,
    required this.amount,
    required this.type,
    this.description,
    this.receiptUrl,
    required this.transactionDate,
  });

  factory DebtTransaction.fromMap(Map<String, dynamic> map) => DebtTransaction(
        id: map['id'],
        customerId: map['customer_id'],
        amount: (map['amount'] as num).toDouble(),
        type: map['type'],
        description: map['description'],
        receiptUrl: map['receipt_url'],
        transactionDate: DateTime.parse(map['transaction_date']),
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
      };

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
