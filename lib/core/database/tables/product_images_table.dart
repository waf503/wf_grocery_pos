import 'package:drift/drift.dart';

import 'products_table.dart';

/// Tabla `product_images`: la miniatura de cada producto, guardada dentro de
/// la propia base de datos (no como archivos sueltos) para que un respaldo de
/// `wf_grocery_pos.sqlite` incluya también las imágenes y funcionen sin
/// internet. Va aparte de `products` para que la lista de productos no cargue
/// los bytes de todas las imágenes: solo se leen cuando hay que dibujarlas.
///
/// Al borrar el producto se borra su imagen (`onDelete: cascade`).
class ProductImagesTable extends Table {
  @override
  String get tableName => 'product_images';

  TextColumn get productId =>
      text().references(ProductsTable, #id, onDelete: KeyAction.cascade)();
  BlobColumn get bytes => blob()();

  @override
  Set<Column> get primaryKey => {productId};
}
