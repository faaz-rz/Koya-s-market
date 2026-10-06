import 'package:flutter_riverpod/flutter_riverpod.dart';

class StoreSyncHealth {
  const StoreSyncHealth({this.live = false, this.failures = 0, this.lastSync});
  final bool live;
  final int failures;
  final DateTime? lastSync;
}

class StoreSyncHealthController extends Notifier<StoreSyncHealth> {
  @override
  StoreSyncHealth build() => const StoreSyncHealth();

  void connection(bool live) {
    if (!ref.mounted || state.live == live) return;
    state = StoreSyncHealth(
      live: live,
      failures: state.failures,
      lastSync: state.lastSync,
    );
  }

  void synced() {
    if (!ref.mounted) return;
    state = StoreSyncHealth(live: state.live, lastSync: DateTime.now());
  }

  void failed(int failures) {
    if (!ref.mounted) return;
    state = StoreSyncHealth(
      live: state.live,
      failures: failures,
      lastSync: state.lastSync,
    );
  }
}

final storeSyncHealthProvider =
    NotifierProvider<StoreSyncHealthController, StoreSyncHealth>(
      StoreSyncHealthController.new,
    );
