import 'package:intl/intl.dart';

final NumberFormat currencyFormat = NumberFormat.currency(
  locale: 'es_MX',
  symbol: r'$',
  decimalDigits: 2,
);

final DateFormat dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm', 'es_MX');
final DateFormat dateFormat = DateFormat('dd/MM', 'es_MX');
final DateFormat weekdayFormat = DateFormat('EEE', 'es_MX');

String formatCurrency(num value) => currencyFormat.format(value);

/// Cantidad sin ".0" sobrante: 3.0 → "3", 1.5 → "1.5", 0.25 → "0.25".
String formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
