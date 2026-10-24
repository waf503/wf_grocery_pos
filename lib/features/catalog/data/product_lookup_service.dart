import '../catalog_item.dart';
import 'catalog_repository.dart';
import 'open_facts_client.dart';

/// Busca información de un código de barras para facilitar el alta de un
/// producto. Orden: memoria local (sin internet) y, si no está, las bases
/// abiertas; lo que se encuentra se guarda para no volver a consultarlo.
class ProductLookupService {
  ProductLookupService(this._local, this._remote);

  final CatalogRepository _local;
  final RemoteLookup _remote;

  /// Solo se consultan códigos comerciales (EAN-8, UPC, EAN-13, ITF-14).
  /// Los códigos internos de la tienda (EAN-13 con prefijo 200) no existen
  /// fuera de ella: no tiene caso enviarlos a internet.
  static bool isLookupable(String code) {
    if (!RegExp(r'^\d{8,14}$').hasMatch(code)) return false;
    return !(code.length == 13 && code.startsWith('200'));
  }

  Future<LookupResult> lookup(String barcode) async {
    final code = barcode.trim();
    if (!isLookupable(code)) return const LookupResult();

    final cached = await _local.findByBarcode(code);
    if (cached != null) return LookupResult(item: cached, fromCache: true);

    final result = await _remote.fetch(code);
    final item = result.item;
    if (item != null) await _local.save(item.withBarcode(code));
    return result;
  }

  void dispose() => _remote.close();
}
