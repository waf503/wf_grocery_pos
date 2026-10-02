import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../core/theme/category_colors.dart';
import '../features/categories/data/category_repository.dart';
import '../models/category.dart';

/// Un nodo del árbol de categorías, para dibujar la pantalla CRUD anidada.
class CategoryNode {
  CategoryNode(this.category, this.children);

  final Category category;
  final List<CategoryNode> children;
}

class CategoryProvider extends ChangeNotifier {
  CategoryProvider(this._repository) {
    _subscription = _repository.watchAll().listen((rows) {
      _categories = rows;
      notifyListeners();
    });
  }

  final CategoryRepository _repository;
  late final StreamSubscription<List<Category>> _subscription;

  List<Category> _categories = [];

  List<Category> get categories => List.unmodifiable(_categories);

  /// Lista plana pero en orden jerárquico, con sangría (`— `) por nivel —
  /// lo que consumen los dropdowns de Inventario/POS para mostrar la
  /// jerarquía sin necesitar un widget de árbol ahí.
  List<Category> get flatIndented {
    final result = <Category>[];
    void walk(String? parentId, int depth) {
      for (final c in _categories.where((c) => c.parentId == parentId)) {
        result.add(c);
        walk(c.id, depth + 1);
      }
    }

    walk(null, 0);
    return result;
  }

  int depthOf(Category category) {
    var depth = 0;
    String? parentId = category.parentId;
    while (parentId != null) {
      final parent = byId(parentId);
      if (parent == null) break;
      depth++;
      parentId = parent.parentId;
    }
    return depth;
  }

  Category? byId(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Color efectivo de una categoría: el propio, o el del ancestro más
  /// cercano que tenga uno (una subcategoría hereda el de su padre).
  int colorValueFor(String categoryId) {
    String? id = categoryId;
    while (id != null) {
      final category = byId(id);
      if (category == null) break;
      if (category.color != null) return category.color!;
      id = category.parentId;
    }
    return defaultCategoryColor;
  }

  /// Siguiente color de la paleta que aún no usa ninguna categoría raíz
  /// (o el primero, si ya se usaron todos) — se sugiere al crear una nueva.
  int nextSuggestedColor() {
    final used = _categories.map((c) => c.color).whereType<int>().toSet();
    for (final candidate in categoryColorPalette) {
      if (!used.contains(candidate)) return candidate;
    }
    return categoryColorPalette[_categories.length % categoryColorPalette.length];
  }

  List<CategoryNode> get tree {
    List<CategoryNode> buildChildren(String? parentId) {
      return _categories
          .where((c) => c.parentId == parentId)
          .map((c) => CategoryNode(c, buildChildren(c.id)))
          .toList();
    }

    return buildChildren(null);
  }

  /// Todos los ids de las categorías descendientes de [id] (hijas, nietas,
  /// etc.) — se usa para no dejar elegir un descendiente como "padre" al
  /// editar, lo que crearía un ciclo infinito en el árbol.
  Set<String> descendantsOf(String id) {
    final result = <String>{};
    void collect(String parentId) {
      for (final c in _categories.where((c) => c.parentId == parentId)) {
        result.add(c.id);
        collect(c.id);
      }
    }

    collect(id);
    return result;
  }

  Future<void> addCategory({
    required String name,
    String? description,
    String? parentId,
    String? icon,
    int? color,
  }) {
    return _repository.add(
      name: name,
      description: description,
      parentId: parentId,
      icon: icon,
      color: color,
    );
  }

  Future<void> updateCategory(Category category) {
    return _repository.update(category);
  }

  Future<DeleteCategoryResult> deleteCategory(String id) {
    return _repository.delete(id);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
