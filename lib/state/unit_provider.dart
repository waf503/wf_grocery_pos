import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/units/data/unit_repository.dart';
import '../models/unit.dart';

class UnitProvider extends ChangeNotifier {
  UnitProvider(this._repository) {
    _subscription = _repository.watchAll().listen((rows) {
      _units = rows;
      notifyListeners();
    });
  }

  final UnitRepository _repository;
  late final StreamSubscription<List<Unit>> _subscription;

  List<Unit> _units = [];

  List<Unit> get units => List.unmodifiable(_units);

  Unit? byId(String id) {
    for (final u in _units) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// `true` si ya existe otra unidad con ese nombre (sin importar mayúsculas).
  bool nameTaken(String name, {String? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return _units.any((u) => u.id != exceptId && u.name.toLowerCase() == normalized);
  }

  Future<void> addUnit({
    required String name,
    String? abbreviation,
    required bool allowsDecimals,
  }) {
    return _repository.add(
      name: name.trim(),
      abbreviation: abbreviation,
      allowsDecimals: allowsDecimals,
    );
  }

  Future<void> updateUnit(Unit unit) => _repository.update(unit);

  Future<DeleteUnitResult> deleteUnit(String id) => _repository.delete(id);

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
