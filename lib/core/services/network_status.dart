import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'network_platform_stub.dart'
    if (dart.library.io) 'network_platform_io.dart'
    if (dart.library.js_interop) 'network_platform_web.dart'
    as platform;

class NoInternetException implements Exception {
  const NoInternetException();
  @override
  String toString() => noInternetMessage;
}

const noInternetMessage =
    'No internet connection. Check Wi-Fi or mobile data and try again.';

bool isNetworkFailure(Object error) =>
    error is NoInternetException ||
    error is http.ClientException ||
    platform.isSocketFailure(error);

String connectionFailureMessage(Object error, String fallback) =>
    isNetworkFailure(error) || NetworkStatus.instance.value
    ? noInternetMessage
    : fallback;

/// Observes real API traffic; it does not poll a third-party service or resend
/// mutations. A server error still proves reachability, so it is not "offline".
class NetworkStatus extends ValueNotifier<bool> {
  NetworkStatus() : super(false);
  static final instance = NetworkStatus();
  int _sequence = 0;
  int _observed = 0;
  int begin() => ++_sequence;
  void observe(int request, {required bool offline}) {
    if (request < _observed) return;
    _observed = request;
    value = offline;
  }
}

class NetworkAwareClient extends http.BaseClient {
  NetworkAwareClient(
    this._inner, {
    NetworkStatus? status,
    this.timeout = const Duration(seconds: 20),
  }) : status = status ?? NetworkStatus.instance;
  final http.Client _inner;
  final NetworkStatus status;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sequence = status.begin();
    try {
      if (platform.browserReportsOffline) throw const NoInternetException();
      final response = await _inner.send(request).timeout(timeout);
      status.observe(sequence, offline: false);
      return http.StreamedResponse(
        _body(response.stream, sequence),
        response.statusCode,
        headers: response.headers,
        request: response.request,
        contentLength: response.contentLength,
        reasonPhrase: response.reasonPhrase,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
      );
    } catch (error) {
      if (isNetworkFailure(error)) {
        status.observe(sequence, offline: true);
        throw const NoInternetException();
      }
      rethrow;
    }
  }

  Stream<List<int>> _body(Stream<List<int>> stream, int sequence) async* {
    try {
      yield* stream.timeout(timeout);
    } catch (error) {
      if (isNetworkFailure(error)) {
        status.observe(sequence, offline: true);
        throw const NoInternetException();
      }
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
