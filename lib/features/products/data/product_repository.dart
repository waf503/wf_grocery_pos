import 'dart:typed_data';

import '../../../core/database/app_database.dart';
import '../../../models/product.dart';
import '../../../models/product_combo.dart';

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

  /// Crea el producto y, si se da [image], su miniatura (todo junto).
  /// Devuelve el id del producto creado.
  Future<String> add(ProductsTableCompanion product, {Uint8List? image});

  /// Actualiza el producto. Con [image] reemplaza su miniatura; con
  /// [removeImage] se la quita. Sin ninguno, la imagen no cambia.
  Future<void> update(ProductsTableCompanion product, {Uint8List? image, bool removeImage = false});

  /// La miniatura del producto, o `null` si no tiene.
  Future<Uint8List?> getImage(String productId);

  /// SUMA [units] a las existencias del producto (en su unidad), de forma
  /// atómica en la base de datos; no reemplaza lo que había. Es el producto
  /// base: las presentaciones no tienen existencias propias.
  Future<void> addStock(String productId, double units);

  /// Fija el costo a partir de lo que cuesta UNA [presentationId] (una unidad,
  /// una cajetilla, un paquete...): calcula el costo exacto por unidad
  /// (costo ÷ unidades que contiene) y actualiza el del producto base y el de
  /// todas sus presentaciones, para que el usuario no tenga que dividir.
  Future<void> setCostFromPresentation(String presentationId, int costCents);

  /// Reemplaza los combos (promociones por cantidad) del producto.
  Future<void> setCombos(String productId, List<ProductCombo> combos);

  /// Deja las presentaciones del producto base [baseId] exactamente como
  /// [drafts]: las que traen id se actualizan, las nuevas se crean y las que
  /// ya no vienen se borran. Siguen la categoría y la unidad del base.
  ///
  /// Si cambia la unidad más pequeña del grupo (se agregó una presentación más
  /// chica que el base), [baseUnitsPerPack] es lo que ahora vale el base en
  /// esa unidad y [stockScale] lo que se multiplican las existencias ya
  /// guardadas (y el stock mínimo y el registro de ventas anteriores).
  Future<void> savePresentations(
    String baseId,
    List<PresentationDraft> drafts, {
    int? baseUnitsPerPack,
    double stockScale = 1,
  });

  Future<void> delete(String id);
}
