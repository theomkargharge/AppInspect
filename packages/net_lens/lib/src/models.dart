/// One stay on a screen. Every call is tagged with the visit that made it.
class NetLensVisit {
  NetLensVisit({required this.id, required String name, required this.startedAt})
      : _name = name;

  final int id;
  final DateTime startedAt;
  String _name;

  /// The screen name, such as `ProductDetailsScreen`.
  String get name => _name;

  /// Screens without a route name get their real name after their first frame.
  void rename(String name) => _name = name;

  @override
  String toString() => 'NetLensVisit($id, $name)';
}

/// Where a call is in its life.
enum NetLensCallState { pending, completed, failed }

/// One captured request and its response.
///
/// Adapters such as `net_lens_dio` create calls through
/// `NetLens.store.startCall` and finish them with `completeCall` or
/// `failCall`. Bodies are stored as they arrive and formatted only when
/// someone opens the call.
class NetLensCall {
  NetLensCall({
    required this.id,
    required this.method,
    required this.uri,
    required this.requestHeaders,
    required this.startedAt,
    required this.visit,
    required this.source,
    this.requestBody,
  });

  final int id;
  final String method;
  final Uri uri;
  final Map<String, String> requestHeaders;
  final Object? requestBody;
  final DateTime startedAt;
  final NetLensVisit visit;

  /// The client that made the call, such as `Dio` or `http`.
  final String source;

  NetLensCallState state = NetLensCallState.pending;
  int? statusCode;
  Map<String, String> responseHeaders = const {};
  Object? responseBody;
  int? responseSize;

  /// True when NetLens worked out [responseSize] from a decoded JSON body,
  /// because the client didn't report one. It counts the body as compact
  /// UTF-8 JSON, which can differ a little from the bytes the server sent, so
  /// it's shown as an estimate, such as `≈ 12.3 KB`.
  bool responseSizeEstimated = false;

  DateTime? endedAt;

  /// Plain words for a failure without a response, such as `Timeout`.
  String? error;

  /// The original error message, for developers.
  String? errorDetail;

  /// How many times this call was made in a row on the same screen.
  int repeatCount = 1;

  /// True when a body was cut at `NetLensConfig.maxBodyChars`.
  bool bodyTruncated = false;

  /// Set when the app failed to read this response, even though the server
  /// answered. This is the classic "it works on my side" bug.
  NetLensParseError? parseError;

  Duration? get duration => endedAt?.difference(startedAt);
  bool get isPending => state == NetLensCallState.pending;
  bool get isRepeated => repeatCount > 1;

  /// A failure without a response, a 4xx or 5xx response, or a response the
  /// app couldn't read.
  bool get isError =>
      state == NetLensCallState.failed || (statusCode ?? 0) >= 400 || parseError != null;

  bool isSlow(Duration threshold) {
    final d = duration;
    return d != null && d > threshold;
  }

  /// The path and query, decoded for reading, for the call list.
  String get path {
    final p = uri.path.isEmpty ? '/' : uri.path;
    if (!uri.hasQuery) return p;
    try {
      return '$p?${Uri.decodeQueryComponent(uri.query)}';
    } on ArgumentError {
      return '$p?${uri.query}';
    }
  }

  /// Short status in plain words, such as `500 Server error` or `Timeout`.
  String get statusLabel {
    if (isPending) return 'Pending';
    final code = statusCode;
    if (state == NetLensCallState.failed && (code == null || code == 0)) {
      return error ?? 'Failed';
    }
    return code == null ? (error ?? 'Done') : '$code ${describeStatus(code)}';
  }

  static String describeStatus(int code) => switch (code) {
        200 => 'OK',
        201 => 'Created',
        202 => 'Accepted',
        204 => 'No content',
        301 || 308 => 'Moved',
        302 || 303 || 307 => 'Redirect',
        304 => 'Not modified',
        400 => 'Bad request',
        401 => 'Unauthorized',
        403 => 'Forbidden',
        404 => 'Not found',
        405 => 'Method not allowed',
        408 => 'Request timeout',
        409 => 'Conflict',
        413 => 'Too large',
        415 => 'Unsupported type',
        422 => 'Invalid data',
        429 => 'Too many requests',
        500 => 'Server error',
        502 => 'Bad gateway',
        503 => 'Unavailable',
        504 => 'Gateway timeout',
        _ when code >= 500 => 'Server error',
        _ when code >= 400 => 'Client error',
        _ when code >= 300 => 'Redirect',
        _ => 'OK',
      };
}

/// Why the app couldn't read a response.
class NetLensParseError {
  const NetLensParseError({
    required this.message,
    required this.stack,
    required this.time,
    this.field,
    this.likelyFields = const [],
    this.expected,
    this.got,
    this.where,
  });

  /// The error as the app saw it, such as
  /// `type 'double' is not a subtype of type 'int' in type cast`.
  final String message;

  /// The exact JSON path that failed, such as `data.items[0].price`. Known
  /// when the app parses with `NetLens.parse` or `NetLensDio.parse`.
  final String? field;

  /// Paths whose values have the wrong type, when [field] isn't known. A guess.
  final List<String> likelyFields;

  /// The type the app expected and the type it got, from a type error.
  final String? expected;
  final String? got;

  /// The app code that failed, such as `CartResult.fromJson (cart.dart:12)`.
  final String? where;

  /// The start of the stack trace.
  final String stack;
  final DateTime time;

  /// The paths to point at in the response: the exact one, or the guesses.
  List<String> get highlightPaths => field != null ? [field!] : likelyFields;
}

/// How serious a log entry is.
enum NetLensLogLevel { debug, info, warning, error }

/// One line in the logs console.
class NetLensLog {
  NetLensLog({
    required this.id,
    required this.time,
    required this.level,
    required this.message,
    required this.source,
    required this.visit,
    this.details,
    this.call,
  });

  final int id;
  final DateTime time;
  final NetLensLogLevel level;
  final String message;

  /// Where it came from, such as `debugPrint`, `Flutter error` or `Network`.
  final String source;

  /// The screen on top when it was logged.
  final NetLensVisit visit;

  /// More text, such as a stack trace.
  final String? details;

  /// The call this entry is about, if any.
  final NetLensCall? call;
}
