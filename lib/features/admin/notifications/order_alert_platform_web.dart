import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'order_alert_types.dart';

OrderAlertPlatform createOrderAlertPlatform() => BrowserOrderAlerts();

class BrowserOrderAlerts implements OrderAlertPlatform {
  web.AudioContext? _audio;
  web.Notification? _notification;

  @override
  Future<OrderAlertPermission> enable() async {
    // Start both operations inside the staff member's click gesture, before
    // awaiting either promise. Permission/audio failures never block orders.
    Future<bool> sound() async {
      try {
        if (_audio == null || _audio!.state == 'closed') {
          _audio = web.AudioContext();
        }
        await _audio!.resume().toDart;
        return _audio!.state == 'running';
      } catch (_) {
        return false;
      }
    }

    Future<BrowserAlertPermission> notifications() async {
      try {
        if (!web.window.isSecureContext ||
            !globalContext.hasProperty('Notification'.toJS).toDart) {
          return BrowserAlertPermission.unavailable;
        }
        final permission = web.Notification.permission == 'default'
            ? (await web.Notification.requestPermission().toDart).toDart
            : web.Notification.permission;
        return permission == 'granted'
            ? BrowserAlertPermission.granted
            : BrowserAlertPermission.denied;
      } catch (_) {
        return BrowserAlertPermission.unavailable;
      }
    }

    final soundRequest = sound();
    final notificationRequest = notifications();
    return OrderAlertPermission(
      sound: await soundRequest,
      notifications: await notificationRequest,
    );
  }

  @override
  Future<bool> playChime() async {
    try {
      final audio = _audio;
      if (audio == null || audio.state != 'running') return false;
      final start = audio.currentTime;
      for (var i = 0; i < 2; i++) {
        final oscillator = audio.createOscillator();
        final gain = audio.createGain();
        final time = start + i * .19;
        oscillator.type = 'sine';
        oscillator.frequency.setValueAtTime(i == 0 ? 880 : 1174.66, time);
        gain.gain.setValueAtTime(.0001, time);
        gain.gain.exponentialRampToValueAtTime(.09, time + .015);
        gain.gain.exponentialRampToValueAtTime(.0001, time + .28);
        oscillator.connect(gain);
        gain.connect(audio.destination);
        oscillator.onended = ((web.Event _) {
          oscillator.disconnect();
          gain.disconnect();
        }).toJS;
        oscillator.start(time);
        oscillator.stop(time + .3);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool notify({required int count, required void Function() onOpen}) {
    try {
      if (!globalContext.hasProperty('Notification'.toJS).toDart ||
          web.Notification.permission != 'granted') {
        return false;
      }
      dismiss();
      final notification = web.Notification(
        count == 1
            ? 'Koya Stores · New order'
            : 'Koya Stores · $count new orders',
        web.NotificationOptions(
          body: 'Open the order queue to review.',
          tag: 'koyas-new-orders',
          icon: '/icons/Icon-192.png',
          silent: true,
          renotify: false,
        ),
      );
      notification.onclick = ((web.Event _) {
        web.window.focus();
        notification.close();
        onOpen();
      }).toJS;
      _notification = notification;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void badge(int count) {
    web.document.title = count > 0
        ? '($count) Koya Stores Admin'
        : 'Koya Stores Admin';
  }

  @override
  void dismiss() {
    try {
      _notification?.close();
    } catch (_) {}
    _notification = null;
  }

  @override
  void dispose() {
    dismiss();
    badge(0);
    final audio = _audio;
    _audio = null;
    if (audio != null && audio.state != 'closed') {
      unawaited(
        audio.close().toDart.then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }
}
