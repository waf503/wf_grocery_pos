import '../../../models/category.dart';

/// Resultado de intentar borrar una categoría — en vez de solo lanzar una
/// excepción genérica, decimos EXACTAMENTE por qué no se pudo, para que la
/// UI muestre un mensaje útil en vez de un error críptico.
enum DeleteCategoryError { hasChildren, hasProducts }

class DeleteCategoryResult {
  const DeleteCategoryResult.success() : error = null;
  const DeleteCategoryResult.failure(this.error);

  final DeleteCategoryError? error;
  bool get isSuccess => error == null;
}

abstract class CategoryRepository {
  Stream<List<Category>> watchAll();

  Future<Category> add({
    required String name,
    String? description,
    String? parentId,
    String? icon,
  });

  Future<void> update(Category category);

  Future<DeleteCategoryResult> delete(String id);
}
