import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/four_dot_loader.dart';
import '../models/delivery_pin.dart';
import '../services/delivery_location_service.dart';

class DeliveryPinField extends ConsumerStatefulWidget {
  const DeliveryPinField({
    required this.pin,
    required this.onChanged,
    required this.onBusyChanged,
    this.enabled = true,
    super.key,
  });
  final DeliveryPin? pin;
  final ValueChanged<DeliveryPin?> onChanged;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;
  @override
  ConsumerState<DeliveryPinField> createState() => _DeliveryPinFieldState();
}

class _DeliveryPinFieldState extends ConsumerState<DeliveryPinField> {
  bool _busy = false;
  DeliveryLocationFailure? _error;
  Future<void> _capture() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusyChanged(true);
    try {
      final pin = await ref.read(deliveryLocationServiceProvider).capture();
      if (mounted) widget.onChanged(pin);
    } on DeliveryLocationFailure catch (error) {
      if (mounted) setState(() => _error = error);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = const DeliveryLocationFailure(
            'Location is unavailable. Enter your address manually.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery pin (optional)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        const Text(
          'Use this while you are at the delivery address. Saving shares this pin with store staff for this address and its orders.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('capture-delivery-pin'),
          onPressed: _busy || !widget.enabled ? null : _capture,
          icon: _busy
              ? const FourDotLoader(size: 20, label: 'Finding location')
              : const Icon(Icons.my_location_rounded),
          label: Text(
            _busy
                ? 'Finding location…'
                : pin == null
                ? 'Use current location'
                : 'Refresh current location',
          ),
        ),
        if (pin != null) ...[
          Text(pin.accuracyLabel),
          if (pin.isApproximate)
            const Text(
              'This pin is approximate. Enable precise location and refresh for better accuracy. Add a landmark below.',
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  try {
                    if (await launchUrl(
                      pin.mapUri,
                      mode: LaunchMode.externalApplication,
                    )) {
                      return;
                    }
                  } catch (_) {}
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Map could not open. Try again when connected.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('Check pin on map'),
              ),
              TextButton(
                onPressed: _busy || !widget.enabled
                    ? null
                    : () => widget.onChanged(null),
                child: const Text('Remove pin'),
              ),
            ],
          ),
        ],
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_error?.openSettings == true && !kIsWeb)
          TextButton(
            onPressed: () =>
                ref.read(deliveryLocationServiceProvider).openSettings(),
            child: const Text('Open settings'),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
