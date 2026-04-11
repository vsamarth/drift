import 'package:flutter/material.dart';
import '../../../core/models/transfer_models.dart';
import '../../../core/theme/drift_theme.dart';

class NearbyDevicesSection extends StatelessWidget {
  final List<SendDestinationViewData> devices;
  final SendDestinationViewData? selectedDevice;
  final bool isScanning;
  final ValueChanged<SendDestinationViewData> onSelect;
  final VoidCallback onScan;

  const NearbyDevicesSection({
    super.key,
    required this.devices,
    required this.selectedDevice,
    required this.isScanning,
    required this.onSelect,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'NEARBY DEVICES',
                style: driftSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: kMuted,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: isScanning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(kMuted),
                          ),
                        )
                      : IconButton(
                          onPressed: onScan,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: kMuted,
                          tooltip: 'Scan again',
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (devices.isEmpty)
            Text(
              isScanning ? ' ' : 'No nearby devices found yet.',
              style: driftSans(fontSize: 13, color: kMuted, height: 1.4),
            ),
          if (selectedDevice != null) ...[
            const SizedBox(height: 6),
            Text(
              'Selected: ${selectedDevice!.name}',
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kInk,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (devices.isNotEmpty)
            SizedBox(
              height: 94,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: devices.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final destination = devices[index];
                  final isSelected = destination == selectedDevice;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey<String>(
                        'mobile-nearby-${destination.lanFullname ?? destination.name}',
                      ),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onSelect(destination),
                      child: Container(
                        width: 92,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? kAccentCyanHover : kSurface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? kAccentCyanStrong : kBorder,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.devices_rounded,
                              size: 18,
                              color: isSelected
                                  ? kAccentCyanStrong
                                  : kMuted.withValues(alpha: 0.9),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              destination.name,
                              style: driftSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kInk,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
