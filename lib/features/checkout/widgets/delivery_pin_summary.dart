import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/delivery_pin.dart';

class DeliveryPinSummary extends StatelessWidget {
  const DeliveryPinSummary({required this.pin, this.staff = false, super.key});
  final DeliveryPin pin;
  final bool staff;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delivery pin saved · ${pin.accuracyLabel}'),
        if (pin.isApproximate)
          const Text(
            'Approximate pin. Confirm the written address and landmark.',
          ),
        TextButton.icon(
          key: const Key('open-delivery-pin'),
          onPressed: () async {
            try {
              if (await launchUrl(
                staff ? pin.directionsUri : pin.mapUri,
                mode: LaunchMode.externalApplication,
              )) {
                return;
              }
            } catch (_) {}
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Map could not open. Check your connection and try again.',
                  ),
                ),
              );
            }
          },
          icon: Icon(staff ? Icons.directions_outlined : Icons.map_outlined),
          label: Text(
            staff ? 'Directions to delivery pin' : 'View delivery pin',
          ),
        ),
        if (staff)
          SelectableText(
            pin.coordinates,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}
