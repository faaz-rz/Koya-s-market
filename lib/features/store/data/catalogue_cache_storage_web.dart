import 'package:web/web.dart' as web;

String _key(String namespace) => 'koyas.publicCatalogue.v1:$namespace';
Future<String?> readCatalogueCache(String namespace) async {
  try {
    return web.window.localStorage.getItem(_key(namespace));
  } catch (_) {
    return null;
  }
}

Future<void> writeCatalogueCache(String namespace, String data) async {
  // Allow headroom for other browser storage. No auth, orders or addresses.
  if (data.length > 1024 * 1024) return;
  try {
    web.window.localStorage.setItem(_key(namespace), data);
  } catch (_) {
    /* Private browsing/quota failures are a cache miss, not a crash. */
  }
}
