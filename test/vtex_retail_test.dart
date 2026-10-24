import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:wf_grocery_pos/features/catalog/catalog_item.dart';
import 'package:wf_grocery_pos/features/catalog/data/open_facts_client.dart';
import 'package:wf_grocery_pos/features/catalog/data/vtex_retail_client.dart';

const _code = '4006000180205';
final _webp = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3, 4]);

Map<String, Object?> _walmartProduct({String ean = _code}) => {
      'productName': 'Desodorante Nivea Derma Control tono uniforme roll on femenino - 50 ml',
      'brand': 'NIVEA',
      'description': 'Deo Nivea Rollon Fem Derma Ctr Tono 50ml',
      'categories': ['/Higiene y Belleza/Cuidado Corporal/Desodorantes/', '/Higiene y Belleza/'],
      'items': [
        {
          'ean': ean,
          'images': [
            {'imageUrl': 'https://walmartsv.vteximg.com.br/arquivos/ids/836027/deo-nivea.jpg?v=1'},
          ],
        },
      ],
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('tienda VTEX (Walmart El Salvador)', () {
    test('busca por código de barras y arma el producto con nombre, marca, categoría e imagen pequeña', () async {
      final requested = <Uri>[];
      final client = VtexRetailClient(
        client: MockClient((request) async {
          requested.add(request.url);
          if (request.url.host == 'walmartsv.vteximg.com.br') {
            return http.Response.bytes(_webp, 200, headers: {'content-type': 'image/webp'});
          }
          return _json([_walmartProduct()], 206);
        }),
      );

      final result = await client.fetch(_code);

      final search = requested.first;
      expect(search.host, 'www.walmart.com.sv');
      expect(search.queryParameters['fq'], 'alternateIds_Ean:$_code');
      final item = result.item!;
      expect(item.source, 'Walmart El Salvador');
      expect(item.name, 'Desodorante Nivea Derma Control tono uniforme roll on femenino - 50 ml');
      expect(item.brand, 'NIVEA');
      expect(item.categoryHint, 'Desodorantes'); // la más específica
      expect(item.barcode, _code);
      expect(item.imageBytes, _webp);
      // Pidió la versión de 300 px, no la original.
      expect(requested.any((u) => u.path.contains('/arquivos/ids/836027-300-300/')), isTrue);
      // El nombre sugerido ya trae la marca y la presentación: no se repiten.
      expect(item.suggestedName, item.name);
    });

    test('si la versión pequeña de la imagen falla, usa la original', () async {
      final client = VtexRetailClient(
        client: MockClient((request) async {
          if (request.url.host == 'walmartsv.vteximg.com.br') {
            return request.url.path.contains('-300-300')
                ? http.Response('no', 404)
                : http.Response.bytes(_webp, 200, headers: {'content-type': 'image/webp'});
          }
          return _json([_walmartProduct()]);
        }),
      );
      expect((await client.fetch(_code)).item!.imageBytes, _webp);
    });

    test('sin resultados: no hay producto y no se marca falta de internet', () async {
      final client = VtexRetailClient(client: MockClient((_) async => _json([], 200)));
      final result = await client.fetch(_code);
      expect(result.item, isNull);
      expect(result.offline, isFalse);
    });

    test('ignora un producto cuyo SKU no tiene exactamente ese código', () async {
      final client = VtexRetailClient(
        client: MockClient((_) async => _json([_walmartProduct(ean: '9999999999999')])),
      );
      expect((await client.fetch(_code)).item, isNull);
    });

    test('sin internet o con la tienda caída se marca offline', () async {
      final down = VtexRetailClient(client: MockClient((_) async => throw const SocketException('sin red')));
      expect((await down.fetch(_code)).offline, isTrue);

      final blocked = VtexRetailClient(client: MockClient((_) async => http.Response('bloqueado', 403)));
      expect((await blocked.fetch(_code)).offline, isTrue);
    });
  });

  group('cadena de fuentes', () {
    test('devuelve la de mayor prioridad que conozca el código', () async {
      final first = _Remote(const LookupResult(item: CatalogItem(source: 'A', name: 'Uno')));
      final second = _Remote(const LookupResult(item: CatalogItem(source: 'B', name: 'Dos')));
      final result = await ChainedLookup([first, second]).fetch(_code);
      expect(result.item!.source, 'A');
    });

    test('si la primera no lo conoce, usa la siguiente', () async {
      final first = _Remote(const LookupResult());
      final second = _Remote(const LookupResult(item: CatalogItem(source: 'B', name: 'Dos')));
      final result = await ChainedLookup([first, second]).fetch(_code);
      expect(result.item!.source, 'B');
      expect(first.calls, 1);
    });

    test('las fuentes corren a la vez: la espera no es la suma de todas', () async {
      Duration slow = const Duration(milliseconds: 400);
      final chain = ChainedLookup([
        _Remote(const LookupResult(), delay: slow),
        _Remote(const LookupResult(item: CatalogItem(source: 'B', name: 'Dos')), delay: slow),
      ]);
      final sw = Stopwatch()..start();
      final result = await chain.fetch(_code);
      expect(result.item!.source, 'B');
      // En serie serían 800 ms; en paralelo, alrededor de 400.
      expect(sw.elapsedMilliseconds, lessThan(700));
    });

    test('la prioridad manda aunque una fuente posterior responda antes', () async {
      final chain = ChainedLookup([
        _Remote(const LookupResult(item: CatalogItem(source: 'A', name: 'Uno')), delay: const Duration(milliseconds: 200)),
        _Remote(const LookupResult(item: CatalogItem(source: 'B', name: 'Dos'))),
      ]);
      expect((await chain.fetch(_code)).item!.source, 'A');
    });

    test('una fuente que lanza un error inesperado no rompe la búsqueda', () async {
      final chain = ChainedLookup([
        _Remote(null, fails: true),
        _Remote(const LookupResult(item: CatalogItem(source: 'B', name: 'Dos'))),
      ]);
      expect((await chain.fetch(_code)).item!.source, 'B');
    });

    test('solo es "sin internet" cuando TODAS las fuentes fallan', () async {
      final offline = await ChainedLookup([
        _Remote(const LookupResult(offline: true)),
        _Remote(const LookupResult(offline: true)),
      ]).fetch(_code);
      expect(offline.offline, isTrue);

      final partial = await ChainedLookup([
        _Remote(const LookupResult(offline: true)),
        _Remote(const LookupResult()), // respondió: simplemente no lo conoce
      ]).fetch(_code);
      expect(partial.offline, isFalse);
      expect(partial.item, isNull);
    });
  });
}

class _Remote implements RemoteLookup {
  _Remote(this.result, {this.delay = Duration.zero, this.fails = false});

  final LookupResult? result;
  final Duration delay;
  final bool fails;
  int calls = 0;

  @override
  Future<LookupResult> fetch(String barcode) async {
    calls++;
    await Future<void>.delayed(delay);
    if (fails) throw StateError('error inesperado');
    return result!;
  }

  @override
  void close() {}
}
