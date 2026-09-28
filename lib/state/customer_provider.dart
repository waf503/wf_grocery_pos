import 'package:flutter/foundation.dart';

import '../data/mock_data.dart';
import '../models/customer.dart';

class CustomerProvider extends ChangeNotifier {
  CustomerProvider() : _customers = buildMockCustomers();

  final List<Customer> _customers;

  List<Customer> get customers => List.unmodifiable(_customers);

  List<Customer> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return customers;
    return _customers
        .where((c) => c.name.toLowerCase().contains(normalized))
        .toList();
  }

  void addCustomer(Customer customer) {
    _customers.add(customer);
    notifyListeners();
  }

  void updateCustomer(Customer updated) {
    final index = _customers.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      _customers[index] = updated;
      notifyListeners();
    }
  }

  void deleteCustomer(String id) {
    _customers.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  void addToBalance(String customerId, double amount) {
    for (final customer in _customers) {
      if (customer.id == customerId) {
        customer.balance += amount;
        notifyListeners();
        return;
      }
    }
  }

  String nextId() => 'c${DateTime.now().millisecondsSinceEpoch}';
}
