import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/core/widgets/koyas_button.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/checkout/models/delivery_pin.dart';
import 'package:koyas_supermarket/features/checkout/services/delivery_address_lookup.dart';
import 'package:koyas_supermarket/features/checkout/services/delivery_location_service.dart';
import 'package:koyas_supermarket/features/checkout/widgets/address_editor_form.dart';
import 'package:koyas_supermarket/features/checkout/widgets/delivery_location_picker.dart';

final samplePin = DeliveryPin(
  latitude: 17.386,
  longitude: 78.419,
  accuracyMeters: 12,
  capturedAt: DateTime.now(),
);
const place = Placemark(
  street: 'Market Road',
  subLocality: 'Tolichowki',
  locality: 'Hyderabad',
  postalCode: '500008',
  isoCountryCode: 'IN',
);

class FixedLocation extends DeliveryLocationService {
  @override
  Future<DeliveryPin> capture() async => samplePin;
}

class TestMapTiles extends TileProvider {
  static final _pixel = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_pixel);
}

Future<void> editor(
  WidgetTester tester,
  DeliveryLocationSelection? selection, {
  ValueChanged<CustomerAddress>? save,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deliveryLocationServiceProvider.overrideWithValue(FixedLocation()),
        deliveryLocationPickerProvider.overrideWithValue(
          (_, _, {required requirePlacement}) async => selection,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.customer,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AddressEditorForm(
              initialName: 'Customer',
              initialPhone: '9876543210',
              onSave: save ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String text(WidgetTester tester, String field) => tester
    .widget<TextFormField>(find.byKey(Key('address-$field')))
    .controller!
    .text;

void main() {
  test(
    'native reverse lookup fills street, city and PIN; missing or foreign postal data is never invented',
    () async {
      final address = await DeliveryAddressLookup(
        lookup: (_, _) async => [place],
      ).resolve(samplePin);
      expect(address!.street, 'Market Road, Tolichowki');
      expect(address.city, 'Hyderabad');
      expect(address.pincode, '500008');
      expect(
        ResolvedDeliveryAddress.fromPlacemark(
          const Placemark(postalCode: '123456', isoCountryCode: 'US'),
        ).pincode,
        isEmpty,
      );
      expect(
        ResolvedDeliveryAddress.fromPlacemark(const Placemark()).formatted,
        isEmpty,
      );
      expect(
        await DeliveryAddressLookup(
          lookup: (_, _) async => [],
        ).resolve(samplePin),
        isNull,
      );
    },
  );

  test(
    'slow geocoder is bounded and returns control for manual address entry',
    () async {
      final pending = Completer<List<Placemark>>();
      await expectLater(
        DeliveryAddressLookup(
          lookup: (_, _) => pending.future,
          timeout: const Duration(milliseconds: 10),
        ).resolve(samplePin),
        throwsA(isA<TimeoutException>()),
      );
      pending.complete([place]);
    },
  );

  testWidgets(
    'confirmed location fills editable address; adding a flat preserves the selected pin',
    (tester) async {
      CustomerAddress? saved;
      await editor(
        tester,
        DeliveryLocationSelection(
          pin: samplePin,
          address: ResolvedDeliveryAddress.fromPlacemark(place),
        ),
        save: (a) => saved = a,
      );
      await tester.tap(find.byKey(const Key('capture-delivery-pin')));
      await tester.pumpAndSettle();
      expect(text(tester, 'line'), 'Market Road, Tolichowki');
      expect(text(tester, 'city'), 'Hyderabad');
      expect(text(tester, 'pincode'), '500008');
      final flat = find.byKey(const Key('address-flat'));
      await tester.ensureVisible(flat);
      await tester.enterText(flat, 'Flat 204');
      final save = find.byKey(const Key('save-address'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved!.line1, 'Flat 204, Market Road, Tolichowki');
      expect(saved!.deliveryPin!.coordinates, samplePin.coordinates);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancel preserves fields and a new pin can be saved with a manually entered address',
    (tester) async {
      CustomerAddress? saved;
      await editor(tester, null);
      await tester.enterText(
        find.byKey(const Key('address-line')),
        'Typed street',
      );
      await tester.enterText(
        find.byKey(const Key('address-pincode')),
        '500008',
      );
      await tester.ensureVisible(find.byKey(const Key('capture-delivery-pin')));
      await tester.tap(find.byKey(const Key('capture-delivery-pin')));
      await tester.pumpAndSettle();
      expect(text(tester, 'line'), 'Typed street');
      expect(text(tester, 'pincode'), '500008');
      await tester.pumpWidget(const SizedBox.shrink());
      await editor(
        tester,
        DeliveryLocationSelection(pin: samplePin),
        save: (address) => saved = address,
      );
      await tester.enterText(
        find.byKey(const Key('address-line')),
        'Typed street',
      );
      await tester.enterText(
        find.byKey(const Key('address-pincode')),
        '500008',
      );
      await tester.ensureVisible(find.byKey(const Key('capture-delivery-pin')));
      await tester.tap(find.byKey(const Key('capture-delivery-pin')));
      await tester.pumpAndSettle();
      expect(text(tester, 'pincode'), '500008');
      expect(text(tester, 'line'), 'Typed street');
      await tester.enterText(
        find.byKey(const Key('address-line')),
        'Typed street',
      );
      await tester.enterText(
        find.byKey(const Key('address-city')),
        'Hyderabad',
      );
      await tester.enterText(
        find.byKey(const Key('address-pincode')),
        '500008',
      );
      final save = find.byKey(const Key('save-address'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved?.deliveryPin, samplePin);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'map confirmation and ${dark ? 'manual placement' : 'street search'} fit 320px and large text',
      (tester) async {
        final searchedPin = Location(
          latitude: 17.385,
          longitude: 78.416,
          timestamp: DateTime(2026),
        );
        DeliveryLocationSelection? confirmed;
        String? searchedQuery;
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deliveryAddressLookupProvider.overrideWithValue(
                DeliveryAddressLookup(
                  lookup: (_, _) async => [place],
                  findLocations: (query) async {
                    searchedQuery = query;
                    return [searchedPin];
                  },
                ),
              ),
              deliveryMapTileProviderFactory.overrideWithValue(
                TestMapTiles.new,
              ),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async => confirmed =
                        await showModalBottomSheet<DeliveryLocationSelection>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => MediaQuery(
                            data: MediaQuery.of(
                              context,
                            ).copyWith(textScaler: const TextScaler.linear(2)),
                            child: DeliveryLocationPickerSheet(
                              initialPin: samplePin,
                              requirePlacement: dark,
                            ),
                          ),
                        ),
                    child: const Text('Open map'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open map'));
        await tester.pumpAndSettle();
        final map = find.byKey(const Key('delivery-location-map'));
        final confirm = find.byKey(const Key('confirm-delivery-location'));
        expect(map, findsOneWidget);
        if (dark) {
          expect(find.bySemanticsLabel('Selected delivery pin'), findsNothing);
          expect(tester.widget<KoyasButton>(confirm).onPressed, isNull);
          await tester.ensureVisible(map);
          await tester.pumpAndSettle();
          expect(map.hitTestable(), findsOneWidget);
          await tester.tap(map);
          await tester.pump();
          // The map waits briefly to distinguish a tap from a double tap.
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsLabel('Selected delivery pin'),
            findsOneWidget,
          );
        } else {
          await tester.enterText(
            find.byKey(const Key('search-delivery-address')),
            ' Market Road ',
          );
          await tester.tap(find.byTooltip('Search for address'));
          await tester.pumpAndSettle();
          expect(searchedQuery, 'Market Road');
        }
        final result = find.byKey(const Key('resolved-delivery-address'));
        expect(tester.widget<Text>(result).data, contains('500008'));
        await tester.ensureVisible(result);
        await tester.pumpAndSettle();
        expect(find.textContaining('500008'), findsOneWidget);
        expect(tester.widget<KoyasButton>(confirm).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        if (!dark) {
          expect(confirmed?.pin.latitude, searchedPin.latitude);
          expect(confirmed?.pin.longitude, searchedPin.longitude);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
