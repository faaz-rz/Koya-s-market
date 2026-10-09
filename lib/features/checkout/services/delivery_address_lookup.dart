import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

import '../models/delivery_pin.dart';

class ResolvedDeliveryAddress {
  const ResolvedDeliveryAddress({
    this.street = '',
    this.city = '',
    this.pincode = '',
  });
  final String street, city, pincode;
  String get formatted =>
      [street, city, pincode].where((v) => v.isNotEmpty).join(', ');

  factory ResolvedDeliveryAddress.fromPlacemark(Placemark place) {
    String clean(String? value) =>
        (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    final street = clean(place.street).isNotEmpty
        ? clean(place.street)
        : [
            clean(place.subThoroughfare),
            clean(place.thoroughfare),
          ].where((v) => v.isNotEmpty).join(' ');
    final parts = <String>[];
    for (final value in [street, clean(place.subLocality)]) {
      if (value.isNotEmpty &&
          !parts.any((p) => p.toLowerCase() == value.toLowerCase())) {
        parts.add(value);
      }
    }
    final city = [
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
    ].map(clean).firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final postal = clean(place.postalCode).replaceAll(' ', '');
    final indian =
        clean(place.isoCountryCode).isEmpty ||
        clean(place.isoCountryCode).toUpperCase() == 'IN';
    final line = parts.join(', ');
    return ResolvedDeliveryAddress(
      street: line.length > 200 ? line.substring(0, 200) : line,
      city: city.length > 80 ? city.substring(0, 80) : city,
      pincode: indian && RegExp(r'^\d{6}$').hasMatch(postal) ? postal : '',
    );
  }
}

class DeliveryLocationSelection {
  const DeliveryLocationSelection({required this.pin, this.address});
  final DeliveryPin pin;
  final ResolvedDeliveryAddress? address;
}

final deliveryAddressLookupProvider = Provider<DeliveryAddressLookup>(
  (ref) => DeliveryAddressLookup(),
);

/// Android/iOS use the operating system's geocoder; no paid Maps API key.
/// Lookups occur only after an explicit location action, never in background.
class DeliveryAddressLookup {
  DeliveryAddressLookup({
    this.lookup,
    this.timeout = const Duration(seconds: 8),
  });
  final Future<List<Placemark>> Function(double, double)? lookup;
  final Duration timeout;

  Future<ResolvedDeliveryAddress?> resolve(DeliveryPin pin) async {
    if (!pin.isValid) return null;
    if (lookup == null && kIsWeb) return null;
    final reader =
        lookup ??
        Geocoding(locale: const Locale('en', 'IN')).placemarkFromCoordinates;
    final places = await reader(pin.latitude, pin.longitude).timeout(timeout);
    final addresses = places
        .map(ResolvedDeliveryAddress.fromPlacemark)
        .toList();
    int score(ResolvedDeliveryAddress a) =>
        (a.pincode.isEmpty ? 0 : 4) +
        (a.city.isEmpty ? 0 : 2) +
        (a.street.isEmpty ? 0 : 1);
    addresses.sort((a, b) => score(b).compareTo(score(a)));
    return addresses.isEmpty || addresses.first.formatted.isEmpty
        ? null
        : addresses.first;
  }
}
