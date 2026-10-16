import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../net_lens.dart';
import 'theme.dart';

/// The floating button over the app.
///
/// Tap it to open NetLens, hold it for a bug report, and drag it anywhere: it
/// springs to the nearest edge when you let go. It counts the calls on the
/// current screen, turns red when something fails, and pulses once for each
/// new failure.
class NetLensBubble extends StatefulWidget {
  const NetLensBubble({super.key});

  static const double size = 56;

  @override
  State<NetLensBubble> createState() => _NetLensBubbleState();
}

class _NetLensBubbleState extends State<NetLensBubble> with TickerProviderStateMixin {
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
    _seenErrors = NetLens.store.unseenErrors.value;
    NetLens.store.unseenErrors.addListener(_onErrors);
  }

  @override
  void dispose() {
    NetLens.store.unseenErrors.removeListener(_onErrors);
    _snap.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onErrors() {
    final errors = NetLens.store.unseenErrors.value;
    if (errors > _seenErrors && !NetLens.isOpen.value) _pulse.forward(from: 0);
    _seenErrors = errors;
  }

  void _followSnap() {
    final p = _position;
    if (p != null) setState(() => _position = Offset(_snap.value, p.dy));
  }

  Offset _clamp(Offset o, Size area, EdgeInsets safe) {
    const s = NetLensBubble.size;
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
      valueListenable: NetLens.isOpen,
      builder: (context, open, _) => LayoutBuilder(
        builder: (context, constraints) {
          const s = NetLensBubble.size;
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
                      NetLens.open();
                    },
                    onLongPress: () {
                      _setPressed(false);
                      HapticFeedback.mediumImpact();
                      NetLens.openReport();
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

class _BubbleFace extends StatelessWidget {
  const _BubbleFace({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final store = NetLens.store;
    return ValueListenableBuilder<bool>(
      valueListenable: NetLens.darkTheme,
      builder: (context, dark, _) {
        final t = dark ? NetLensTokens.dark : NetLensTokens.light;
        return ListenableBuilder(
          listenable: Listenable.merge([store, store.unseenErrors]),
          builder: (context, _) {
            final errors = store.unseenErrors.value;
            final count = store.callsFor(store.currentVisit).length;
            final alert = errors > 0;
            final color = alert ? t.err : t.accent;
            final badge = alert ? errors : count;
            const s = NetLensBubble.size;
            return Semantics(
              button: true,
              label: alert
                  ? 'NetLens. $errors failures. Opens the network inspector. Hold for a bug report.'
                  : 'NetLens. $count calls on this screen. Opens the network inspector. Hold for a bug report.',
              child: SizedBox(
                width: s,
                height: s,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: pulse,
                        builder: (context, _) => CustomPaint(painter: _HaloPainter(pulse.value, t.err)),
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
                    if (badge > 0)
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
                            constraints: const BoxConstraints(minWidth: 22),
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: t.surface, width: 2),
                            ),
                            child: Text(
                              badge > 99 ? '99+' : '$badge',
                              style: TextStyle(
                                fontSize: 11,
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
          },
        );
      },
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
