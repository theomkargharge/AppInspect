import 'models.dart';

/// One moment in the session timeline: a move to a screen, a call or a line
/// in the logs.
sealed class TimelineEntry {
  const TimelineEntry();

  DateTime get time;

  /// The screen on top at that moment.
  AppInspectVisit get visit;

  /// Whether QC should look at it: a failed or slow call, or a warning or
  /// error in the logs.
  bool isProblem(Duration slowThreshold);
}

final class ScreenEntry extends TimelineEntry {
  const ScreenEntry(this.change);

  final AppInspectScreenChange change;

  @override
  DateTime get time => change.time;

  @override
  AppInspectVisit get visit => change.visit;

  @override
  bool isProblem(Duration slowThreshold) => false;
}

final class CallEntry extends TimelineEntry {
  const CallEntry(this.call);

  final AppInspectCall call;

  @override
  DateTime get time => call.startedAt;

  @override
  AppInspectVisit get visit => call.visit;

  @override
  bool isProblem(Duration slowThreshold) => call.isError || call.isSlow(slowThreshold);
}

final class LogEntry extends TimelineEntry {
  const LogEntry(this.log);

  final AppInspectLog log;

  @override
  DateTime get time => log.time;

  @override
  AppInspectVisit get visit => log.visit;

  @override
  bool isProblem(Duration slowThreshold) => log.level.index >= AppInspectLogLevel.warning.index;
}

/// The session in order, oldest first: the screens people moved to, the
/// calls each made and the lines in the logs.
///
/// Log lines about a call, such as a failed call or a response the app
/// couldn't read, are left out: the call itself shows what went wrong.
List<TimelineEntry> buildTimeline({
  required List<AppInspectScreenChange> screens,
  required List<AppInspectCall> calls,
  required List<AppInspectLog> logs,
}) {
  final shownLogs = [
    for (final log in logs)
      if (log.call == null) log,
  ];
  // Each list is oldest first already, so merging keeps the order. When two
  // happen at the same moment, the screen comes first, then its call.
  final out = <TimelineEntry>[];
  var s = 0, c = 0, l = 0;
  while (s < screens.length || c < calls.length || l < shownLogs.length) {
    final screen = s < screens.length ? screens[s].time : null;
    final call = c < calls.length ? calls[c].startedAt : null;
    final log = l < shownLogs.length ? shownLogs[l].time : null;
    bool first(DateTime? a, DateTime? b, DateTime? d) =>
        a != null && (b == null || !b.isBefore(a)) && (d == null || !d.isBefore(a));
    if (first(screen, call, log)) {
      out.add(ScreenEntry(screens[s++]));
    } else if (first(call, null, log)) {
      out.add(CallEntry(calls[c++]));
    } else {
      out.add(LogEntry(shownLogs[l++]));
    }
  }
  return out;
}

/// The time from one entry to the next, such as `+120 ms`, `+1.4 s` or
/// `+3 min`. Empty when they happened at the same moment.
String formatGap(Duration gap) {
  final ms = gap.inMilliseconds;
  if (ms <= 0) return '';
  if (ms < 1000) return '+$ms ms';
  if (ms < 60000) return '+${(ms / 1000).toStringAsFixed(1)} s';
  if (ms < 3600000) return '+${gap.inMinutes} min';
  return '+${gap.inHours} h';
}
