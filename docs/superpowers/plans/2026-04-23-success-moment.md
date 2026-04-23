# Transfer Success Moment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a subtle celebratory "pop" animation and color shift when a transfer reaches 100%, with a 1-second breathing room before transitioning to the results screen.

**Architecture:** 
- Update `RecipientAvatar` to handle a "success sequence" using a dedicated `AnimationController`.
- Introduce a 1-second delay in the transfer controllers (`SendController` and `TransfersServiceController`) upon completion.
- Hide "Cancel" buttons in the UI during this 1-second success window.

**Tech Stack:** Flutter (Animations, Riverpod)

---

### Task 1: Update RecipientAvatar with Success Animation

**Files:**
- Modify: `flutter/lib/features/send/presentation/widgets/recipient_avatar.dart`

- [ ] **Step 1: Add Success Animation Controller and state**
Add `_successController` and track whether the success animation has already played to avoid repeats.

```dart
class _RecipientAvatarState extends State<RecipientAvatar>
    with TickerProviderStateMixin { // Changed from SingleTickerProviderStateMixin
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
        tween: Tween<double>(begin: 1.0, end: 1.12).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.12, end: 1.0).chain(CurveTween(curve: Curves.backOut)),
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
```

- [ ] **Step 2: Trigger Success Sequence on Progress 1.0**
Update `didUpdateWidget` to detect the 100% threshold.

```dart
  @override
  void didUpdateWidget(RecipientAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();

    if (widget.progress >= 1.0 && !_hasPlayedSuccess && widget.mode == SendingStripMode.transferring) {
      _hasPlayedSuccess = true;
      _successController.forward();
    } else if (widget.progress < 1.0) {
      _hasPlayedSuccess = false;
      if (_successController.value > 0 && !widget.animate) {
         _successController.reset();
      }
    }
  }
```

- [ ] **Step 3: Apply Scale and Color Animations in Build**
Wrap the avatar components in `ScaleTransition` and use `_colorAnimation`.

```dart
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
                      valueColor: AlwaysStoppedAnimation<Color>(_colorAnimation.value ?? kAccentCyan),
                    ),
                  ),
                ),

              // The Pop Container
              ScaleTransition(
                scale: _scaleAnimation,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle ...
                    // Icon ...
                  ],
                ),
              ),
```

### Task 2: Introduce Delay in Transfer Controllers

**Files:**
- Modify: `flutter/lib/features/transfers/application/service.dart`
- Modify: `flutter/lib/features/send/application/controller.dart`

- [ ] **Step 1: Add delay to TransfersServiceController (Receiver)**
Modify the completion listener to wait 1 second.

```dart
        case rust_receiver.ReceiverTransferPhase.completed:
          final offer = _mapIncomingOffer(event);
          final result = _mapResult(event);
          unawaited(Future.delayed(const Duration(milliseconds: 1000)).then((_) {
            state = TransferSessionState.completed(
              offer: offer,
              result: result,
            );
            _incomingOffer = null;
            _transferStartTime = null;
          }));
          return;
```

- [ ] **Step 2: Add delay to SendController (Sender)**
Modify `_completeTransfer` to be asynchronous and include the delay.

```dart
  Future<void> _completeTransfer(
    SendTransferResult result, {
    required SendTransferState transfer,
    String? errorMessage,
  }) async {
    final currentState = state;
    if (currentState is! SendStateTransferring) {
      return;
    }

    if (result.outcome == SendTransferOutcome.success) {
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    state = SendStateResult(
       // ... existing args
    );
    // ... rest of method
  }
```

### Task 3: Hide Cancel Buttons During Success Moment

**Files:**
- Modify: `flutter/lib/features/transfers/presentation/widgets/receiving_card.dart`
- Modify: `flutter/lib/features/send/presentation/send_transfer_route.dart`

- [ ] **Step 1: Update ReceivingCard footer**
Hide the button if progress is 1.0.

```dart
        footer: progress.progressFraction >= 1.0 
          ? const SizedBox(height: 52)
          : Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onCancel,
                    // ...
```

- [ ] **Step 2: Update SendTransferRoutePage footer**
Update the `showFooterButton` logic.

```dart
    final showFooterButton =
        (state is SendStateTransferring && progress.progressFraction < 1.0) || 
        state is SendStateResult;
```
