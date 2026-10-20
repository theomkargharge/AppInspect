import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../app_inspect.dart';
import '../schedule.dart';
import 'theme.dart';

/// The floating button over the app.
///
/// Tap it to open AppInspect, and drag it anywhere: it springs to the nearest
/// edge when you let go. Its badge counts the API calls on the current screen.
/// It turns red when something fails, and pulses once for each new failure.
class AppInspectBubble extends StatefulWidget {
  const AppInspectBubble({super.key});

  static const double size = 56;

  @override
  State<AppInspectBubble> createState() => _AppInspectBubbleState();
}

class _AppInspectBubbleState extends State<AppInspectBubble> with TickerProviderStateMixin {
  Offset? _position;
  bool _pressed = false;
  int _seenErrors = 0;

  // Created in initState, not lazily: dispose must never be the first use.
  late final AnimationController _snap;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController.unbounded(vsync: this)..addListener(_followSnap);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _seenErrors = AppInspect.store.unseenErrors.value;
    AppInspect.store.unseenErrors.addListener(_onErrors);
  }

  @override
  void dispose() {
    AppInspect.store.unseenErrors.removeListener(_onErrors);
    _snap.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onErrors() {
    final errors = AppInspect.store.unseenErrors.value;
    if (errors > _seenErrors && !AppInspect.isOpen.value) {
      // Starting the pulse repaints the bubble, which can't happen while
      // Flutter builds the app, where many errors are reported.
      runWhenSafe(() {
        if (mounted) _pulse.forward(from: 0);
      });
    }
    _seenErrors = errors;
  }

  void _followSnap() {
    final p = _position;
    if (p != null) setState(() => _position = Offset(_snap.value, p.dy));
  }

  Offset _clamp(Offset o, Size area, EdgeInsets safe) {
    const s = AppInspectBubble.size;
    return Offset(
      o.dx.clamp(safe.left + 4, math.max(safe.left + 4, area.width - safe.right - s - 4)),
      o.dy.clamp(safe.top + 8, math.max(safe.top + 8, area.height - safe.bottom - s - 8)),
    );
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: AppInspect.isOpen,
      builder: (context, open, _) => LayoutBuilder(
        builder: (context, constraints) {
          const s = AppInspectBubble.size;
          final area = constraints.biggest;
          final pos = _clamp(_position ?? Offset(area.width - s - 12, area.height * 0.62), area, safe);
          return Stack(
            children: [
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: IgnorePointer(
                  ignoring: open,
                  child: GestureDetector(
                    onTapDown: (_) => _setPressed(true),
                    onTapUp: (_) => _setPressed(false),
                    onTapCancel: () => _setPressed(false),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      AppInspect.open();
                    },
                    onPanStart: (_) {
                      _snap.stop();
                      _setPressed(true);
                    },
                    onPanUpdate: (d) => setState(() => _position = pos + d.delta),
                    onPanEnd: (d) {
                      _setPressed(false);
                      final toLeft = pos.dx + s / 2 < area.width / 2;
                      final target = toLeft ? safe.left + 12 : area.width - safe.right - s - 12;
                      _position = pos;
                      _snap.value = pos.dx;
                      _snap.animateWith(SpringSimulation(
                        const SpringDescription(mass: 1, stiffness: 380, damping: 22),
                        pos.dx,
                        target,
                        d.velocity.pixelsPerSecond.dx.clamp(-2500.0, 2500.0),
                      ));
                    },
                    child: AnimatedOpacity(
                      opacity: open ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: AnimatedScale(
                        scale: open ? 0.5 : (_pressed ? 0.9 : 1),
                        duration: Duration(milliseconds: open ? 220 : 160),
                        curve: open ? Curves.easeIn : Curves.easeOutBack,
                        child: _BubbleFace(pulse: _pulse),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The bubble itself: the AppInspect icon, a ring and the call count.
class _BubbleFace extends StatefulWidget {
  const _BubbleFace({required this.pulse});

  final Animation<double> pulse;

  @override
  State<_BubbleFace> createState() => _BubbleFaceState();
}

class _BubbleFaceState extends State<_BubbleFace> {
  late final Listenable _changes =
      Listenable.merge([AppInspect.store, AppInspect.store.unseenErrors, AppInspect.darkTheme]);

  @override
  void initState() {
    super.initState();
    _changes.addListener(_changed);
  }

  @override
  void dispose() {
    _changes.removeListener(_changed);
    super.dispose();
  }

  /// A failure can be counted while Flutter builds the app, such as an error
  /// thrown in a build method, so the bubble catches up after that frame.
  void _changed() => runWhenSafe(() {
        if (mounted) setState(() {});
      });

  @override
  Widget build(BuildContext context) {
    final store = AppInspect.store;
    final t = AppInspect.darkTheme.value ? AppInspectTokens.dark : AppInspectTokens.light;
    final errors = store.unseenErrors.value;
    final count = store.callsFor(store.currentVisit).length;
    final alert = errors > 0;
    final color = alert ? t.err : t.accent;
    // Always the number of calls on this screen. Red says something failed;
    // "!" says so when this screen hasn't made a call.
    final badge = count > 99 ? '99+' : (count > 0 ? '$count' : (alert ? '!' : null));
    const s = AppInspectBubble.size;
    return Semantics(
      button: true,
      // The label already says the count, so the badge isn't read again.
      excludeSemantics: true,
      label: [
        'AppInspect',
        '$count ${count == 1 ? 'call' : 'calls'} on this screen',
        if (alert) '$errors new ${errors == 1 ? 'error' : 'errors'}',
        'Opens the network inspector.',
      ].join('. '),
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: widget.pulse,
                builder: (context, _) => CustomPaint(painter: _HaloPainter(widget.pulse.value, t.err)),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: s,
              height: s,
              decoration: BoxDecoration(
                color: t.surface,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
                boxShadow: t.floatShadow,
              ),
              child: Icon(Icons.manage_search_rounded, size: 27, color: color),
            ),
            if (badge != null)
              Positioned(
                top: -3,
                right: -3,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('$alert$badge'),
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: t.surface, width: 2),
                    ),
                    child: Text(
                      badge,
                      key: const ValueKey('app_inspect_bubble_badge'),
                      maxLines: 1,
                      softWrap: false,
                      // A badge this small stays readable up to a little
                      // larger text, and never outgrows the bubble.
                      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: t.onAccent,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Three soft rings that grow and fade, once per new failure.
class _HaloPainter extends CustomPainter {
  _HaloPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final p = (progress * 3 - i * 0.7).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - p)
        ..color = color.withValues(alpha: 0.45 * (1 - p));
      canvas.drawCircle(center, base + 22 * Curves.easeOut.transform(p), paint);
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.progress != progress || old.color != color;
}
