import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../models/cash_session.dart';
import '../../../models/customer.dart';
import '../../sales/data/sale_repository.dart';
import 'customer_repository.dart';

class DriftCustomerRepository implements CustomerRepository {
  DriftCustomerRepository(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<List<Customer>> watchAll() {
    // El saldo se calcula con SQL sobre los movimientos: los cargos suman;
    // los abonos y las anulaciones restan.
    final query = _db.customSelect(
      '''
      SELECT c.id, c.name, c.phone, c.email,
        COALESCE(SUM(CASE m.type WHEN 'charge' THEN m.amount_cents
                                 ELSE -m.amount_cents END), 0) AS balance_cents
      FROM customers c
      LEFT JOIN customer_account_movements m ON m.customer_id = c.id
      GROUP BY c.id
      ORDER BY c.name COLLATE NOCASE
      ''',
      readsFrom: {_db.customersTable, _db.customerMovementsTable},
    );
    return query.watch().map((rows) => [
          for (final row in rows)
            Customer(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
              phone: row.readNullable<String>('phone'),
              email: row.readNullable<String>('email'),
              balanceCents: row.read<int>('balance_cents'),
            ),
        ]);
  }

  @override
  Future<void> add({required String name, String? phone, String? email}) async {
    await _db.into(_db.customersTable).insert(
          CustomersTableCompanion.insert(
            name: name,
            phone: Value(phone),
            email: Value(email),
          ),
        );
  }

  @override
  Future<void> update(Customer customer) {
    return (_db.update(_db.customersTable)..where((row) => row.id.equals(customer.id))).write(
      CustomersTableCompanion(
        name: Value(customer.name),
        phone: Value(customer.phone),
        email: Value(customer.email),
      ),
    );
  }

  @override
  Future<DeleteCustomerResult> delete(String id) {
    return _db.transaction(() async {
      if (await _balanceCents(id) > 0) return DeleteCustomerResult.hasBalance;
      // Un cliente sin deuda se borra junto con su estado de cuenta (ya
      // saldado); las ventas conservan su foto del nombre.
      await (_db.delete(_db.customerMovementsTable)..where((row) => row.customerId.equals(id))).go();
      await (_db.delete(_db.customersTable)..where((row) => row.id.equals(id))).go();
      return DeleteCustomerResult.deleted;
    });
  }

  @override
  Stream<List<CustomerMovement>> watchMovements(String customerId) {
    return (_db.select(_db.customerMovementsTable)
          ..where((row) => row.customerId.equals(customerId))
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
        .watch()
        .map((rows) => [
              for (final row in rows)
                CustomerMovement(
                  id: row.id,
                  type: row.type,
                  amountCents: row.amountCents,
                  note: row.note,
                  date: row.createdAt,
                  saleId: row.saleId,
                ),
            ]);
  }

  @override
  Future<void> registerPayment({
    required String customerId,
    required int amountCents,
    String? cashSessionId,
    String? note,
  }) {
    if (amountCents <= 0) throw ArgumentError('El abono debe ser mayor a cero.');

    return _db.transaction(() async {
      final customer = await (_db.select(_db.customersTable)
            ..where((row) => row.id.equals(customerId)))
          .getSingle();
      final balance = await _balanceCents(customerId);
      if (amountCents > balance) throw PaymentExceedsBalanceException(balance);

      final now = _clock();
      await _db.into(_db.customerMovementsTable).insert(
            CustomerMovementsTableCompanion.insert(
              customerId: customerId,
              type: CustomerMovementType.payment,
              amountCents: amountCents,
              note: note ?? 'Abono',
              createdAt: now,
            ),
          );

      if (cashSessionId != null) {
        final session = await (_db.select(_db.cashSessionsTable)
              ..where((row) => row.id.equals(cashSessionId)))
            .getSingleOrNull();
        if (session == null || session.closedAt != null) throw CashSessionClosedException();
        await _db.into(_db.cashMovementsTable).insert(
              CashMovementsTableCompanion.insert(
                sessionId: cashSessionId,
                type: CashMovementType.customerPayment,
                amountCents: amountCents,
                note: 'Abono de ${customer.name}',
                createdAt: now,
              ),
            );
      }
    });
  }

  Future<int> _balanceCents(String customerId) async {
    final row = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(CASE type WHEN 'charge' THEN amount_cents
                                    ELSE -amount_cents END), 0) AS balance_cents
      FROM customer_account_movements WHERE customer_id = ?
      ''',
      variables: [Variable<String>(customerId)],
      readsFrom: {_db.customerMovementsTable},
    ).getSingle();
    return row.read<int>('balance_cents');
  }
}
