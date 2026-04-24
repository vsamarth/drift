import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/drift_theme.dart';
import '../../../receive/application/service.dart';
import '../../../receive/application/state.dart';
import '../../application/controller.dart';
import '../../application/model.dart';
import '../../application/state.dart';
import '../receive_code_field.dart';

class SendDestinationSelector extends ConsumerStatefulWidget {
  const SendDestinationSelector({super.key, required this.controller});

  final SendController controller;

  @override
  ConsumerState<SendDestinationSelector> createState() =>
      _SendDestinationSelectorState();
}

class _SendDestinationSelectorState
    extends ConsumerState<SendDestinationSelector> {
  List<NearbyReceiver> _nearbyDevices = const [];
  bool _isScanningNearby = false;
  bool _nearbyScanCompletedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_scanNearby());
      }
    });
  }

  Future<void> _scanNearby() async {
    setState(() {
      _isScanningNearby = true;
    });

    try {
      final devices = await ref
          .read(receiverServiceProvider.notifier)
          .scanNearby(timeout: const Duration(seconds: 4));
      if (!mounted) {
        return;
      }
      setState(() {
        _nearbyDevices = devices;
        _isScanningNearby = false;
        _nearbyScanCompletedOnce = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nearbyDevices = const [];
        _isScanningNearby = false;
        _nearbyScanCompletedOnce = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sendControllerProvider);
    final destination = switch (state) {
      SendStateDrafting(:final destination) => destination,
      SendStateTransferring(:final destination) => destination,
      SendStateResult(:final destination) => destination,
      SendStateIdle() => const SendDestinationState.none(),
    };

    final titleStyle = driftSans(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: kInk,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Nearby devices', style: titleStyle),
            const Spacer(),
            _ScanAction(isScanning: _isScanningNearby, onPressed: _scanNearby),
          ],
        ),
        const SizedBox(height: 12),
        if (_nearbyDevices.isEmpty)
          _NearbyStatusCard(
            isScanning: _isScanningNearby && !_nearbyScanCompletedOnce,
          )
        else
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _nearbyDevices.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final receiver = _nearbyDevices[index];
                final selected =
                    destination.mode == SendDestinationMode.nearby &&
                    destination.ticket == receiver.ticket;
                return _NearbyDeviceTile(
                  receiver: receiver,
                  isSelected: selected,
                  icon: Icons.devices_rounded,
                  onTap: () => widget.controller.selectNearbyReceiver(receiver),
                );
              },
            ),
          ),
        const SizedBox(height: 18),
        Text('Send with code', style: titleStyle),
        const SizedBox(height: 6),
        Text(
          'Use the 6 characters shown on the receiver.',
          style: driftSans(fontSize: 13.5, color: kMuted, height: 1.4),
        ),
        const SizedBox(height: 16),
        ReceiveCodeField(
          code: destination.mode == SendDestinationMode.code
              ? destination.code ?? ''
              : '',
          onChanged: widget.controller.updateDestinationCode,
          hintText: 'AB12CD',
          understated: true,
        ),
      ],
    );
  }
}

class _ScanAction extends StatelessWidget {
  const _ScanAction({required this.isScanning, required this.onPressed});

  final bool isScanning;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FB9CA)),
        ),
      );
    }

    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: Text(
        'Rescan',
        style: driftSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF7AAFC9),
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF7AAFC9),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _NearbyStatusCard extends StatelessWidget {
  const _NearbyStatusCard({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final title = isScanning
        ? 'Scanning for nearby receivers...'
        : 'No nearby devices found';
    final subtitle = isScanning
        ? 'Make sure both devices are on the same Wi-Fi.'
        : 'Make sure both devices are on the same Wi-Fi. Local network access may be required.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 22,
              height: 22,
              child: Icon(
                isScanning ? Icons.radar_rounded : Icons.wifi_off_rounded,
                size: 20,
                color: const Color(0xFF8E8E8E),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: driftSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: driftSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: kMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyDeviceTile extends StatelessWidget {
  const _NearbyDeviceTile({
    required this.receiver,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  final NearbyReceiver receiver;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 106,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF4F8FA) : kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF8DBED4) : kBorder,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? const Color(0xFF7AAFC9) : kMuted,
            ),
            const SizedBox(height: 10),
            Text(
              receiver.label,
              style: driftSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: kInk,
                height: 1.18,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
