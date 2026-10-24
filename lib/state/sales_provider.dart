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
    _subscription = _repository.watchBetween(from).listen((rows) {
      _sales = rows;
      notifyListeners();
    });
  }

  final SaleRepository _repository;
  final int historyDays;
  late final StreamSubscription<List<Sale>> _subscription;

  List<Sale> _sales = [];

  /// Todas las ventas cargadas (incluidas las anuladas), de la más reciente
  /// a la más antigua. Es lo que muestra el historial.
  List<Sale> get sales => List.unmodifiable(_sales);

  /// Ventas de un rango arbitrario [from, to) leídas directo de la base de
  /// datos (para consultar más allá de [historyDays]), actualizadas solas.
  Stream<List<Sale>> watchRange(DateTime from, DateTime to) => _repository.watchBetween(from, to: to);

  /// Ventas de un turno de caja (incluidas las anuladas), actualizadas solas.
  Stream<List<Sale>> watchSession(String sessionId) => _repository.watchBySession(sessionId);

  /// Solo las ventas vigentes: las anuladas no cuentan en totales ni reportes.
  List<Sale> get completedSales => _sales.where((s) => !s.isVoided).toList();

  /// Registra la venta (transacción completa) y devuelve la venta guardada.
  Future<Sale> registerSale({
    required String sessionId,
    required List<SaleLine> lines,
    required PaymentMethod paymentMethod,
    String? customerId,
    String? customerName,
    int? tenderedCents,
  }) {
    return _repository.registerSale(
      sessionId: sessionId,
      lines: lines,
      paymentMethod: paymentMethod,
      customerId: customerId,
      customerName: customerName,
      tenderedCents: tenderedCents,
    );
  }

  Future<void> voidSale({required String saleId, required String reason, String? cashSessionId}) {
    return _repository.voidSale(saleId: saleId, reason: reason, cashSessionId: cashSessionId);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Sale> salesOnDay(DateTime day) => completedSales.where((s) => _isSameDay(s.date, day)).toList();

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
    for (final sale in completedSales) {
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
