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
        createdAt: DateTime.parse(map['created_at']),
        updatedAt: DateTime.parse(map['updated_at']),
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
      case 'pending': return 'بانتظار رد';
      case 'offered': return 'عرض موصول';
      case 'covered': return 'تمت التغطية';
      case 'stubborn': return 'مستعصي';
      default: return status;
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
    int? id, String? name, String? company, int? quantity,
    String? status, bool? isUrgent, String? notes,
  }) => Shortage(
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
  final DateTime createdAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.totalDebt = 0.0,
    required this.createdAt,
  });

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'],
        name: map['name'],
        phone: map['phone'],
        address: map['address'],
        totalDebt: (map['total_debt'] as num?)?.toDouble() ?? 0.0,
        createdAt: DateTime.parse(map['created_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'total_debt': totalDebt,
      };
}

// ── نموذج معاملة الدين ──────────────────────────────────────────────────
class DebtTransaction {
  final int? id;
  final int customerId;
  final double amount;
  final String type; // debt أو payment
  final String? description;
  final DateTime transactionDate;

  DebtTransaction({
    this.id,
    required this.customerId,
    required this.amount,
    required this.type,
    this.description,
    required this.transactionDate,
  });

  factory DebtTransaction.fromMap(Map<String, dynamic> map) => DebtTransaction(
        id: map['id'],
        customerId: map['customer_id'],
        amount: (map['amount'] as num).toDouble(),
        type: map['type'],
        description: map['description'],
        transactionDate: DateTime.parse(map['transaction_date']),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'customer_id': customerId,
        'amount': amount,
        'type': type,
        'description': description,
      };
}
