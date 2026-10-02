import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../models/cash_session.dart';
import '../../../models/sale.dart';
import 'sale_repository.dart';

class DriftSaleRepository implements SaleRepository {
  DriftSaleRepository(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<List<Sale>> watchSince(DateTime from) {
    final sales = _db.salesTable;
    final items = _db.saleItemsTable;
    final query = _db.select(sales).join([
      leftOuterJoin(items, items.saleId.equalsExp(sales.id)),
    ])
      ..where(sales.createdAt.isBiggerOrEqualValue(from))
      ..orderBy([OrderingTerm.desc(sales.createdAt), OrderingTerm.desc(sales.number)]);

    return query.watch().map((rows) {
      // Un renglón de resultado por cada ítem: se agrupan por venta,
      // conservando el orden (más reciente primero).
      final bySale = <String, (SalesTableData, List<SaleItemsTableData>)>{};
      for (final row in rows) {
        final sale = row.readTable(sales);
        final entry = bySale.putIfAbsent(sale.id, () => (sale, []));
        final item = row.readTableOrNull(items);
        if (item != null) entry.$2.add(item);
      }
      return [for (final (sale, saleItems) in bySale.values) _toModel(sale, saleItems)];
    });
  }

  @override
  Future<Sale> registerSale({
    required String sessionId,
    required List<SaleLine> lines,
    required PaymentMethod paymentMethod,
    String? customerId,
    String? customerName,
  }) {
    if (lines.isEmpty) throw ArgumentError('Una venta necesita al menos un renglón.');

    return _db.transaction(() async {
      final session = await (_db.select(_db.cashSessionsTable)
            ..where((row) => row.id.equals(sessionId)))
          .getSingleOrNull();
      if (session == null || session.closedAt != null) throw CashSessionClosedException();

      // 1. Validar existencias (sumando por si un producto viene repetido).
      final requested = <String, double>{};
      for (final line in lines) {
        requested[line.productId] = (requested[line.productId] ?? 0) + line.quantity;
      }
      for (final line in lines) {
        final product = await (_db.select(_db.productsTable)
              ..where((row) => row.id.equals(line.productId)))
            .getSingleOrNull();
        if (product == null) throw ProductNotFoundException(line.productName);
        if (product.stock < requested[line.productId]!) {
          throw InsufficientStockException(line.productName, available: product.stock);
        }
      }

      // 2. Folio consecutivo y encabezado.
      final maxNumber = _db.salesTable.number.max();
      final lastNumber = await (_db.selectOnly(_db.salesTable)..addColumns([maxNumber]))
          .map((row) => row.read(maxNumber))
          .getSingle();
      final totalCents = lines.fold<int>(0, (sum, line) => sum + line.subtotalCents);
      final now = _clock();

      final sale = await _db.into(_db.salesTable).insertReturning(
            SalesTableCompanion.insert(
              number: (lastNumber ?? 0) + 1,
              sessionId: sessionId,
              customerId: Value(customerId),
              customerName: Value(customerName),
              paymentMethod: paymentMethod,
              totalCents: totalCents,
              createdAt: now,
            ),
          );

      // 3. Renglones (con foto de nombre, precio y costo).
      final itemRows = <SaleItemsTableData>[];
      for (final line in lines) {
        itemRows.add(
          await _db.into(_db.saleItemsTable).insertReturning(
                SaleItemsTableCompanion.insert(
                  saleId: sale.id,
                  productId: Value(line.productId),
                  productName: line.productName,
                  quantity: line.quantity,
                  unitPriceCents: line.unitPriceCents,
                  unitCostCents: line.unitCostCents,
                  subtotalCents: line.subtotalCents,
                ),
              ),
        );
      }

      // 4. Descontar existencias de forma atómica (en SQL, no leer-y-escribir).
      for (final entry in requested.entries) {
        await _db.customUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          variables: [Variable<double>(entry.value), Variable<String>(entry.key)],
          updates: {_db.productsTable},
          updateKind: UpdateKind.update,
        );
      }

      // 5. Solo el efectivo mueve la caja; tarjeta y fiado no.
      if (paymentMethod == PaymentMethod.cash && totalCents > 0) {
        await _db.into(_db.cashMovementsTable).insert(
              CashMovementsTableCompanion.insert(
                sessionId: sessionId,
                type: CashMovementType.sale,
                amountCents: totalCents,
                note: 'Venta V-${sale.number.toString().padLeft(6, '0')}',
                createdAt: now,
                saleId: Value(sale.id),
              ),
            );
      }

      return _toModel(sale, itemRows);
    });
  }

  Sale _toModel(SalesTableData sale, List<SaleItemsTableData> items) {
    return Sale(
      id: sale.id,
      number: sale.number,
      date: sale.createdAt,
      totalCents: sale.totalCents,
      paymentMethod: sale.paymentMethod,
      customerId: sale.customerId,
      customerName: sale.customerName,
      items: [
        for (final item in items)
          SaleItem(
            productId: item.productId,
            productName: item.productName,
            quantity: item.quantity,
            unitPriceCents: item.unitPriceCents,
            unitCostCents: item.unitCostCents,
            subtotalCents: item.subtotalCents,
          ),
      ],
    );
  }
}
