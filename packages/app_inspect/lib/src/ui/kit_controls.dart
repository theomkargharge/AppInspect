import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kit.dart';
import 'theme.dart';

/// A segmented control whose white thumb slides to the chosen option.
class NlSegmented<T> extends StatelessWidget {
  const NlSegmented({super.key, required this.options, required this.value, required this.onChanged});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final index = options.indexWhere((o) => o.$1 == value).clamp(0, options.length - 1);
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: BorderRadius.circular(AppInspectRadius.control + 1)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: width * index,
                top: 0,
                bottom: 0,
                width: width,
                child: Container(
                  decoration: BoxDecoration(
                    color: t.raised,
                    borderRadius: BorderRadius.circular(AppInspectRadius.control - 2),
                    boxShadow: t.cardShadow,
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (i, option) in options.indexed)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (option.$1 == value) return;
                            HapticFeedback.selectionClick();
                            onChanged(option.$1);
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                color: i == index ? t.text : t.textSecondary,
                                letterSpacing: -0.1,
                              ),
                              child: Text(option.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A search field with a clear button that appears once there's text.
class NlSearchField extends StatelessWidget {
  const NlSearchField({super.key, required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 14, color: t.text),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: t.textMuted),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.cancel_rounded, size: 18, color: t.textMuted),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// One tab in [NlNavBar].
class NlNavItem {
  const NlNavItem({required this.icon, required this.label, this.badge = 0, this.key});

  final IconData icon;
  final String label;
  final int badge;
  final Key? key;
}

/// A floating tab bar whose soft highlight slides to the chosen tab.
class NlNavBar extends StatelessWidget {
  const NlNavBar({super.key, required this.items, required this.index, required this.onChanged});

  final List<NlNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return _BottomFade(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Container(
            height: 60,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: t.border),
              boxShadow: t.floatShadow,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      left: width * index,
                      top: 0,
                      bottom: 0,
                      width: width,
                      child: Container(
                        decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(17)),
                      ),
                    ),
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (final (i, item) in items.indexed)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: i == index,
                                label: item.label,
                                child: GestureDetector(
                                  key: item.key,
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    if (i == index) return;
                                    HapticFeedback.selectionClick();
                                    onChanged(i);
                                  },
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Badge(
                                          isLabelVisible: item.badge > 0,
                                          backgroundColor: t.err,
                                          label: Text('${item.badge}'),
                                          child:
                                              Icon(item.icon, size: 21, color: i == index ? t.accent : t.textSecondary),
                                        ),
                                        const SizedBox(width: 8),
                                        AnimatedDefaultTextStyle(
                                          duration: const Duration(milliseconds: 200),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                            color: i == index ? t.accent : t.textSecondary,
                                          ),
                                          child: Text(item.label),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades the page out under a floating bottom bar, so cards scrolling beneath
/// it don't show around its edges.
class _BottomFade extends StatelessWidget {
  const _BottomFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canvas = AppInspectTokens.of(context).canvas;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [canvas.withValues(alpha: 0), canvas.withValues(alpha: 0.96), canvas],
          stops: const [0, 0.38, 1],
        ),
      ),
      child: child,
    );
  }
}

/// A button that briefly turns into a check mark after it copies something.
class NlCopyButton extends StatefulWidget {
  const NlCopyButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.doneLabel = 'Copied',
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool primary;
  final String doneLabel;

  @override
  State<NlCopyButton> createState() => _NlCopyButtonState();
}

class _NlCopyButtonState extends State<NlCopyButton> {
  bool _done = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _press() async {
    await widget.onPressed();
    if (!mounted) return;
    setState(() => _done = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _done = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Row(
        key: ValueKey(_done),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_done ? Icons.check_rounded : widget.icon, size: 18),
          const SizedBox(width: 7),
          Text(_done ? widget.doneLabel : widget.label),
        ],
      ),
    );
    return widget.primary
        ? FilledButton(onPressed: _press, child: content)
        : OutlinedButton(onPressed: _press, child: content);
  }
}

/// A frosted bar that floats at the bottom of a page. Content scrolls under it.
class NlFloatingBar extends StatelessWidget {
  const NlFloatingBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return _BottomFade(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: t.floatShadow),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: t.surface.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: t.border),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded square with a soft fill and an icon.
class NlIconBadge extends StatelessWidget {
  const NlIconBadge(this.icon, {super.key, required this.color, required this.background, this.size = 38});

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// A row in a sheet or card: icon, title, subtitle and a chevron.
class NlActionTile extends StatelessWidget {
  const NlActionTile({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: NlPressable(
        onTap: enabled ? onTap : null,
        pressedScale: 0.98,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              NlIconBadge(icon, color: color, background: background),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.text)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings-style row with a switch. Tapping anywhere flips it.
class NlSwitchRow extends StatelessWidget {
  const NlSwitchRow({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return NlPressable(
      onTap: () => onChanged(!value),
      pressedScale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            NlIconBadge(icon, color: color, background: background, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: t.text)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
                    ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}

OverlayEntry? _activeToast;

/// A dark pill message that slides up, then fades away on its own.
void showNlToast(BuildContext context, String message, {IconData icon = Icons.check_circle_rounded}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final previous = _activeToast;
  _activeToast = null;
  previous?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NlToast(
      message: message,
      icon: icon,
      onDone: () {
        if (identical(_activeToast, entry)) {
          _activeToast = null;
          entry.remove();
        }
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

class _NlToast extends StatefulWidget {
  const _NlToast({required this.message, required this.icon, required this.onDone});

  final String message;
  final IconData icon;
  final VoidCallback onDone;

  @override
  State<_NlToast> createState() => _NlToastState();
}

class _NlToastState extends State<_NlToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300), reverseDuration: const Duration(milliseconds: 200));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return Positioned(
      left: 20,
      right: 20,
      bottom: 104 + MediaQuery.paddingOf(context).bottom,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(curved),
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.ink,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: t.floatShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 18, color: const Color(0xFF4ADE80)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: t.onInk,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
