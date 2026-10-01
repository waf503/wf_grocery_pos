import '../models/customer.dart';

List<Customer> buildMockCustomers() => [
      Customer(id: 'c1', name: 'Mostrador / Público general'),
      Customer(
        id: 'c2',
        name: 'Doña Carmen Ruiz',
        phone: '55 1234 5678',
        balance: 85.0,
      ),
      Customer(
        id: 'c3',
        name: 'Taquería El Buen Sabor',
        phone: '55 8765 4321',
        email: 'contacto@elbuensabor.mx',
        balance: 0,
      ),
      Customer(
        id: 'c4',
        name: 'Don Rafael Torres',
        phone: '55 2222 3333',
        balance: 0,
      ),
    ];
