import '../../models/app_user.dart';

/// Pantallas que solo ve el administrador: dinero y costos (inicio, reportes),
/// el catálogo (inventario, categorías, unidades), los usuarios y los datos del negocio.
const Set<String> adminOnlyPaths = {
  '/dashboard',
  '/inventory',
  '/categories',
  '/units',
  '/reports',
  '/users',
  '/business',
};

bool canAccess(AppUser user, String path) => user.isAdmin || !adminOnlyPaths.contains(path);

/// Pantalla con la que empieza cada rol tras entrar.
String homeFor(AppUser user) => user.isAdmin ? '/dashboard' : '/pos';
