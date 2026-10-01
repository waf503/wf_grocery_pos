class Category {
  Category({
    required this.id,
    required this.name,
    this.description,
    this.parentId,
    this.icon,
  });

  final String id;
  final String name;
  final String? description;
  final String? parentId;

  /// El id del ícono elegido (ver `category_icon_options.dart`), no el
  /// ícono en sí.
  final String? icon;

  bool get isRoot => parentId == null;
}
