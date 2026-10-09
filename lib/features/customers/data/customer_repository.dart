import '../../../models/customer.dart';

/// Un abono mayor al saldo pendiente del cliente.
class PaymentExceedsBalanceException implements Exception {
  PaymentExceedsBalanceException(this.balanceCents);

  final int balanceCents;

  @override
  String toString() => 'El abono es mayor que el saldo pendiente.';
}

/// Resultado de intentar borrar un cliente.
enum DeleteCustomerResult { deleted, hasBalance }

abstract class CustomerRepository {
  /// Todos los clientes con su saldo, ordenados por nombre.
  Stream<List<Customer>> watchAll();

  Future<void> add({required String name, String? phone, String? email});

  Future<void> update(Customer customer);

  /// No permite borrar a un cliente que todavía debe dinero.
  Future<DeleteCustomerResult> delete(String id);

  /// Estado de cuenta: movimientos del más reciente al más antiguo.
  Stream<List<CustomerMovement>> watchMovements(String customerId);

  /// Registra un abono al fiado. Si se indica [cashSessionId], el abono
  /// entra como ingreso de efectivo a esa caja abierta. Lanza
  /// [PaymentExceedsBalanceException] si excede el saldo.
  Future<void> registerPayment({
    required String customerId,
    required int amountCents,
    String? cashSessionId,
    String? note,
  });
}
