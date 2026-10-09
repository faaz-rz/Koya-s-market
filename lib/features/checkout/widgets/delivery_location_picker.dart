import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/network_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/four_dot_loader.dart';
import '../../../core/widgets/koyas_button.dart';
import '../models/delivery_pin.dart';
import '../services/delivery_address_lookup.dart';
import '../services/delivery_location_service.dart';

typedef DeliveryLocationPicker =
    Future<DeliveryLocationSelection?> Function(
      BuildContext context,
      DeliveryPin pin,
    );
final deliveryLocationPickerProvider = Provider<DeliveryLocationPicker>(
  (ref) =>
      (context, pin) => showModalBottomSheet<DeliveryLocationSelection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DeliveryLocationPickerSheet(initialPin: pin),
      ),
);

final deliveryMapTileProviderFactory = Provider<TileProvider Function()>(
  (ref) =>
      () => NetworkTileProvider(
        cachingProvider: kIsWeb
            ? null
            : BuiltInMapCachingProvider.getOrCreateInstance(
                maxCacheSize: 50 * 1024 * 1024,
              ),
      ),
);

class DeliveryLocationPickerSheet extends ConsumerStatefulWidget {
  const DeliveryLocationPickerSheet({required this.initialPin, super.key});
  final DeliveryPin initialPin;
  @override
  ConsumerState<DeliveryLocationPickerSheet> createState() =>
      _DeliveryLocationPickerSheetState();
}

class _DeliveryLocationPickerSheetState
    extends ConsumerState<DeliveryLocationPickerSheet> {
  final _map = MapController();
  late DeliveryPin _pin = widget.initialPin;
  late final _tiles = ref.read(deliveryMapTileProviderFactory)();
  ResolvedDeliveryAddress? _address;
  bool _resolving = true, _locating = false, _tileError = false;
  String? _message;
  int _request = 0;

  LatLng get _point => LatLng(_pin.latitude, _pin.longitude);

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final request = ++_request;
    final pin = _pin;
    setState(() {
      _resolving = true;
      _address = null;
      _message = null;
    });
    try {
      final address = await ref
          .read(deliveryAddressLookupProvider)
          .resolve(pin);
      if (!mounted || request != _request) return;
      setState(() {
        _address = address;
        if (address == null || address.pincode.isEmpty) {
          _message =
              'Check your street and enter the PIN code below after confirming.';
        }
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(
        () => _message = connectionFailureMessage(
          error,
          'Address lookup is unavailable. Confirm the pin and enter the address manually.',
        ),
      );
    } finally {
      if (mounted && request == _request) setState(() => _resolving = false);
    }
  }

  void _select(LatLng point) {
    if (_locating) return;
    setState(
      () => _pin = DeliveryPin(
        latitude: point.latitude,
        longitude: point.longitude,
        accuracyMeters: _pin.accuracyMeters,
        capturedAt: DateTime.now().toUtc(),
      ),
    );
    unawaited(_resolve());
  }

  Future<void> _recenter() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final pin = await ref.read(deliveryLocationServiceProvider).capture();
      if (!mounted) return;
      setState(() => _pin = pin);
      _map.move(_point, 17);
      await _resolve();
    } on DeliveryLocationFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Location could not be refreshed. Check permissions and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _tileFailed(TileImage tile, Object error, StackTrace? trace) {
    if (_tileError || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileError) setState(() => _tileError = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final map = Stack(
      children: [
        FlutterMap(
          key: const Key('delivery-location-map'),
          mapController: _map,
          options: MapOptions(
            initialCenter: _point,
            initialZoom: 17,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: colors.surfaceMuted,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: (_, point) => _select(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.koyas.koyas_supermarket',
              tileProvider: _tiles,
              maxNativeZoom: 19,
              panBuffer: 0,
              errorTileCallback: _tileFailed,
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _point,
                  width: 52,
                  height: 64,
                  alignment: Alignment.topCenter,
                  child: Semantics(
                    label: 'Selected delivery pin',
                    child: Icon(
                      Icons.location_pin,
                      size: 52,
                      color: colors.brand700,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 24,
                ),
                child: Material(
                  color: colors.surface,
                  child: InkWell(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright'),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        '© OpenStreetMap contributors',
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.inkSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Material(
            color: colors.surface,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Recenter on current location',
              onPressed: _locating ? null : _recenter,
              icon: _locating
                  ? const FourDotLoader(size: 22)
                  : const Icon(Icons.my_location_rounded),
            ),
          ),
        ),
      ],
    );
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_resolving)
          const Row(
            children: [
              FourDotLoader(size: 24, label: 'Looking up address'),
              SizedBox(width: 12),
              Expanded(child: Text('Finding your address…')),
            ],
          )
        else ...[
          Text(
            _address?.formatted.isNotEmpty == true
                ? _address!.formatted
                : 'Selected location',
            key: const Key('resolved-delivery-address'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Confirm the location, then add your flat number and landmark.',
            style: TextStyle(color: colors.inkSecondary),
          ),
        ],
        if (_pin.isApproximate)
          Text(
            'Your device shared an approximate location. Check the pin carefully.',
            style: TextStyle(color: colors.warning),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: TextStyle(color: colors.inkSecondary),
              ),
            ),
          ),
        if (_tileError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Map unavailable. Check your internet connection, or enter the address manually.',
              style: TextStyle(color: colors.warning),
            ),
          ),
      ],
    );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Confirm delivery location',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel location selection',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Tap the map to place the pin at your entrance.',
                    ),
                  ),
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height * .4).clamp(
                      240.0,
                      360.0,
                    ),
                    child: map,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: summary,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: KoyasButton(
                key: const Key('confirm-delivery-location'),
                label: 'Confirm location',
                onPressed: _resolving || _locating
                    ? null
                    : () => Navigator.of(context).pop(
                        DeliveryLocationSelection(pin: _pin, address: _address),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
