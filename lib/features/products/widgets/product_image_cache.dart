import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../../core/config/usage_policy.dart';

/// Native cache: ~53 MiB if files meet the 150 KiB upload cap. Browser caching
/// uses immutable Storage URLs + HTTP headers, not this native disk cache.
final productImageCache = CacheManager(
  Config(
    'koyasProductImagesV1',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: UsagePolicy.imageCacheObjects,
  ),
);
