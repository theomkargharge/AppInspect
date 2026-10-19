import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'config.dart';
import 'format.dart';
import 'models.dart';

/// Holds the captured calls and screen visits.
///
/// Capturing is cheap on purpose: a call is appended to a fixed-size list and
/// listeners are told at most once per frame, however many calls arrive.
class AppInspectStore extends ChangeNotifier {
  AppInspectConfig config = const AppInspectConfig();

  final List<AppInspectCall> _calls = [];
  final List<AppInspectVisit> _visits = [];
  final List<AppInspectLog> _logs = [];
  AppInspectVisit? _current;
  int _nextId = 1;
  bool _notifyScheduled = false;

  /// Size estimates already started, so each call is measured once.
  final Expando<Future<int?>> _estimates = Expando<Future<int?>>();

  /// Failures since the inspector was last opened: failed calls, responses
  /// the app couldn't read, and errors in the logs. Drives the red bubble.
  final ValueNotifier<int> unseenErrors = ValueNotifier<int>(0);

  /// Oldest first.
  List<AppInspectCall> get calls => UnmodifiableListView(_calls);

  /// Log entries, oldest first.
  List<AppInspectLog> get logs => UnmodifiableListView(_logs);

  /// Adds a line to the logs console. Errors also turn the bubble red.
  AppInspectLog addLog(
    AppInspectLogLevel level,
    String message, {
    String source = 'App',
    String? details,
    AppInspectCall? call,
  }) {
    final log = AppInspectLog(
      id: _nextId++,
      time: DateTime.now(),
      level: level,
      message: _cut(message, 4000),
      source: source,
      visit: currentVisit,
      details: details == null ? null : _cut(details, 8000),
      call: call,
    );
    _logs.add(log);
    // Drop old entries in batches, so a busy app doesn't shift the list on
    // every new line.
    if (_logs.length > config.maxLogs + 100) _logs.removeRange(0, _logs.length - config.maxLogs);
    if (level == AppInspectLogLevel.error) unseenErrors.value++;
    _scheduleNotify();
    return log;
  }

  /// Marks [call] as a response the app couldn't read, and logs it.
  void attachParseError(AppInspectCall call, AppInspectParseError error) {
    call.parseError = error;
    final where = error.field ?? (error.likelyFields.isEmpty ? null : 'likely ${error.likelyFields.first}');
    addLog(
      AppInspectLogLevel.error,
      'Couldn\'t read the response of ${call.method} ${_maskedPath(call)}'
      '${where == null ? '' : ' at $where'}: ${error.message}',
      source: 'Parse error',
      details: error.stack,
      call: call,
    );
  }

  void clearLogs() {
    _logs.clear();
    _scheduleNotify();
  }

  /// Screen visits, oldest first.
  List<AppInspectVisit> get visits => UnmodifiableListView(_visits);

  /// The screen on top right now. Calls started now are tagged with it.
  AppInspectVisit get currentVisit => _current ??= _addVisit('App');

  /// Starts a new visit, for a new route or a tab switch.
  AppInspectVisit startVisit(String name) {
    final visit = _addVisit(name);
    _current = visit;
    _scheduleNotify();
    return visit;
  }

  /// Goes back to an earlier visit, when a route is popped.
  void resumeVisit(AppInspectVisit visit) {
    if (identical(_current, visit)) return;
    _current = visit;
    _scheduleNotify();
  }

  /// Records the start of a request and returns the call to finish later.
  AppInspectCall startCall({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    Object? body,
    String source = 'custom',
  }) {
    final visit = currentVisit;
    final now = DateTime.now();
    final call = AppInspectCall(
      id: _nextId++,
      method: method.toUpperCase(),
      uri: uri,
      requestHeaders: Map.unmodifiable(headers),
      requestBody: _limit(body, (cut) {}),
      startedAt: now,
      visit: visit,
      source: source,
    );
    _markRepeats(call, now);
    _calls.add(call);
    if (_calls.length > config.maxCalls) {
      _calls.removeRange(0, _calls.length - config.maxCalls);
    }
    _scheduleNotify();
    return call;
  }

  /// Records a response. 4xx and 5xx responses count as errors.
  void completeCall(
    AppInspectCall call, {
    required int statusCode,
    Map<String, String> headers = const {},
    Object? body,
    int? size,
  }) {
    if (!call.isPending) return;
    call
      ..state = AppInspectCallState.completed
      ..statusCode = statusCode
      ..responseHeaders = Map.unmodifiable(headers)
      ..responseBody = _limit(body, (cut) => call.bodyTruncated = cut)
      ..responseSize = size ?? _sizeOf(body)
      ..endedAt = DateTime.now();
    if (call.isError) {
      unseenErrors.value++;
      _logFailure(call);
    }
    _scheduleNotify();
  }

  /// Records a call that failed. [error] is shown as is, so use plain words
  /// such as `Timeout` or `No connection`. Pass [statusCode] and [body] when
  /// the server did answer.
  void failCall(
    AppInspectCall call, {
    required String error,
    String? detail,
    int? statusCode,
    Map<String, String> headers = const {},
    Object? body,
  }) {
    if (!call.isPending) return;
    call
      ..state = AppInspectCallState.failed
      ..error = error
      ..errorDetail = detail
      ..statusCode = statusCode
      ..responseHeaders = Map.unmodifiable(headers)
      ..responseBody = _limit(body, (cut) => call.bodyTruncated = cut)
      ..responseSize = _sizeOf(body)
      ..endedAt = DateTime.now();
    unseenErrors.value++;
    _logFailure(call);
    _scheduleNotify();
  }

  /// Records a call the app cancelled on purpose, such as a search that was
  /// typed over or a screen that closed. It shows as `Cancelled` and doesn't
  /// count as a failure, so the bubble stays calm.
  void cancelCall(AppInspectCall call, {String? detail}) {
    if (!call.isPending) return;
    call
      ..state = AppInspectCallState.failed
      ..cancelled = true
      ..error = 'Cancelled'
      ..errorDetail = detail
      ..endedAt = DateTime.now();
    _scheduleNotify();
  }

  void _logFailure(AppInspectCall call) => addLog(
        AppInspectLogLevel.warning,
        '${call.method} ${_maskedPath(call)} → ${call.statusLabel}',
        source: 'Network',
        call: call,
      );

  /// Log lines are written once, so a token in the URL is always masked
  /// there. The call itself keeps it, for a developer to see in Settings.
  String _maskedPath(AppInspectCall call) => AppInspectMasker(config).path(call);

  /// Fills in [AppInspectCall.responseSize] when the client handed over decoded
  /// JSON without a size, such as a Dio response that came compressed or in
  /// chunks, with no Content-Length header.
  ///
  /// The inspector calls this when someone opens the call, so capturing never
  /// pays for it: the body is written out as compact JSON on another isolate
  /// and its UTF-8 bytes are counted. The size is marked
  /// [AppInspectCall.responseSizeEstimated], and listeners are told, so the call
  /// list shows it too.
  ///
  /// Returns the call's size, or null when it can't be worked out.
  Future<int?> estimateResponseSize(AppInspectCall call) {
    if (call.isPending || call.responseSize != null) return Future<int?>.value(call.responseSize);
    return _estimates[call] ??= jsonSizeAsync(call.responseBody).then((size) {
      if (size != null && call.responseSize == null) {
        call
          ..responseSize = size
          ..responseSizeEstimated = true;
        _scheduleNotify();
      }
      return call.responseSize;
    });
  }

  /// Calls made during [visit], oldest first.
  List<AppInspectCall> callsFor(AppInspectVisit visit) => _calls.where((c) => identical(c.visit, visit)).toList();

  void markErrorsSeen() => unseenErrors.value = 0;

  /// Tells listeners on the next frame, for example after a visit is renamed.
  void refresh() => _scheduleNotify();

  void clear() {
    _calls.clear();
    unseenErrors.value = 0;
    _scheduleNotify();
  }

  /// Tells listeners right away. Useful in tests.
  @visibleForTesting
  void flush() {
    _notifyScheduled = false;
    notifyListeners();
  }

  AppInspectVisit _addVisit(String name) {
    final visit = AppInspectVisit(id: _nextId++, name: name, startedAt: DateTime.now());
    _visits.add(visit);
    if (_visits.length > config.maxCalls) _visits.removeAt(0);
    return visit;
  }

  void _markRepeats(AppInspectCall call, DateTime now) {
    final same = <AppInspectCall>[];
    for (var i = _calls.length - 1; i >= 0; i--) {
      final c = _calls[i];
      if (now.difference(c.startedAt) > config.repeatWindow) break;
      if (identical(c.visit, call.visit) && c.method == call.method && c.uri == call.uri) {
        same.add(c);
      }
    }
    if (same.isEmpty) return;
    final count = same.length + 1;
    for (final c in same) {
      c.repeatCount = count;
    }
    call.repeatCount = count;
  }

  static String _cut(String text, int max) => text.length <= max ? text : '${text.substring(0, max)}…';

  Object? _limit(Object? body, void Function(bool cut) onCut) {
    if (body is String && body.length > config.maxBodyChars) {
      onCut(true);
      return body.substring(0, config.maxBodyChars);
    }
    return body;
  }

  static int? _sizeOf(Object? body) => switch (body) {
        String s => s.length,
        List<int> b => b.length,
        _ => null,
      };

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } catch (_) {
      // Too early, for example a print before runApp. Nothing listens yet.
      return;
    }
    _notifyScheduled = true;
    binding.addPostFrameCallback((_) {
      if (!_notifyScheduled) return;
      _notifyScheduled = false;
      notifyListeners();
    });
    binding.ensureVisualUpdate();
  }

  @override
  void dispose() {
    unseenErrors.dispose();
    super.dispose();
  }
}
