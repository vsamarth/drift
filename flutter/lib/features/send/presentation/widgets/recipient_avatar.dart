import 'package:flutter/material.dart';
import 'package:app/theme/drift_theme.dart';
import 'package:app/features/transfers/presentation/widgets/sending_connection_strip.dart';

class RecipientAvatar extends StatefulWidget {
  const RecipientAvatar({
    super.key,
    required this.deviceName,
    required this.deviceType,
    this.progress = 0.0,
    required this.mode,
    this.animate = true,
  });

  final String deviceName;
  final String deviceType;
  final double progress;
  final SendingStripMode mode;
  final bool animate;

  @override
  State<RecipientAvatar> createState() => _RecipientAvatarState();
}

class _RecipientAvatarState extends State<RecipientAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.animate && widget.mode == SendingStripMode.waitingOnRecipient) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(RecipientAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate &&
        widget.mode == SendingStripMode.waitingOnRecipient &&
        !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (widget.mode != SendingStripMode.waitingOnRecipient) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = widget.deviceType.toLowerCase() == 'phone';
    final icon = isPhone ? Icons.smartphone_rounded : Icons.laptop_mac_rounded;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Pulse effect for waiting state
            if (widget.mode == SendingStripMode.waitingOnRecipient)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 100 + (20 * _pulseController.value),
                    height: 100 + (20 * _pulseController.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kAccentCyan.withValues(
                        alpha: 0.15 * (1.0 - _pulseController.value),
                      ),
                    ),
                  );
                },
              ),
            
            // Background circle
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kSurface,
                border: Border.all(color: kBorder.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
            
            // Progress Ring
            if (widget.mode == SendingStripMode.transferring)
              SizedBox(
                width: 96,
                height: 96,
                child: CircularProgressIndicator(
                  value: widget.progress.clamp(0.01, 1.0),
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: kBorder.withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(kAccentCyan),
                ),
              ),
            
            // Success Ring (Implicitly when progress is 1.0 or state is Result)
            if (widget.mode == SendingStripMode.transferring && widget.progress >= 1.0)
               Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kAccentCyan, width: 4),
                ),
              ),

            // Icon
            Icon(
              icon,
              size: 40,
              color: kInk.withValues(alpha: 0.9),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          widget.deviceName,
          textAlign: TextAlign.center,
          style: driftSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: kInk,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}
