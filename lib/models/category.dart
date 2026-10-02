class Category {
  Category({
    required this.id,
    required this.name,
    this.description,
    this.parentId,
    this.icon,
    this.color,
  });

  final String id;
  final String name;
  final String? description;
  final String? parentId;

  /// El id del ícono elegido (ver `category_icon_options.dart`), no el
  /// ícono en sí.
  final String? icon;

  /// Color propio (ARGB); nulo = hereda el del padre.
  final int? color;

  bool get isRoot => parentId == null;
}
