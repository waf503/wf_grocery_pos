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
