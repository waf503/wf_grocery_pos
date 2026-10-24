import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../models/cash_session.dart';
import '../../../models/customer.dart';
import '../../../models/sale.dart';
import 'sale_repository.dart';

class DriftSaleRepository implements SaleRepository {
  DriftSaleRepository(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<List<Sale>> watchBetween(DateTime from, {DateTime? to}) {
    final sales = _db.salesTable;
    return _watchSales(
      sales.createdAt.isBiggerOrEqualValue(from) &
          (to == null ? const Constant(true) : sales.createdAt.isSmallerThanValue(to)),
    );
  }

  @override
  Stream<List<Sale>> watchBySession(String sessionId) {
    return _watchSales(_db.salesTable.sessionId.equals(sessionId));
  }

  /// Ventas con sus renglones que cumplen [filter], de la más reciente a la
  /// más antigua.
  Stream<List<Sale>> _watchSales(Expression<bool> filter) {
    final sales = _db.salesTable;
    final items = _db.saleItemsTable;
    final query = _db.select(sales).join([
      leftOuterJoin(items, items.saleId.equalsExp(sales.id)),
    ])
      ..where(filter)
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
    int? tenderedCents,
  }) {
    if (lines.isEmpty) throw ArgumentError('Una venta necesita al menos un renglón.');
    if (tenderedCents != null && paymentMethod != PaymentMethod.cash) {
      throw ArgumentError('Solo las ventas en efectivo tienen monto recibido.');
    }

    return _db.transaction(() async {
      final session = await (_db.select(_db.cashSessionsTable)
            ..where((row) => row.id.equals(sessionId)))
          .getSingleOrNull();
      if (session == null || session.closedAt != null) throw CashSessionClosedException();

      // El fiado necesita un cliente real al que cargarle la deuda.
      if (paymentMethod == PaymentMethod.credit) {
        final customer = customerId == null
            ? null
            : await (_db.select(_db.customersTable)..where((row) => row.id.equals(customerId)))
                .getSingleOrNull();
        if (customer == null) throw CreditRequiresCustomerException();
        customerName = customer.name;
      }

      // 1. Validar existencias. Cada renglón consume del producto BASE: una
      // cajetilla de 20 descuenta 20 unidades del mismo "pool" que la unidad
      // suelta y que el paquete. Se suma todo lo que se pide de cada pool (un
      // producto puede venir en varios renglones o presentaciones) antes de
      // comparar. Los renglones genéricos (sin producto) no tienen existencias.
      final consumption = <_Consumption?>[];
      final requestedByPool = <String, double>{};
      for (final line in lines) {
        final id = line.productId;
        if (id == null) {
          consumption.add(null);
          continue;
        }
        final product = await (_db.select(_db.productsTable)..where((row) => row.id.equals(id)))
            .getSingleOrNull();
        if (product == null) throw ProductNotFoundException(line.productName);

        final poolId = product.baseProductId ?? product.id;
        final factor = product.unitsPerPack <= 0 ? 1.0 : product.unitsPerPack;
        final units = line.quantity * factor;
        consumption.add(_Consumption(poolId, units, factor));
        requestedByPool[poolId] = (requestedByPool[poolId] ?? 0) + units;
      }

      final pools = <String, ProductsTableData>{};
      for (final poolId in requestedByPool.keys) {
        final pool = await (_db.select(_db.productsTable)..where((row) => row.id.equals(poolId)))
            .getSingleOrNull();
        if (pool == null) {
          final name = lines.firstWhere((l) => l.productId != null).productName;
          throw ProductNotFoundException(name);
        }
        pools[poolId] = pool;
      }
      for (var i = 0; i < lines.length; i++) {
        final use = consumption[i];
        if (use == null) continue;
        final pool = pools[use.poolId]!;
        if (pool.stock + 1e-9 < requestedByPool[use.poolId]!) {
          // Lo disponible se expresa en la presentación que se quería vender.
          final available = use.factor == 1 ? pool.stock : (pool.stock / use.factor).floorToDouble();
          throw InsufficientStockException(lines[i].productName, available: available);
        }
      }

      // 2. Folio consecutivo y encabezado.
      final maxNumber = _db.salesTable.number.max();
      final lastNumber = await (_db.selectOnly(_db.salesTable)..addColumns([maxNumber]))
          .map((row) => row.read(maxNumber))
          .getSingle();
      final totalCents = lines.fold<int>(0, (sum, line) => sum + line.subtotalCents);
      final now = _clock();

      // Efectivo: lo recibido (por defecto el total exacto) y el vuelto.
      int? tendered;
      int? change;
      if (paymentMethod == PaymentMethod.cash) {
        tendered = tenderedCents ?? totalCents;
        if (tendered < totalCents) throw InsufficientTenderException(totalCents - tendered);
        change = tendered - totalCents;
      }

      final sale = await _db.into(_db.salesTable).insertReturning(
            SalesTableCompanion.insert(
              number: (lastNumber ?? 0) + 1,
              sessionId: sessionId,
              customerId: Value(customerId),
              customerName: Value(customerName),
              paymentMethod: paymentMethod,
              totalCents: totalCents,
              createdAt: now,
              tenderedCents: Value(tendered),
              changeCents: Value(change),
            ),
          );

      // 3. Renglones (con foto de nombre, precio y costo).
      final itemRows = <SaleItemsTableData>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final use = consumption[i];
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
                  stockProductId: Value(use?.poolId),
                  stockQuantity: Value(use?.units),
                ),
              ),
        );
      }

      // 4. Descontar existencias de forma atómica (en SQL, no leer-y-escribir).
      for (final entry in requestedByPool.entries) {
        await _db.customUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          variables: [Variable<double>(entry.value), Variable<String>(entry.key)],
          updates: {_db.productsTable},
          updateKind: UpdateKind.update,
        );
      }

      // 5. Solo el efectivo mueve la caja; tarjeta y fiado no. Entra lo que
      // entregó el cliente y el vuelto sale como un movimiento propio (neto =
      // total de la venta).
      if (paymentMethod == PaymentMethod.cash && totalCents > 0) {
        final folio = 'V-${sale.number.toString().padLeft(6, '0')}';
        await _db.into(_db.cashMovementsTable).insert(
              CashMovementsTableCompanion.insert(
                sessionId: sessionId,
                type: CashMovementType.sale,
                amountCents: tendered!,
                note: 'Venta $folio',
                createdAt: now,
                saleId: Value(sale.id),
              ),
            );
        if (change! > 0) {
          await _db.into(_db.cashMovementsTable).insert(
                CashMovementsTableCompanion.insert(
                  sessionId: sessionId,
                  type: CashMovementType.change,
                  amountCents: change,
                  note: 'Vuelto $folio',
                  createdAt: now,
                  saleId: Value(sale.id),
                ),
              );
        }
      }

      // 6. El fiado carga el saldo del cliente en su estado de cuenta.
      if (paymentMethod == PaymentMethod.credit && totalCents > 0) {
        await _db.into(_db.customerMovementsTable).insert(
              CustomerMovementsTableCompanion.insert(
                customerId: customerId!,
                type: CustomerMovementType.charge,
                amountCents: totalCents,
                saleId: Value(sale.id),
                note: 'Venta V-${sale.number.toString().padLeft(6, '0')}',
                createdAt: now,
              ),
            );
      }

      return _toModel(sale, itemRows);
    });
  }

  @override
  Future<void> voidSale({
    required String saleId,
    required String reason,
    String? cashSessionId,
  }) {
    return _db.transaction(() async {
      final sale = await (_db.select(_db.salesTable)..where((row) => row.id.equals(saleId)))
          .getSingleOrNull();
      if (sale == null) throw SaleNotFoundException();
      if (sale.status == SaleStatus.voided) throw SaleAlreadyVoidedException();

      final now = _clock();
      final folio = 'V-${sale.number.toString().padLeft(6, '0')}';

      // Efectivo: se saca de la caja ABIERTA (la de la venta puede estar
      // cerrada ya); validar antes de tocar nada.
      if (sale.paymentMethod == PaymentMethod.cash && sale.totalCents > 0) {
        final session = cashSessionId == null
            ? null
            : await (_db.select(_db.cashSessionsTable)..where((row) => row.id.equals(cashSessionId)))
                .getSingleOrNull();
        if (session == null || session.closedAt != null) throw CashSessionClosedException();
        await _db.into(_db.cashMovementsTable).insert(
              CashMovementsTableCompanion.insert(
                sessionId: cashSessionId!,
                type: CashMovementType.saleVoid,
                amountCents: sale.totalCents,
                note: 'Anulación $folio',
                createdAt: now,
              ),
            );
      }

      // Devolver existencias. Si el producto ya no existe, el UPDATE no
      // afecta ninguna fila (no es error).
      final items = await (_db.select(_db.saleItemsTable)..where((row) => row.saleId.equals(saleId))).get();
      for (final item in items) {
        // Ventas nuevas: el producto base y las unidades que se descontaron.
        // Ventas anteriores a las presentaciones: el producto y su cantidad.
        final targetId = item.stockProductId ?? item.productId;
        if (targetId == null) continue;
        await _db.customUpdate(
          'UPDATE products SET stock = stock + ? WHERE id = ?',
          variables: [Variable<double>(item.stockQuantity ?? item.quantity), Variable<String>(targetId)],
          updates: {_db.productsTable},
          updateKind: UpdateKind.update,
        );
      }

      // Fiado: se revierte el cargo, si el cliente todavía existe.
      if (sale.paymentMethod == PaymentMethod.credit && sale.customerId != null && sale.totalCents > 0) {
        final customer = await (_db.select(_db.customersTable)
              ..where((row) => row.id.equals(sale.customerId!)))
            .getSingleOrNull();
        if (customer != null) {
          await _db.into(_db.customerMovementsTable).insert(
                CustomerMovementsTableCompanion.insert(
                  customerId: customer.id,
                  type: CustomerMovementType.reversal,
                  amountCents: sale.totalCents,
                  saleId: Value(saleId),
                  note: 'Anulación $folio',
                  createdAt: now,
                ),
              );
        }
      }

      await (_db.update(_db.salesTable)..where((row) => row.id.equals(saleId))).write(
        SalesTableCompanion(
          status: const Value(SaleStatus.voided),
          voidedAt: Value(now),
          voidReason: Value(reason),
        ),
      );
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
      status: sale.status,
      voidedAt: sale.voidedAt,
      voidReason: sale.voidReason,
      tenderedCents: sale.tenderedCents,
      changeCents: sale.changeCents,
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

/// Qué existencias consume un renglón de venta: el producto base (pool), las
/// unidades base que descuenta y cuántas unidades base vale una del renglón.
class _Consumption {
  _Consumption(this.poolId, this.units, this.factor);

  final String poolId;
  final double units;
  final double factor;
}
