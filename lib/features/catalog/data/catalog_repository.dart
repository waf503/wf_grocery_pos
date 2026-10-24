import '../catalog_item.dart';

/// Acceso a la tabla local de catálogo de consulta (`catalog_items`).
abstract class CatalogRepository {
  /// Lo que ya se sabe de ese código de barras, sin consultar internet.
  Future<CatalogItem?> findByBarcode(String barcode);

  /// Guarda (o reemplaza) la información de un código de barras.
  Future<void> save(CatalogItem item);
}
