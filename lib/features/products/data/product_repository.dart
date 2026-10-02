import '../../../core/database/app_database.dart';
import '../../../models/product.dart';

/// Contrato de acceso a datos para productos.
///
/// El resto de la app (Provider, pantallas) programa contra ESTA interfaz,
/// nunca contra Drift directamente. Cuando conectemos el backend de
/// Laravel, agregaremos una `ApiProductRepository` que cumpla el mismo
/// contrato — la UI no se enterará del cambio.
abstract class ProductRepository {
  /// Todos los productos, ya con el nombre de su categoría resuelto.
  Stream<List<Product>> watchAll();

  Future<Product?> getById(String id);

  Future<void> add(ProductsTableCompanion product);

  Future<void> update(ProductsTableCompanion product);

  Future<void> delete(String id);

  Future<void> decreaseStock(String id, double quantity);
}
