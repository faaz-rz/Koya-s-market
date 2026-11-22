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
import '../../store/providers/store_provider.dart';
import '../models/delivery_pin.dart';
import '../services/delivery_address_lookup.dart';
import '../services/delivery_location_service.dart';

typedef DeliveryLocationPicker =
    Future<DeliveryLocationSelection?> Function(
      BuildContext context,
      DeliveryPin pin, {
      required bool requirePlacement,
    });
final deliveryLocationPickerProvider = Provider<DeliveryLocationPicker>(
  (ref) =>
      (context, pin, {required requirePlacement}) =>
          showModalBottomSheet<DeliveryLocationSelection>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => DeliveryLocationPickerSheet(
              initialPin: pin,
              requirePlacement: requirePlacement,
            ),
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
  const DeliveryLocationPickerSheet({
    required this.initialPin,
    this.requirePlacement = false,
    super.key,
  });
  final DeliveryPin initialPin;
  final bool requirePlacement;
  @override
  ConsumerState<DeliveryLocationPickerSheet> createState() =>
      _DeliveryLocationPickerSheetState();
}

class _DeliveryLocationPickerSheetState
    extends ConsumerState<DeliveryLocationPickerSheet> {
  final _map = MapController();
  final _searchController = TextEditingController();
  late DeliveryPin _pin = widget.initialPin;
  late bool _hasSelectedPin = !widget.requirePlacement;
  late final _tiles = ref.read(deliveryMapTileProviderFactory)();
  ResolvedDeliveryAddress? _address;
  bool _resolving = false, _locating = false, _searching = false;
  bool _mapReady = false, _tileError = false;
  String? _message;
  int _request = 0;

  LatLng get _point => LatLng(_pin.latitude, _pin.longitude);

  @override
  void initState() {
    super.initState();
    if (_hasSelectedPin) unawaited(_resolve());
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    if (_locating || _searching) return;
    setState(() {
      _hasSelectedPin = true;
      _pin = DeliveryPin(
        latitude: point.latitude,
        longitude: point.longitude,
        accuracyMeters: 0,
        capturedAt: DateTime.now().toUtc(),
      );
    });
    unawaited(_resolve());
  }

  Future<void> _recenter() async {
    if (_locating || _searching) return;
    setState(() => _locating = true);
    try {
      final pin = await ref.read(deliveryLocationServiceProvider).capture();
      if (!mounted) return;
      setState(() {
        _hasSelectedPin = true;
        _pin = pin;
      });
      if (_mapReady) _map.move(_point, 17);
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

  Future<void> _search() async {
    if (_locating || _searching) return;
    final query = _searchController.text.trim();
    if (query.length < 3) {
      setState(() => _message = 'Enter an area, street or PIN code.');
      return;
    }
    FocusScope.of(context).unfocus();
    _request++;
    setState(() {
      _searching = true;
      _resolving = false;
      _message = null;
    });
    try {
      final pin = await ref
          .read(deliveryAddressLookupProvider)
          .findLocation(query);
      if (!mounted) return;
      if (pin == null) {
        setState(
          () => _message =
              'Address not found. Try a nearby street or place the pin on the map.',
        );
        return;
      }
      setState(() {
        _hasSelectedPin = true;
        _pin = pin;
        _tileError = false;
      });
      if (_mapReady) _map.move(_point, 17);
      await _resolve();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Search is unavailable. Place the pin on the map or use your current location.',
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
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
    final canSearch = ref.watch(deliveryAddressLookupProvider).canSearch;
    final deliveryArea = ref.watch(
      storeProvider.select((store) => store.deliveryArea),
    );
    final areaIssue = _hasSelectedPin ? deliveryArea?.issueFor(_pin) : null;
    final map = Stack(
      children: [
        FlutterMap(
          key: const Key('delivery-location-map'),
          mapController: _map,
          options: MapOptions(
            initialCenter: _point,
            initialZoom: widget.requirePlacement ? 13 : 17,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: colors.surfaceMuted,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: (_, point) => _select(point),
            onMapReady: () => _mapReady = true,
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
            if (_hasSelectedPin)
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
              onPressed: _locating || _searching ? null : _recenter,
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
        if (_searching && !_resolving)
          const Text('Searching for the address…')
        else if (_resolving)
          const Row(
            children: [
              FourDotLoader(size: 24, label: 'Looking up address'),
              SizedBox(width: 12),
              Expanded(child: Text('Finding your address…')),
            ],
          )
        else if (_hasSelectedPin) ...[
          Text(
            _address?.formatted.isNotEmpty == true
                ? _address!.formatted
                : 'Selected location',
            key: const Key('resolved-delivery-address'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Check the pin is at the entrance before confirming.',
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
        if (areaIssue != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(areaIssue, style: TextStyle(color: colors.warning)),
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
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (canSearch)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        child: TextField(
                          key: const Key('search-delivery-address'),
                          controller: _searchController,
                          enabled: !_searching && !_locating,
                          maxLength: 120,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: InputDecoration(
                            labelText: 'Area, street or PIN code',
                            counterText: '',
                            suffixIcon: IconButton(
                              tooltip: 'Search for address',
                              onPressed: _searching || _locating
                                  ? null
                                  : _search,
                              icon: const Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                      ),
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: KoyasButton(
                key: const Key('confirm-delivery-location'),
                label: 'Confirm location',
                onPressed:
                    !_hasSelectedPin || _resolving || _locating || _searching
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
