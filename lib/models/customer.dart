import '../core/money.dart';

/// Cómo cambia el saldo del cliente: un cargo lo aumenta (venta a crédito);
/// un abono o la reversa de un cargo (venta anulada) lo disminuyen.
enum CustomerMovementType { charge, payment, reversal }

extension CustomerMovementTypeLabel on CustomerMovementType {
  String get label {
    switch (this) {
      case CustomerMovementType.charge:
        return 'Cargo';
      case CustomerMovementType.payment:
        return 'Abono';
      case CustomerMovementType.reversal:
        return 'Anulación';
    }
  }

  /// +1 si aumenta lo que el cliente debe, -1 si lo disminuye.
  int get sign => this == CustomerMovementType.charge ? 1 : -1;
}

class CustomerMovement {
  CustomerMovement({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.note,
    required this.date,
    this.saleId,
  });

  final String id;
  final CustomerMovementType type;
  final int amountCents;
  final String note;
  final DateTime date;
  final String? saleId;

  double get amount => fromCents(amountCents);
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.balanceCents = 0,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;

  /// Saldo pendiente (fiado) en centavos. Positivo = el cliente debe dinero.
  final int balanceCents;

  double get balance => fromCents(balanceCents);
}
