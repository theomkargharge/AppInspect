import 'dart:collection';

import 'format.dart';
import 'models.dart';

/// Remembers the last JSON path the app read while parsing.
class JsonReadTracker {
  String? lastPath;
}

/// Wraps decoded JSON so every read records its path. When `fromJson`
/// throws, the last path read is the field that broke it.
Object? trackJson(Object? value, String path, JsonReadTracker tracker) => switch (value) {
      Map<dynamic, dynamic> m => _TrackingMap(m, path, tracker),
      List<dynamic> l => _TrackingList(l, path, tracker),
      _ => value,
    };

class _TrackingMap extends MapBase<String, dynamic> {
  _TrackingMap(this._inner, this._path, this._tracker);

  final Map<dynamic, dynamic> _inner;
  final String _path;
  final JsonReadTracker _tracker;

  @override
  dynamic operator [](Object? key) {
    final path = joinJsonPath(_path, '$key');
    _tracker.lastPath = path;
    return trackJson(_inner[key], path, _tracker);
  }

  @override
  void operator []=(String key, dynamic value) => _inner[key] = value;

  @override
  bool containsKey(Object? key) => _inner.containsKey(key);

  @override
  int get length => _inner.length;

  @override
  Iterable<String> get keys => _inner.keys.map((k) => '$k');

  @override
  dynamic remove(Object? key) => _inner.remove(key);

  @override
  void clear() => _inner.clear();
}

class _TrackingList extends ListBase<dynamic> {
  _TrackingList(this._inner, this._path, this._tracker);

  final List<dynamic> _inner;
  final String _path;
  final JsonReadTracker _tracker;

  @override
  int get length => _inner.length;

  @override
  set length(int value) => _inner.length = value;

  @override
  dynamic operator [](int index) {
    final path = '$_path[$index]';
    _tracker.lastPath = path;
    return trackJson(_inner[index], path, _tracker);
  }

  @override
  void operator []=(int index, dynamic value) => _inner[index] = value;
}

final RegExp _typeError = RegExp(r"type '(.+?)' is not a subtype of type '(.+?)'");
final RegExp _frame = RegExp(r'^#\d+\s+(.+?) \((package:[^/]+/(?:[^)]*/)?([^/)]+\.dart)):(\d+)(?::\d+)?\)');

/// Packages whose frames aren't the app's own code.
const List<String> _libraryPackages = [
  'package:flutter/',
  'package:net_lens/',
  'package:net_lens_dio/',
  'package:net_lens_http/',
  'package:dio/',
  'package:http/',
  'package:retrofit/',
  'package:json_annotation/',
];

/// Builds a [NetLensParseError] from what the app threw.
///
/// When [field] isn't known, it looks through [responseBody] for values of
/// the type the app got instead of the one it expected, and lists up to three.
NetLensParseError buildParseError(Object error, StackTrace stack, {String? field, Object? responseBody}) {
  final message = error.toString().replaceFirst(RegExp(r'^(TypeError|_TypeError|Error): '), '');
  final match = _typeError.firstMatch(message);
  final got = match?.group(1);
  final expected = match?.group(2);

  final lines = stack.toString().split('\n').where((l) => l.trim().isNotEmpty).toList();
  String? where;
  for (final line in lines) {
    final m = _frame.firstMatch(line.trim());
    if (m == null || _libraryPackages.any(m.group(2)!.startsWith)) continue;
    // Constructors show up as "new CartResult.fromJson".
    where = '${m.group(1)!.replaceFirst(RegExp(r'^new '), '')} (${m.group(3)}:${m.group(4)})';
    break;
  }

  final likely = field == null && got != null ? _likelyFields(decodeBody(responseBody), got, expected) : const <String>[];
  return NetLensParseError(
    message: message,
    field: field,
    likelyFields: likely,
    expected: expected,
    got: got,
    where: where,
    stack: lines.take(12).join('\n'),
    time: DateTime.now(),
  );
}

/// Paths whose value has the type the app got by mistake, shallowest first.
List<String> _likelyFields(Object? json, String got, String? expected) {
  bool matches(Object? v) => switch (got) {
        'Null' => v == null,
        'String' => v is String && (expected == null || !_isText(expected) || v.isEmpty),
        'int' => v is int,
        'double' => v is double,
        'bool' => v is bool,
        _ when got.startsWith('List') => v is List,
        _ when got.contains('Map') => v is Map,
        _ => false,
      };
  final found = <(int, String)>[];
  void walk(Object? v, String path, int depth) {
    if (found.length > 50 || depth > 12) return;
    if (path.isNotEmpty && matches(v)) found.add((depth, path));
    if (v is Map) {
      v.forEach((k, child) => walk(child, joinJsonPath(path, '$k'), depth + 1));
    } else if (v is List) {
      for (var i = 0; i < v.length && i < 20; i++) {
        walk(v[i], '$path[$i]', depth + 1);
      }
    }
  }

  walk(json, '', 0);
  // A wrong-type string that looks like a number is the most likely culprit.
  if (got == 'String' && expected != null && _isNumber(expected)) {
    final numeric = found.where((f) => num.tryParse('${_valueAt(json, f.$2)}') != null).toList();
    if (numeric.isNotEmpty) {
      found
        ..clear()
        ..addAll(numeric);
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found.take(3)) f.$2];
}

bool _isText(String type) => type == 'String';
bool _isNumber(String type) => type == 'int' || type == 'double' || type == 'num';

Object? _valueAt(Object? json, String path) {
  Object? node = json;
  for (final m in RegExp(r'\["((?:[^"\\]|\\.)*)"\]|\[(\d+)\]|([^.\[\]]+)').allMatches(path)) {
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
