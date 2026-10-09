import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/customers/data/customer_repository.dart';
import '../models/customer.dart';

class CustomerProvider extends ChangeNotifier {
  CustomerProvider(this._repository) {
    _subscription = _repository.watchAll().listen((rows) {
      _customers = rows;
      notifyListeners();
    });
  }

  final CustomerRepository _repository;
  late final StreamSubscription<List<Customer>> _subscription;

  List<Customer> _customers = [];

  List<Customer> get customers => List.unmodifiable(_customers);

  /// Total que los clientes deben a la tienda (fiado pendiente), en centavos.
  int get totalReceivableCents => _customers.fold(0, (sum, c) => sum + c.balanceCents);

  Customer? byId(String? id) {
    if (id == null) return null;
    for (final c in _customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Customer> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return customers;
    return _customers.where((c) => c.name.toLowerCase().contains(normalized)).toList();
  }

  Future<void> addCustomer({required String name, String? phone, String? email}) =>
      _repository.add(name: name, phone: phone, email: email);

  Future<void> updateCustomer(Customer customer) => _repository.update(customer);

  Future<DeleteCustomerResult> deleteCustomer(String id) => _repository.delete(id);

  Stream<List<CustomerMovement>> watchMovements(String customerId) =>
      _repository.watchMovements(customerId);

  Future<void> registerPayment({
    required String customerId,
    required int amountCents,
    String? cashSessionId,
    String? note,
  }) {
    return _repository.registerPayment(
      customerId: customerId,
      amountCents: amountCents,
      cashSessionId: cashSessionId,
      note: note,
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
