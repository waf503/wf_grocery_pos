/// Rol de un usuario del sistema.
enum UserRole {
  /// Dueño o encargado: ve y cambia todo (inventario, reportes, usuarios...).
  admin,

  /// Cajero: cobra, maneja su caja y atiende clientes. No ve costos ni reportes
  /// ni toca el inventario; para anular una venta necesita el PIN de un admin.
  cashier,
}

extension UserRoleLabel on UserRole {
  String get label => this == UserRole.admin ? 'Administrador' : 'Cajero';
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    this.active = true,
  });

  final String id;
  final String name;
  final UserRole role;
  final bool active;

  bool get isAdmin => role == UserRole.admin;

  AppUser copyWith({String? name, UserRole? role, bool? active}) => AppUser(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        active: active ?? this.active,
      );
}

/// Un PIN válido: de 4 a 6 dígitos.
bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);
