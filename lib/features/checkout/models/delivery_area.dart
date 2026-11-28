import 'dart:math' as math;

import 'delivery_pin.dart';

class DeliveryArea {
  const DeliveryArea(this.latitude, this.longitude);

  static const storeOrigin = DeliveryArea(17.37601003, 78.41978797);
  static const pinRequired = 'Add a delivery pin to check this address.';
  static const outsideRadius =
      'This location is outside our delivery area. Please choose an address within 5 km of Koya Stores.';

  final double latitude;
  final double longitude;

  static DeliveryArea? fromSettings(Map<String, dynamic> settings) {
    final latitude = settings['delivery_origin_latitude'];
    final longitude = settings['delivery_origin_longitude'];
    if (latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    return DeliveryArea(latitude.toDouble(), longitude.toDouble());
  }

  String? issueFor(DeliveryPin? pin) {
    if (pin == null || !pin.isValid) return pinRequired;

    const radians = math.pi / 180;
    final sinLatitude = math.sin((pin.latitude - latitude) * radians / 2);
    final sinLongitude = math.sin((pin.longitude - longitude) * radians / 2);
    final h =
        sinLatitude * sinLatitude +
        math.cos(latitude * radians) *
            math.cos(pin.latitude * radians) *
            sinLongitude *
            sinLongitude;
    final distance = 2 * 6371008.8 * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
    return distance > 5000.0000001 ? outsideRadius : null;
  }
}
