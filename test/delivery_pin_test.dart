import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/checkout/models/delivery_pin.dart';
import 'package:koyas_supermarket/features/checkout/services/delivery_location_service.dart';
import 'package:koyas_supermarket/features/checkout/widgets/address_editor_dialog.dart';

class TestLocation extends GeolocatorPlatform {
  bool service = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requested = LocationPermission.whileInUse;
  int requests = 0, reads = 0;
  Object? failure;
  DateTime timestamp = DateTime.now();
  double accuracy = 12;
  @override
  Future<bool> isLocationServiceEnabled() async => service;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return requested;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    reads++;
    expect(locationSettings?.timeLimit, const Duration(seconds: 20));
    if (failure != null) throw failure!;
    return Position(
      longitude: 78.419,
      latitude: 17.386,
      timestamp: timestamp,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

class WaitingLocation extends DeliveryLocationService {
  final result = Completer<DeliveryPin>();
  @override
  Future<DeliveryPin> capture() => result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = GeolocatorPlatform.instance;
  late TestLocation location;
  setUp(() {
    location = TestLocation();
    GeolocatorPlatform.instance = location;
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  test(
    'single foreground fix asks permission only when needed and returns finite coordinates with accuracy',
    () async {
      location.permission = LocationPermission.denied;
      final pin = await DeliveryLocationService().capture();
      expect(location.requests, 1);
      expect(location.reads, 1);
      expect(pin.accuracyLabel, 'Estimated accuracy: ±12 m');
      expect(DeliveryPin.fromJson(pin.toJson())!.toJson(), pin.toJson());
      expect(pin.directionsUri.queryParameters['destination'], '17.386,78.419');
      expect(
        DeliveryPin.fromJson({...pin.toJson(), 'latitude': double.nan}),
        null,
      );
      expect(DeliveryPin.fromJson({...pin.toJson(), 'longitude': 181}), null);
    },
  );
  test(
    'denied, permanently denied and disabled services never read a location',
    () async {
      location.permission = LocationPermission.denied;
      location.requested = LocationPermission.denied;
      await expectLater(
        DeliveryLocationService().capture(),
        throwsA(isA<DeliveryLocationFailure>()),
      );
      location.permission = LocationPermission.deniedForever;
      await expectLater(
        DeliveryLocationService().capture(),
        throwsA(
          isA<DeliveryLocationFailure>().having(
            (e) => e.openSettings,
            'settings',
            true,
          ),
        ),
      );
      location.service = false;
      await expectLater(
        DeliveryLocationService().capture(),
        throwsA(isA<DeliveryLocationFailure>()),
      );
      expect(location.reads, 0);
    },
  );
  test(
    'GPS timeout and stale cached fixes retain manual-address fallback; approximate fixes are labelled',
    () async {
      location.failure = TimeoutException('GPS timeout');
      await expectLater(
        DeliveryLocationService().capture(),
        throwsA(
          isA<DeliveryLocationFailure>().having(
            (e) => e.message,
            'message',
            contains('manually'),
          ),
        ),
      );
      location.failure = null;
      location.timestamp = DateTime.now().subtract(const Duration(hours: 1));
      await expectLater(
        DeliveryLocationService().capture(),
        throwsA(isA<DeliveryLocationFailure>()),
      );
      location.timestamp = DateTime.now();
      location.accuracy = 1200;
      expect((await DeliveryLocationService().capture()).isApproximate, true);
    },
  );
  testWidgets(
    'address edits remove mismatched pin; capture blocks Save, can cancel safely, and manual save remains possible',
    (tester) async {
      final service = WaitingLocation();
      final initial = CustomerAddress(
        id: 'saved',
        label: 'Home',
        recipientName: 'Test Customer',
        phone: '9876543210',
        line1: '12 Test Street',
        city: 'Hyderabad',
        pincode: '500008',
        deliveryPin: DeliveryPin(
          latitude: 17.386,
          longitude: 78.419,
          accuracyMeters: 1200,
          capturedAt: DateTime.now(),
        ),
      );
      CustomerAddress? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deliveryLocationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            theme: AppTheme.customer,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<CustomerAddress>(
                      context: context,
                      builder: (_) => AddressEditorDialog(address: initial),
                    );
                  },
                  child: const Text('Edit'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final line = find.widgetWithText(
        TextFormField,
        'Flat, building and street',
      );
      await tester.ensureVisible(line);
      await tester.enterText(line, '99 New Street');
      await tester.pump();
      expect(find.textContaining('Address changed.'), findsOneWidget);
      final capture = find.byKey(const Key('capture-delivery-pin'));
      await tester.ensureVisible(capture);
      await tester.tap(capture);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        null,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      service.result.complete(initial.deliveryPin!);
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(result, null);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(line);
      await tester.enterText(line, '99 New Street');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result!.line1, '99 New Street');
      expect(result!.deliveryPin, null);
    },
  );
}
