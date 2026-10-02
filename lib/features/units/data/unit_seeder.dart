import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';

/// Si la tabla `units` está vacía, la llena con las unidades más comunes de
/// una tienda de abarrotes. Devuelve un mapa nombre → id para que
/// `seedProductsIfEmpty` pueda referenciar la unidad real de cada producto.
Future<Map<String, String>> seedUnitsIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.unitsTable).get();
  if (existing.isNotEmpty) {
    return {for (final row in existing) row.name: row.id};
  }

  final ids = <String, String>{};

  Future<void> unit(String name, String abbreviation, {bool decimals = false}) async {
    final row = await db.into(db.unitsTable).insertReturning(
          UnitsTableCompanion.insert(
            name: name,
            abbreviation: Value(abbreviation),
            allowsDecimals: Value(decimals),
          ),
        );
    ids[name] = row.id;
  }

  await unit('Pieza', 'pz');
  await unit('Paquete', 'paq');
  await unit('Kilogramo', 'kg', decimals: true);
  await unit('Libra', 'lb', decimals: true);
  await unit('Litro', 'L', decimals: true);

  return ids;
}
