import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Shrinks a little while pressed and gives a light haptic tap, so every
/// tappable surface feels physical.
class NlPressable extends StatefulWidget {
  const NlPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final String? semanticLabel;

  @override
  State<NlPressable> createState() => _NlPressableState();
}

class _NlPressableState extends State<NlPressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _set(false);
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A white card with a hairline and a soft shadow.
class NlCard extends StatelessWidget {
  const NlCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.shadow = true,
    this.radius = AppInspectRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final bool shadow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? t.border),
        boxShadow: shadow ? t.cardShadow : null,
      ),
      child: child,
    );
  }
}

/// A small rounded label, optionally with a leading dot or icon.
class NlPill extends StatelessWidget {
  const NlPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.dot = false,
    this.icon,
    this.mono = false,
  });

  final String label;
  final Color foreground;
  final Color background;
  final bool dot;
  final IconData? icon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final style = (mono ? appInspectMono : const TextStyle()).copyWith(
      fontSize: 11.5,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: foreground,
      letterSpacing: mono ? 0 : 0.1,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppInspectRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: foreground, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          // A long label, such as an error message, ends in an ellipsis
          // instead of overflowing. Where the width is unbounded, the pill
          // takes the label's natural width.
          Flexible(child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// A round, quiet icon button with a tooltip and an optional badge.
class NlIconButton extends StatelessWidget {
  const NlIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: NlPressable(
        onTap: onPressed,
        pressedScale: 0.9,
        semanticLabel: tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: t.surface,
                shape: BoxShape.circle,
                border: Border.all(color: t.border),
              ),
              child: Icon(icon, size: 19, color: onPressed == null ? t.textMuted : t.text),
            ),
            if (badge)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: t.err,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small uppercase heading.
class NlSectionLabel extends StatelessWidget {
  const NlSectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 18, 4, 8)});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(fontSize: 11, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: t.textMuted),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// An icon in a soft circle, a title and one line of help.
class NlEmptyState extends StatelessWidget {
  const NlEmptyState({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: t.accentSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: t.accent),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.text)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades and slides its child in once, for items that just arrived.
class NlAppear extends StatelessWidget {
  const NlAppear({super.key, required this.child, this.animate = true});

  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

/// A number that counts up or down to its new value.
class NlCount extends StatelessWidget {
  const NlCount(this.value, {super.key, required this.style, this.suffix = ''});

  final int value;
  final TextStyle style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}$suffix', style: style),
    );
  }
}

/// A tappable number tile: a label, a value and a color. Used as a filter.
class NlStatTile extends StatelessWidget {
  const NlStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
    this.suffix = '',
  });

  final String label;
  final int value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return NlPressable(
      onTap: onTap,
      semanticLabel: '$label: $value$suffix',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : t.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : t.border, width: selected ? 1.5 : 1),
          boxShadow: selected ? null : t.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                // Shrinks a long label, such as "Repeated", instead of cutting it.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: t.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            NlCount(
              value,
              suffix: suffix,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: value == 0 ? t.textMuted : t.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
