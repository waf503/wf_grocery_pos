class Customer {
  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.balance = 0,
  });

  final String id;
  String name;
  String? phone;
  String? email;

  /// Saldo pendiente (fiado). Positivo = el cliente debe dinero a la tienda.
  double balance;
}
