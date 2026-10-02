import '../../../models/unit.dart';

/// Resultado de intentar borrar una unidad: si hay productos que la usan no
/// se puede, y la UI muestra un mensaje claro en vez de un error críptico.
enum DeleteUnitError { hasProducts }

class DeleteUnitResult {
  const DeleteUnitResult.success() : error = null;
  const DeleteUnitResult.failure(this.error);

  final DeleteUnitError? error;
  bool get isSuccess => error == null;
}

abstract class UnitRepository {
  Stream<List<Unit>> watchAll();

  Future<void> add({
    required String name,
    String? abbreviation,
    required bool allowsDecimals,
  });

  Future<void> update(Unit unit);

  Future<DeleteUnitResult> delete(String id);
}
