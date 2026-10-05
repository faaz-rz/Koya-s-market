import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A safe customer-facing message that retains the server's rollback code.
class TransactionValidationException extends PostgrestException {
  const TransactionValidationException(String message, String? code)
    : super(message: message, code: code);
}

String transactionFailureMessage(Object error, String fallback) {
  if (error is PostgrestException && error.code == 'PT409') {
    return 'These details changed while you were editing. Refresh and try again.';
  }
  if (error is PostgrestException &&
      const {
        '40001',
        '40P01',
        '55P03',
        '57014',
        '502',
        '503',
        '504',
      }.contains(error.code)) {
    return 'The store is busy. Please try again in a moment.';
  }
  return fallback;
}

String newTransactionId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

bool isDefinitiveTransactionFailure(Object error) =>
    error is PostgrestException &&
    (RegExp(r'^[A-Z0-9]{5}$').hasMatch(error.code ?? '') ||
        (error.code ?? '').startsWith('PGRST'));

/// Only use with a server-idempotent RPC and an unchanged request ID/payload.
Future<T> retryTransaction<T>(
  Future<T> Function() send, {
  Future<void> Function(Duration) wait = Future<void>.delayed,
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await send();
    } catch (error) {
      final retryable =
          error is TimeoutException ||
          (error is PostgrestException &&
              const {
                '40001',
                '40P01',
                '55P03',
                '57014',
                '502',
                '503',
                '504',
              }.contains(error.code));
      if (!retryable || attempt >= 2) rethrow;
      await wait(Duration(milliseconds: 150 * (1 << attempt)));
    }
  }
}

/// Retain an uncertain mutation's ID across route/repository reconstruction in
/// the same session. Only a confirmed result ends the attempt. Even a later
/// permission/lock failure does not prove an earlier lost response rolled back.
dynamic _canonical(dynamic value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

class InventoryRequestRegistry {
  final _ids = <String, String>{};
  final _running = <String, Future<Map<String, dynamic>>>{};

  void clearScope(String prefix) {
    _ids.removeWhere((key, _) => key.startsWith('$prefix:'));
    _running.removeWhere((key, _) => key.startsWith('$prefix:'));
  }

  Future<Map<String, dynamic>> run({
    required String userId,
    required Map<String, dynamic> request,
    required Future<Map<String, dynamic>> Function(String id) send,
  }) {
    final key = '$userId:${jsonEncode(_canonical(request))}';
    return _running[key] ??= _run(key, send);
  }

  Future<Map<String, dynamic>> _run(
    String key,
    Future<Map<String, dynamic>> Function(String id) send,
  ) async {
    final id = _ids.putIfAbsent(key, newTransactionId);
    try {
      final result = await retryTransaction(() => send(id));
      _ids.remove(key);
      return result;
    } finally {
      _running.remove(key);
    }
  }
}

/// One checkout attempt can outlive the payment screen. A lost response retries
/// the original basket/date/key; two mounted screens share the same request.
class CheckoutAttempt<T> {
  T? snapshot;
  String? _id;
  DateTime? _startedAt;
  String? _confirmedId;
  Future<String>? _running;
  int _generation = 0;
  bool _uncertain = false;
  bool get hasUncertainResult => _uncertain;

  Future<String> submit(
    T current,
    Future<String> Function(T snapshot, String key, DateTime startedAt) send,
  ) {
    if (_confirmedId != null) return Future.value(_confirmedId);
    snapshot ??= current;
    _id ??= newTransactionId();
    _startedAt ??= DateTime.now();
    return _running ??= _submit(
      snapshot as T,
      _id!,
      _startedAt!,
      _generation,
      send,
    );
  }

  Future<String> _submit(
    T frozen,
    String id,
    DateTime date,
    int generation,
    Future<String> Function(T, String, DateTime) send,
  ) async {
    try {
      final confirmed = await retryTransaction(() async {
        try {
          return await send(frozen, id, date);
        } catch (error) {
          if (generation == _generation &&
              !isDefinitiveTransactionFailure(error)) {
            _uncertain = true;
          }
          rethrow;
        }
      });
      if (generation == _generation) _confirmedId = confirmed;
      return confirmed;
    } catch (error) {
      if (generation == _generation &&
          !_uncertain &&
          isDefinitiveTransactionFailure(error) &&
          !(error is PostgrestException && error.code == 'PT409')) {
        reset();
      }
      rethrow;
    } finally {
      if (generation == _generation) _running = null;
    }
  }

  void reset() {
    _generation++;
    _running = null;
    snapshot = null;
    _id = null;
    _startedAt = null;
    _confirmedId = null;
    _uncertain = false;
  }
}
