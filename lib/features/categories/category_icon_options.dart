import 'package:flutter/material.dart';

/// Un ícono elegible en el selector, con palabras clave para la búsqueda y
/// para la auto-sugerencia por nombre de categoría.
class CategoryIconOption {
  const CategoryIconOption(this.id, this.icon, this.keywords);

  /// Lo que se GUARDA en la base de datos (un `IconData` no es serializable).
  final String id;
  final IconData icon;
  final List<String> keywords;
}

/// Catálogo curado — no el universo completo de Material Symbols, para que
/// elegir un ícono sea rápido y no abrumador.
const List<CategoryIconOption> categoryIconOptions = [
  CategoryIconOption('local_grocery_store', Icons.local_grocery_store, ['abarrotes', 'grocery', 'general']),
  CategoryIconOption('storefront', Icons.storefront, ['tienda', 'store']),
  CategoryIconOption('shopping_basket', Icons.shopping_basket, ['canasta', 'basket']),
  CategoryIconOption('local_drink', Icons.local_drink, ['bebida', 'bebidas', 'drink', 'jugo', 'agua']),
  CategoryIconOption('local_bar', Icons.local_bar, ['gaseosa', 'gaseosas', 'refresco', 'soda', 'bar']),
  CategoryIconOption('liquor', Icons.liquor, ['licor', 'cerveza', 'alcohol', 'vino']),
  CategoryIconOption('coffee', Icons.coffee, ['cafe', 'café']),
  CategoryIconOption('icecream', Icons.icecream, ['helado', 'lacteo', 'lacteos', 'leche', 'yogurt']),
  CategoryIconOption('egg', Icons.egg, ['huevo', 'huevos']),
  CategoryIconOption('bakery_dining', Icons.bakery_dining, ['pan', 'panaderia', 'panadería', 'bakery']),
  CategoryIconOption('cake', Icons.cake, ['pastel', 'reposteria', 'repostería']),
  CategoryIconOption('lunch_dining', Icons.lunch_dining, ['comida', 'almuerzo']),
  CategoryIconOption('local_pizza', Icons.local_pizza, ['pizza', 'botana', 'botanas', 'snack', 'frituras']),
  CategoryIconOption('cookie', Icons.cookie, ['galleta', 'galletas']),
  CategoryIconOption('eco', Icons.eco, ['verdura', 'verduras', 'fruta', 'frutas', 'organico', 'vegetal']),
  CategoryIconOption('scale', Icons.scale, ['granel', 'peso', 'balanza']),
  CategoryIconOption('set_meal', Icons.set_meal, ['pescado', 'mariscos', 'carne']),
  CategoryIconOption('kebab_dining', Icons.kebab_dining, ['carne', 'carniceria', 'carnicería']),
  CategoryIconOption('cleaning_services', Icons.cleaning_services, ['limpieza', 'cleaning']),
  CategoryIconOption('soap', Icons.soap, ['jabon', 'jabón', 'higiene']),
  CategoryIconOption('dry_cleaning', Icons.dry_cleaning, ['ropa', 'lavanderia', 'lavandería']),
  CategoryIconOption('pets', Icons.pets, ['mascota', 'mascotas', 'perro', 'gato']),
  CategoryIconOption('hardware', Icons.hardware, ['ferreteria', 'ferretería', 'herramienta', 'herramientas', 'tornillo', 'tornillos', 'clavo', 'clavos']),
  CategoryIconOption('construction', Icons.construction, ['construccion', 'construcción', 'pintura', 'electrico', 'eléctrico']),
  CategoryIconOption('medication', Icons.medication, ['farmacia', 'medicina', 'salud']),
  CategoryIconOption('kitchen', Icons.kitchen, ['cocina', 'refrigerador', 'congelado', 'congelados']),
  CategoryIconOption('ac_unit', Icons.ac_unit, ['congelado', 'congelados', 'frio', 'frío', 'helado']),
  CategoryIconOption('inventory_2', Icons.inventory_2, ['empaque', 'paquete', 'caja']),
  CategoryIconOption('category', Icons.category, ['general', 'otro', 'otros']),
  CategoryIconOption('label', Icons.label, ['etiqueta', 'generico', 'genérico']),
];

const CategoryIconOption defaultCategoryIcon = CategoryIconOption('label_outline', Icons.label_outline, []);

IconData iconDataFor(String? iconId) {
  if (iconId == null) return defaultCategoryIcon.icon;
  for (final option in categoryIconOptions) {
    if (option.id == iconId) return option.icon;
  }
  return defaultCategoryIcon.icon;
}

/// Auto-sugerencia: busca la primera opción cuya palabra clave aparezca
/// dentro del nombre escrito (o viceversa), para preseleccionar un ícono
/// razonable sin que el usuario tenga que abrir el selector.
String? suggestIconFor(String categoryName) {
  final normalized = categoryName.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final option in categoryIconOptions) {
    for (final keyword in option.keywords) {
      if (normalized.contains(keyword) || keyword.contains(normalized)) {
        return option.id;
      }
    }
  }
  return null;
}
