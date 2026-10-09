import '../../../core/widgets/four_dot_loader.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Explicit, on-demand diagnostic; never adds queries to the live polling loop.
class ResourceUsageButton extends StatelessWidget {
  const ResourceUsageButton({this.loadUsage, super.key});
  final Future<Map<String, dynamic>> Function()? loadUsage;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.data_usage, size: 18),
    label: const Text('Check hosting usage'),
    onPressed: () {
      Future<Map<String, dynamic>>? request;
      showDialog<void>(
        context: context,
        builder: (context) {
          // Start when the dialog subscribes, so immediate failures are handled
          // by FutureBuilder rather than becoming unhandled before the frame.
          request ??= Future.sync(
            () =>
                loadUsage?.call() ??
                Supabase.instance.client
                    .rpc('admin_resource_usage')
                    .then((data) => Map<String, dynamic>.from(data as Map)),
          );
          return AlertDialog(
            title: const Text('Hosting usage'),
            content: SizedBox(
              width: 420,
              child: FutureBuilder<dynamic>(
                future: request,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'Could not check usage. Confirm your staff access and database migrations, then try again.',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 80,
                      child: Center(child: FourDotLoader()),
                    );
                  }
                  final data = Map<String, dynamic>.from(snapshot.data as Map);
                  Widget usage(String label, String key, int allowance) {
                    final bytes = (data[key] as num).toInt();
                    final ratio = bytes / allowance;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$label: ${(bytes / 1000000).toStringAsFixed(1)} / ${allowance ~/ 1000000} MB',
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: ratio.clamp(0, 1),
                            color: ratio >= .75
                                ? AppColors.of(context).warning
                                : null,
                          ),
                          if (ratio >= .75)
                            const Text(
                              'Above 75%: review capacity before adding more data.',
                            ),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        usage('Database', 'database_bytes', 500000000),
                        usage('Product images', 'storage_bytes', 1000000000),
                        Text(
                          '${data['product_count']} products · ${data['order_count']} orders',
                        ),
                        Text(
                          '${data['inventory_receipt_count']} inventory retry receipts',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Free-tier reference limits checked 19 Sep 2026. Database size is an estimate; image usage covers this bucket only. Supabase billing is authoritative and includes other projects/buckets where applicable.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Check monthly bandwidth and Auth usage in Supabase, and daily/hourly email usage in your SMTP provider. They cannot be measured by this database query. Never delete orders or retry receipts just to save space.',
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}
