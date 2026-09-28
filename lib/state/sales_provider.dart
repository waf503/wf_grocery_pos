import 'package:flutter/foundation.dart';

import '../models/sale.dart';

class SalesProvider extends ChangeNotifier {
  SalesProvider() : _sales = _buildMockHistory();

  final List<Sale> _sales;

  List<Sale> get sales => List.unmodifiable(_sales.reversed);

  void addSale(Sale sale) {
    _sales.add(sale);
    notifyListeners();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Sale> salesOnDay(DateTime day) =>
      _sales.where((s) => _isSameDay(s.date, day)).toList();

  double get todayTotal {
    final now = DateTime.now();
    return salesOnDay(now).fold(0.0, (sum, s) => sum + s.total);
  }

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

  List<MapEntry<String, int>> topProducts({int limit = 5}) {
    final counts = <String, int>{};
    for (final sale in _sales) {
      for (final item in sale.items) {
        counts[item.productName] = (counts[item.productName] ?? 0) + item.quantity;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  String nextId() => 'v${DateTime.now().millisecondsSinceEpoch}';

  static List<Sale> _buildMockHistory() {
    final now = DateTime.now();
    final history = <Sale>[];
    final dailyTotals = [420.0, 610.0, 380.0, 705.0, 540.0, 890.0];
    for (int i = 0; i < dailyTotals.length; i++) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: dailyTotals.length - i));
      history.add(
        Sale(
          id: 'seed$i',
          date: day.add(const Duration(hours: 12)),
          items: [
            SaleItem(productName: 'Coca-Cola 600ml', quantity: 6, unitPrice: 18.0),
            SaleItem(productName: 'Sabritas Original', quantity: 4, unitPrice: 17.0),
            SaleItem(productName: 'Arroz Morelos 1kg', quantity: 3, unitPrice: 32.5),
          ],
          total: dailyTotals[i],
          paymentMethod: PaymentMethod.cash,
        ),
      );
    }
    return history;
  }
}
