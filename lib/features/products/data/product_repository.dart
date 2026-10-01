import '../../../core/database/app_database.dart';
import '../../../models/product.dart';
import '../../../models/product_family.dart';

/// Contrato de acceso a datos para productos y sus familias.
///
/// El resto de la app (Provider, pantallas) programa contra ESTA interfaz,
/// nunca contra Drift directamente. Cuando conectemos el backend de
/// Laravel, agregaremos una `ApiProductRepository` que cumpla el mismo
/// contrato — la UI no se enterará del cambio.
abstract class ProductRepository {
  /// Todas las variantes, ya combinadas con el nombre de su familia.
  Stream<List<Product>> watchAllVariants();

  Stream<List<ProductFamily>> watchFamilies();

  Future<Product?> getVariantById(String id);

  /// Busca una familia por nombre (sin importar mayúsculas/minúsculas); si
  /// no existe, la crea. Es lo que permite que escribir "Coca-Cola" dos
  /// veces reutilice la misma familia en vez de duplicarla.
  Future<ProductFamily> findOrCreateFamily({
    required String name,
    required String categoryId,
    String? brand,
  });

  Future<void> addVariant(String familyId, ProductVariantsTableCompanion variant);

  Future<void> updateVariant(ProductVariantsTableCompanion variant);

  Future<void> deleteVariant(String variantId);

  Future<void> decreaseStock(String variantId, double quantity);
}
