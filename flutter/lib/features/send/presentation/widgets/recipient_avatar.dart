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
    with TickerProviderStateMixin {
  late AnimationController _rippleController;
  late AnimationController _successController;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;
  bool _hasPlayedSuccess = false;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.12)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.12, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
    ]).animate(_successController);

    _colorAnimation = ColorTween(
      begin: kAccentCyan,
      end: const Color(0xFF49B36C), // Success Green
    ).animate(CurvedAnimation(
      parent: _successController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    _updateAnimation();
  }

  @override
  void didUpdateWidget(RecipientAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();

    if (widget.progress >= 1.0 &&
        !_hasPlayedSuccess &&
        widget.mode == SendingStripMode.transferring) {
      _hasPlayedSuccess = true;
      _successController.forward();
    } else if (widget.progress < 1.0) {
      _hasPlayedSuccess = false;
      if (_successController.value > 0 && !widget.animate) {
        _successController.reset();
      }
    }
  }

  void _updateAnimation() {
    final shouldAnimate = widget.animate &&
        (widget.mode == SendingStripMode.waitingOnRecipient ||
            widget.mode == SendingStripMode.looping);
    if (shouldAnimate && !_rippleController.isAnimating) {
      _rippleController.repeat();
    } else if (!shouldAnimate && _rippleController.isAnimating) {
      _rippleController.stop();
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = widget.deviceType.toLowerCase() == 'phone';
    final icon = isPhone ? Icons.smartphone_rounded : Icons.laptop_mac_rounded;
    final isRippling = _rippleController.isAnimating;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 112,
          height: 112,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ripple animation
              if (isRippling)
                AnimatedBuilder(
                  animation: _rippleController,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        for (int i = 0; i < 2; i++)
                          _buildRipple((_rippleController.value + (i * 0.5)) % 1.0),
                      ],
                    );
                  },
                ),

              // Static base ring (always shown for layout stability)
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kAccentCyan.withValues(alpha: 0.12),
                ),
              ),

              // Progress Ring
              if (widget.mode == SendingStripMode.transferring)
                AnimatedBuilder(
                  animation: _successController,
                  builder: (context, child) => SizedBox(
                    width: 96,
                    height: 96,
                    child: CircularProgressIndicator(
                      value: widget.progress.clamp(0.01, 1.0),
                      strokeWidth: 4,
                      strokeCap: StrokeCap.round,
                      backgroundColor: kBorder.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _colorAnimation.value ?? kAccentCyan,
                      ),
                    ),
                  ),
                ),

              // The Pop Container (Background and Icon)
              ScaleTransition(
                scale: _scaleAnimation,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kSurface,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kSurface,
                            kBg.withValues(alpha: 0.5),
                          ],
                        ),
                        border: Border.all(
                          color: kBorder.withValues(alpha: 0.6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
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
              ),
            ],
          ),
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

  Widget _buildRipple(double t) {
    // Starts at avatar edge (90) and expands to edge of footprint (112)
    final size = 90 + (22 * t);
    final opacity = (1.0 - t) * 0.25;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: kAccentCyan.withValues(alpha: opacity),
          width: 1.5,
        ),
      ),
    );
  }
}
