/// AppInspect: a QC-first network inspector for Flutter.
///
/// See the API calls of each screen, find what failed or was slow, and copy a
/// call as cURL for the backend team, right inside the app.
library;

export 'src/config.dart';
export 'src/export.dart' show buildHar, buildPostmanCollection, buildReportMarkdown, logsToText;
export 'src/format.dart'
    show
        AppInspectInsight,
        AppInspectInsightLevel,
        AppInspectMasker,
        buildCurl,
        callToMarkdown,
        decodeBody,
        describeParseError,
        insightsFor,
        appInspectMask;
export 'src/models.dart';
export 'src/app_inspect.dart' show AppInspect;
export 'src/screens.dart' show AppInspectNavigatorObserver, AppInspectScreen;
export 'src/sharing.dart';
export 'src/store.dart';
