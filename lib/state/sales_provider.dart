import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/sales/data/sale_repository.dart';
import '../models/sale.dart';

/// Estado de ventas. Mantiene en memoria las ventas de los últimos
/// [historyDays] días (leídas de la base de datos y actualizadas solas);
/// alcanza para el Dashboard y los Reportes sin cargar todo el historial.
class SalesProvider extends ChangeNotifier {
  SalesProvider(this._repository, {this.historyDays = 30}) {
    final today = DateTime.now();
    final from = DateTime(today.year, today.month, today.day).subtract(Duration(days: historyDays - 1));
    _subscription = _repository.watchSince(from).listen((rows) {
      _sales = rows;
      notifyListeners();
    });
  }

  final SaleRepository _repository;
  final int historyDays;
  late final StreamSubscription<List<Sale>> _subscription;

  List<Sale> _sales = [];

  /// De la más reciente a la más antigua.
  List<Sale> get sales => List.unmodifiable(_sales);

  /// Registra la venta (transacción completa) y devuelve la venta guardada.
  Future<Sale> registerSale({
    required String sessionId,
    required List<SaleLine> lines,
    required PaymentMethod paymentMethod,
    String? customerId,
    String? customerName,
  }) {
    return _repository.registerSale(
      sessionId: sessionId,
      lines: lines,
      paymentMethod: paymentMethod,
      customerId: customerId,
      customerName: customerName,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Sale> salesOnDay(DateTime day) => _sales.where((s) => _isSameDay(s.date, day)).toList();

  double get todayTotal => salesOnDay(DateTime.now()).fold(0.0, (sum, s) => sum + s.total);

  int get todayCount => salesOnDay(DateTime.now()).length;

  /// Total vendido por cada uno de los últimos [days] días (incluyendo hoy).
  List<MapEntry<DateTime, double>> lastDaysTotals(int days) {
    final now = DateTime.now();
    final result = <MapEntry<DateTime, double>>[];
    for (int i = days - 1; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final total = salesOnDay(day).fold(0.0, (sum, s) => sum + s.total);
      result.add(MapEntry(day, total));
    }
    return result;
  }

  /// Productos más vendidos (por cantidad) en el período cargado.
  List<MapEntry<String, double>> topProducts({int limit = 5}) {
    final counts = <String, double>{};
    for (final sale in _sales) {
      for (final item in sale.items) {
        counts[item.productName] = (counts[item.productName] ?? 0) + item.quantity;
      }
    }
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
