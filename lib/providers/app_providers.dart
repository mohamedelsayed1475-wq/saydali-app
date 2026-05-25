import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';

// ── Provider للثيم ──────────────────────────────────────────────────
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_theme') ?? 'dark';
    _mode = saved == 'light' ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', isDark ? 'dark' : 'light');
    notifyListeners();
  }
}

// ── Provider للنواقص ──────────────────────────────────────────────────
class ShortagesProvider extends ChangeNotifier {
  List<Shortage> _shortages = [];
  bool _loading = false;
  String _filter = 'all';
  String _search = '';
  StreamSubscription<void>? _syncSubscription;

  ShortagesProvider() {
    _syncSubscription = SyncService.instance.onSyncComplete.listen((_) {
      load();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  List<Shortage> get shortages => _shortages;
  bool get loading => _loading;
  String get filter => _filter;
  String get search => _search;

  List<Shortage> get filtered => _shortages.where((s) {
        final matchFilter = _filter == 'all' || s.status == _filter;
        final matchSearch = _search.isEmpty ||
            s.name.contains(_search) ||
            s.company.contains(_search);
        return matchFilter && matchSearch;
      }).toList();

  Map<String, int> get stats => {
        'total': _shortages.length,
        'pending': _shortages.where((s) => s.status == 'pending').length,
        'offered': _shortages.where((s) => s.status == 'offered').length,
        'covered': _shortages.where((s) => s.status == 'covered').length,
        'stubborn': _shortages.where((s) => s.status == 'stubborn').length,
      };

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    await DatabaseHelper.instance.autoCloseOldPendingShortages();
    final data = await DatabaseHelper.instance.getShortages();
    _shortages = data.map(Shortage.fromMap).toList();
    if (!silent) {
      _loading = false;
    }
    notifyListeners();
  }

  void setFilter(String f) {
    _filter = f;
    notifyListeners();
  }

  void setSearch(String s) {
    _search = s;
    notifyListeners();
  }

  Future<void> add(Map<String, dynamic> data) async {
    await DatabaseHelper.instance.insertShortage(data);
    await load();
  }

  Future<void> update(int id, Map<String, dynamic> data) async {
    await DatabaseHelper.instance.updateShortage(id, data);
    await load();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteShortage(id);
    await load();
  }
}

// ── Provider للعملاء ──────────────────────────────────────────────────
class CustomersProvider extends ChangeNotifier {
  List<Customer> _customers = [];
  bool _loading = false;
  StreamSubscription<void>? _syncSubscription;

  CustomersProvider() {
    _syncSubscription = SyncService.instance.onSyncComplete.listen((_) {
      load();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  List<Customer> get customers => _customers;
  bool get loading => _loading;
  double get totalDebt => _customers.fold(0, (sum, c) => sum + c.totalDebt);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final data = await DatabaseHelper.instance.getCustomers();
    _customers = data.map(Customer.fromMap).toList();
    _loading = false;
    notifyListeners();
  }

  Future<void> add(Map<String, dynamic> data) async {
    if (data['photo_url'] != null && !data['photo_url'].startsWith('http')) {
      final url = await SupabaseService.instance.uploadCustomerPhoto(
        data['photo_url'],
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      if (url != null) data['photo_url'] = url;
    }
    await DatabaseHelper.instance.insertCustomer(data);
    await load();
  }

  Future<void> update(int id, Map<String, dynamic> data) async {
    if (data['photo_url'] != null && !data['photo_url'].startsWith('http')) {
      final url = await SupabaseService.instance.uploadCustomerPhoto(
        data['photo_url'],
        id.toString(),
      );
      if (url != null) data['photo_url'] = url;
    }
    await DatabaseHelper.instance.updateCustomer(id, data);
    await load();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteCustomer(id);
    await load();
  }

  Future<void> addTransaction(Map<String, dynamic> data) async {
    if (data['receipt_url'] != null && !data['receipt_url'].startsWith('http')) {
      final url = await SupabaseService.instance.uploadReceiptPhoto(
        data['receipt_url'],
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      if (url != null) data['receipt_url'] = url;
    }
    await DatabaseHelper.instance.addDebtTransaction(data);
    await load();
  }
}

// ── Provider للمندوبين ──────────────────────────────────────────────────
class RepsProvider extends ChangeNotifier {
  List<Representative> _reps = [];
  bool _loading = false;
  StreamSubscription<void>? _syncSubscription;

  RepsProvider() {
    _syncSubscription = SyncService.instance.onSyncComplete.listen((_) {
      load();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  List<Representative> get reps => _reps;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final data = await DatabaseHelper.instance.getReps();
    _reps = data.map(Representative.fromMap).toList();
    _loading = false;
    notifyListeners();
  }

  Future<void> add(Map<String, dynamic> data) async {
    await DatabaseHelper.instance.insertRep(data);
    await load();
  }

  Future<void> update(int id, Map<String, dynamic> data) async {
    await DatabaseHelper.instance.updateRep(id, data);
    await load();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteRep(id);
    await load();
  }
}
