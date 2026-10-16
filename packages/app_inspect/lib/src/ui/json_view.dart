import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../format.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'theme.dart';
import 'widgets.dart';

/// A foldable JSON tree, built lazily as a sliver.
///
/// Only the lines on screen are built, so a large response doesn't create a
/// widget per value. Big containers start folded. Tap a value to copy it or
/// its path, such as `data.items[0].price`.
class JsonSliver extends StatefulWidget {
  const JsonSliver({super.key, required this.data, this.highlight = const {}});

  /// Decoded JSON: a map, a list or a single value.
  final Object? data;

  /// Paths to mark in red, such as the field that broke parsing. Folded
  /// containers around them start open.
  final Set<String> highlight;

  @override
  State<JsonSliver> createState() => _JsonSliverState();
}

sealed class _Line {
  const _Line(this.depth);
  final int depth;
}

class _OpenLine extends _Line {
  const _OpenLine(super.depth, this.path, this.label, this.isList, this.size, this.folded, this.isLast);
  final String path;
  final String? label;
  final bool isList;
  final int size;
  final bool folded;
  final bool isLast;
}

class _CloseLine extends _Line {
  const _CloseLine(super.depth, this.isList, this.isLast);
  final bool isList;
  final bool isLast;
}

class _ValueLine extends _Line {
  const _ValueLine(super.depth, this.path, this.label, this.value, this.isLast);
  final String path;
  final String? label;
  final Object? value;
  final bool isLast;
}

class _JsonSliverState extends State<JsonSliver> {
  final Set<String> _toggled = {};
  List<_Line> _lines = const [];

  @override
  void initState() {
    super.initState();
    _rebuildLines();
  }

  @override
  void didUpdateWidget(JsonSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _toggled.clear();
      _rebuildLines();
    } else if (!setEquals(oldWidget.highlight, widget.highlight)) {
      _rebuildLines();
    }
  }

  /// Small, shallow containers start open. Deep or long ones start folded,
  /// unless a highlighted path is inside them.
  bool _folded(String path, int depth, int size) {
    final holdsHighlight = widget.highlight.any(
      (h) => path.isEmpty || h == path || h.startsWith('$path.') || h.startsWith('$path[') || h.startsWith('$path["'),
    );
    final byDefault = !(holdsHighlight || depth < 2 || (depth < 4 && size <= 20));
    return byDefault != _toggled.contains(path);
  }

  void _toggle(String path) {
    setState(() {
      if (!_toggled.remove(path)) _toggled.add(path);
      _rebuildLines();
    });
  }

  void _rebuildLines() {
    final out = <_Line>[];
    void walk(Object? value, String path, String? label, int depth, bool isLast) {
      if (value is Map || value is List) {
        final isList = value is List;
        final entries = value is Map
            ? value.entries.map((e) => (e.key.toString(), e.value)).toList()
            : [for (final (i, v) in (value as List).indexed) ('$i', v)];
        final folded = entries.isNotEmpty && _folded(path, depth, entries.length);
        out.add(_OpenLine(depth, path, label, isList, entries.length, folded, isLast));
        if (folded || entries.isEmpty) return;
        for (final (i, (key, child)) in entries.indexed) {
          final childPath = isList ? '$path[$key]' : joinJsonPath(path, key);
          walk(child, childPath, isList ? null : key, depth + 1, i == entries.length - 1);
        }
        out.add(_CloseLine(depth, isList, isLast));
      } else {
        out.add(_ValueLine(depth, path, label, value, isLast));
      }
    }

    walk(widget.data, '', null, 0, true);
    _lines = out;
  }

  Object? _valueAt(String path) {
    Object? node = widget.data;
    final parts = RegExp(r'\["((?:[^"\\]|\\.)*)"\]|\[(\d+)\]|([^.\[\]]+)').allMatches(path);
    for (final m in parts) {
      final quoted = m.group(1), index = m.group(2), plain = m.group(3);
      if (index != null && node is List) {
        node = node[int.parse(index)];
      } else if (node is Map) {
        node = node[quoted?.replaceAll(r'\"', '"') ?? plain];
      } else {
        return null;
      }
    }
    return node;
  }

  void _showValueActions(String path) {
    final value = _valueAt(path);
    final text = value is String ? value : encodeBody(value);
    final shownPath = path.isEmpty ? '(root)' : path;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        final t = AppInspectTokens.of(sheet);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(shownPath,
                      style: appInspectMono.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: NlCard(
                    color: t.codeBg,
                    shadow: false,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      text.length > 400 ? '${text.substring(0, 400)}…' : text,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: appInspectMono.copyWith(fontSize: 12.5, color: t.text),
                    ),
                  ),
                ),
                NlActionTile(
                  icon: Icons.copy_rounded,
                  color: t.accent,
                  background: t.accentSoft,
                  title: 'Copy value',
                  onTap: () {
                    Navigator.pop(sheet);
                    copyText(context, text, 'Value copied');
                  },
                ),
                NlActionTile(
                  icon: Icons.alt_route_rounded,
                  color: t.violet,
                  background: t.violetSoft,
                  title: 'Copy path',
                  subtitle: shownPath,
                  onTap: () {
                    Navigator.pop(sheet);
                    copyText(context, shownPath, 'Path copied: $shownPath');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return SliverList.builder(
      itemCount: _lines.length,
      itemBuilder: (context, i) => _buildLine(_lines[i], t),
    );
  }

  Widget _buildLine(_Line line, AppInspectTokens t) {
    TextSpan keySpan(String? label) => label == null
        ? const TextSpan()
        : TextSpan(children: [
            TextSpan(text: '"$label"', style: TextStyle(color: t.jsonKey, fontWeight: FontWeight.w600)),
            TextSpan(text: ': ', style: TextStyle(color: t.textMuted)),
          ]);
    final punctuation = TextStyle(color: t.textMuted);
    final style = appInspectMono.copyWith(color: t.text);
    switch (line) {
      case _OpenLine():
        final open = line.isList ? '[' : '{';
        final close = line.isList ? ']' : '}';
        final empty = line.size == 0;
        return _paint(
          line.depth,
          line.path,
          t,
          onTap: empty ? null : () => _toggle(line.path),
          onLongPress: () => _showValueActions(line.path),
          lead: empty
              ? null
              : AnimatedRotation(
                  turns: line.folded ? -0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded, size: 17, color: t.textMuted),
                ),
          text: Text.rich(
            TextSpan(children: [
              keySpan(line.label),
              TextSpan(text: open, style: punctuation),
              if (empty) TextSpan(text: close + (line.isLast ? '' : ','), style: punctuation),
              if (line.folded) ...[
                const TextSpan(text: ' '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: NlPill(
                    label: '${line.size} ${line.isList ? 'items' : 'keys'}',
                    foreground: t.textSecondary,
                    background: t.surfaceAlt,
                  ),
                ),
                TextSpan(text: ' $close${line.isLast ? '' : ','}', style: punctuation),
              ],
            ]),
            style: style,
          ),
        );
      case _CloseLine():
        return _paint(
          line.depth,
          null,
          t,
          text: Text((line.isList ? ']' : '}') + (line.isLast ? '' : ','), style: style.copyWith(color: t.textMuted)),
        );
      case _ValueLine():
        final v = line.value;
        final (shown, color) = switch (v) {
          null => ('null', t.jsonLiteral),
          bool b => ('$b', t.jsonLiteral),
          num n => ('$n', t.jsonNumber),
          String s => ('"${s.length > 300 ? '${s.substring(0, 300)}…' : s}"', s == appInspectMask ? t.textMuted : t.jsonString),
          _ => (v.toString(), t.textMuted),
        };
        final failed = widget.highlight.contains(line.path);
        return _paint(
          line.depth,
          line.path,
          t,
          onTap: () => _showValueActions(line.path),
          text: Text.rich(
            TextSpan(children: [
              keySpan(line.label),
              TextSpan(text: shown, style: TextStyle(color: color)),
              TextSpan(text: line.isLast ? '' : ',', style: punctuation),
              if (failed) ...[
                const TextSpan(text: '  '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: NlPill(label: 'failed here', foreground: t.onAccent, background: t.err),
                ),
              ],
            ]),
            style: style,
          ),
        );
    }
  }

  /// One line: indent guides and, for a highlighted path, a red band are
  /// painted behind it, so the text never shifts.
  Widget _paint(
    int depth,
    String? path,
    AppInspectTokens t, {
    required Widget text,
    Widget? lead,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final marked = path != null && widget.highlight.contains(path);
    return CustomPaint(
      painter: _LinePainter(
        depth: depth,
        guide: t.border,
        band: marked ? t.errSoft : null,
        bar: marked ? t.err : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: EdgeInsets.fromLTRB(_gutter + depth * _step, 0, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 18, height: 21, child: lead),
                Expanded(child: text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const double _gutter = 12;
const double _step = 16;

class _LinePainter extends CustomPainter {
  _LinePainter({required this.depth, required this.guide, this.band, this.bar});

  final int depth;
  final Color guide;
  final Color? band;
  final Color? bar;

  @override
  void paint(Canvas canvas, Size size) {
    final band = this.band, bar = this.bar;
    if (band != null && bar != null) {
      final rect = RRect.fromLTRBR(6, 1, size.width - 6, size.height - 1, const Radius.circular(8));
      canvas
        ..drawRRect(rect, Paint()..color = band)
        ..save()
        ..clipRRect(rect)
        ..drawRect(Rect.fromLTWH(6, 0, 3, size.height), Paint()..color = bar)
        ..restore();
    }
    final line = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (var i = 0; i < depth; i++) {
      final x = _gutter + i * _step + 9;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.depth != depth || old.guide != guide || old.band != band || old.bar != bar;
}
