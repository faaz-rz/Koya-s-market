import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/delivery_pin.dart';

final deliveryLocationServiceProvider = Provider<DeliveryLocationService>(
  (ref) => DeliveryLocationService(),
);

class DeliveryLocationFailure implements Exception {
  const DeliveryLocationFailure(this.message, {this.openSettings = false});
  final String message;
  final bool openSettings;
}

/// A single foreground fix, requested only by the customer's explicit action.
class DeliveryLocationService {
  Future<DeliveryPin> capture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const DeliveryLocationFailure(
          'Turn on Location Services, then try again. You can also enter your address manually.',
          openSettings: true,
        );
      }
      if (!kIsWeb) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.deniedForever) {
          throw const DeliveryLocationFailure(
            'Location access is blocked. Enable it in Settings or enter your address manually.',
            openSettings: true,
          );
        }
        if (permission == LocationPermission.denied) {
          throw const DeliveryLocationFailure(
            'Location was not shared. You can still enter your address manually.',
          );
        }
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final pin = DeliveryPin(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        capturedAt: position.timestamp.toUtc(),
      );
      if (!pin.isValid ||
          DateTime.now().difference(pin.capturedAt).abs() >
              const Duration(minutes: 2)) {
        throw const DeliveryLocationFailure(
          'A fresh location could not be obtained. Try again outdoors or enter your address manually.',
        );
      }
      return pin;
    } on DeliveryLocationFailure {
      rethrow;
    } on TimeoutException {
      throw const DeliveryLocationFailure(
        'Location took too long. Try again near a window or enter your address manually.',
      );
    } catch (_) {
      throw const DeliveryLocationFailure(
        'Location could not be obtained. Check location permission and enter your address manually if needed.',
      );
    }
  }

  Future<void> openSettings() async {
    if (!kIsWeb) await Geolocator.openAppSettings();
  }
}
