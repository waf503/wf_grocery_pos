import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/money.dart';
import '../features/cash/data/cash_repository.dart';
import '../models/cash_session.dart';

/// Estado de la caja. La sesión abierta vive en la base de datos, así que
/// sobrevive a cerrar la app; este provider solo refleja lo que el
/// repositorio emite.
class CashProvider extends ChangeNotifier {
  CashProvider(this._repository) {
    _subscription = _repository.watchCurrent().listen((session) {
      _current = session;
      notifyListeners();
    });
  }

  final CashRepository _repository;
  late final StreamSubscription<CashSession?> _subscription;

  CashSession? _current;

  CashSession? get current => _current;
  bool get isOpen => _current?.isOpen ?? false;

  Future<void> openSession(double openingAmount) async {
    await _repository.open(openingCents: toCents(openingAmount));
  }

  Future<void> registerMovement(CashMovementType type, double amount, String note) async {
    final session = _current;
    if (session == null) return;
    await _repository.addMovement(
      sessionId: session.id,
      type: type,
      amountCents: toCents(amount),
      note: note,
    );
  }

  Future<void> closeSession(double countedAmount) async {
    final session = _current;
    if (session == null) return;
    await _repository.close(sessionId: session.id, countedCents: toCents(countedAmount));
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
