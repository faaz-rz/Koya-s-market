import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

const _maxBytes = 2 * 1024 * 1024;
Future<File> _file(String namespace) async {
  final directory = await getApplicationCacheDirectory();
  final key = base64Url.encode(utf8.encode(namespace)).replaceAll('=', '');
  return File('${directory.path}/koyas_catalogue_v1_$key.json');
}

Future<String?> readCatalogueCache(String namespace) async {
  try {
    final file = await _file(namespace);
    if (!await file.exists() || await file.length() > _maxBytes) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> writeCatalogueCache(String namespace, String data) async {
  if (utf8.encode(data).length > _maxBytes) return;
  try {
    final file = await _file(namespace);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(data, flush: true);
    await temporary.rename(file.path);
  } catch (_) {
    // Public, disposable acceleration only; never block checkout on disk IO.
  }
}
