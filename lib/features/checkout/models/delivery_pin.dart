class DeliveryPin {
  const DeliveryPin({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      accuracyMeters.isFinite &&
      accuracyMeters >= 0 &&
      accuracyMeters <= 100000 &&
      capturedAt.millisecondsSinceEpoch >= 0 &&
      capturedAt.millisecondsSinceEpoch <= 4102444800000;
  bool get isApproximate => accuracyMeters > 100;
  String get accuracyLabel => 'Estimated accuracy: ±${accuracyMeters.ceil()} m';
  String get coordinates =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  Uri get mapUri => Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': '$latitude,$longitude',
  });
  Uri get directionsUri => Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$latitude,$longitude',
    'travelmode': 'driving',
  });
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_meters': accuracyMeters,
    'captured_at_ms': capturedAt.millisecondsSinceEpoch,
  };

  static DeliveryPin? fromJson(Object? value) {
    if (value is! Map) return null;
    final lat = value['latitude'], lng = value['longitude'];
    final accuracy = value['accuracy_meters'], time = value['captured_at_ms'];
    if (lat is! num ||
        lng is! num ||
        accuracy is! num ||
        time is! num ||
        !time.isFinite ||
        time < 0 ||
        time > 4102444800000) {
      return null;
    }
    final pin = DeliveryPin(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      accuracyMeters: accuracy.toDouble(),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        time.toInt(),
        isUtc: true,
      ),
    );
    return pin.isValid ? pin : null;
  }
}
