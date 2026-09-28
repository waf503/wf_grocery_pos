import 'package:flutter/foundation.dart';

import '../models/cash_session.dart';

class CashProvider extends ChangeNotifier {
  CashSession? _current;
  final List<CashSession> _history = [];

  CashSession? get current => _current;
  bool get isOpen => _current?.isOpen ?? false;
  List<CashSession> get history => List.unmodifiable(_history.reversed);

  void openSession(double openingAmount) {
    _current = CashSession(openingAmount: openingAmount, openedAt: DateTime.now());
    notifyListeners();
  }

  void registerSale(double amount, {required String note}) {
    _current?.movements.add(
      CashMovement(
        type: CashMovementType.sale,
        amount: amount,
        note: note,
        time: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void registerMovement(CashMovementType type, double amount, String note) {
    _current?.movements.add(
      CashMovement(type: type, amount: amount, note: note, time: DateTime.now()),
    );
    notifyListeners();
  }

  void closeSession(double countedAmount) {
    final session = _current;
    if (session == null) return;
    session.closedAt = DateTime.now();
    session.closingCountedAmount = countedAmount;
    _history.add(session);
    _current = null;
    notifyListeners();
  }
}
