import 'package:flutter/foundation.dart';

import 'sharing.dart';

/// Settings for NetLens. Pass them to `NetLens.wrap`.
@immutable
class NetLensConfig {
  const NetLensConfig({
    this.maxCalls = 300,
    this.maxLogs = 1000,
    this.maxBodyChars = 500000,
    this.slowThreshold = const Duration(seconds: 1),
    this.repeatWindow = const Duration(milliseconds: 1500),
    this.maskedHeaders = defaultMaskedHeaders,
    this.maskedBodyKeys = defaultMaskedBodyKeys,
    this.showBubble = true,
    this.captureLogs = true,
    this.pin,
    this.onShare,
    this.onReport,
    this.reportInfo,
    this.darkTheme = false,
  });

  /// How many calls to keep. Older calls are dropped first.
  final int maxCalls;

  /// How many log entries to keep. Older entries are dropped first.
  final int maxLogs;

  /// Capture `debugPrint`, Flutter errors and uncaught errors in the logs
  /// console. To capture `print` too, start the app with `NetLens.runZoned`.
  final bool captureLogs;

  /// Sends a bug report somewhere. See [NetLensReportCallback].
  final NetLensReportCallback? onReport;

  /// Extra lines for bug reports, such as the app version, flavor and user ID.
  /// Called each time a report is built.
  final Map<String, String> Function()? reportInfo;

  /// Text bodies longer than this are cut, so a big download can't fill memory.
  final int maxBodyChars;

  /// Calls slower than this are flagged as slow.
  final Duration slowThreshold;

  /// The same call made again within this window, on the same screen, is
  /// flagged as repeated. That usually means an API call inside `build()`.
  final Duration repeatWindow;

  /// Header names (lowercase) whose values are masked on screen and in exports.
  final Set<String> maskedHeaders;

  /// JSON keys (lowercase) whose values are masked on screen and in exports.
  final Set<String> maskedBodyKeys;

  /// Show the floating bubble. Turn it off to open NetLens only with
  /// `NetLens.open()`, for example from a hidden gesture.
  final bool showBubble;

  /// When set, NetLens asks for this PIN once per app session before it
  /// opens. Use it for UAT builds you hand to people outside the team.
  final String? pin;

  /// Share handler. See [NetLensShareCallback].
  final NetLensShareCallback? onShare;

  /// Start the inspector in its dark theme instead of the light one. People
  /// can switch it in Settings.
  final bool darkTheme;

  static const Set<String> defaultMaskedHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
  };

  static const Set<String> defaultMaskedBodyKeys = {
    'password',
    'passwd',
    'token',
    'accesstoken',
    'access_token',
    'refreshtoken',
    'refresh_token',
    'idtoken',
    'id_token',
    'otp',
    'pin',
    'cvv',
    'cardnumber',
    'card_number',
    'secret',
    'apikey',
    'api_key',
  };
}
