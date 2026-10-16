/// NetLens: a QC-first network inspector for Flutter.
///
/// See the API calls of each screen, find what failed or was slow, and copy a
/// call as cURL for the backend team, right inside the app.
library;

export 'src/config.dart';
export 'src/export.dart' show buildHar, buildPostmanCollection, buildReportMarkdown, logsToText;
export 'src/format.dart'
    show
        NetLensInsight,
        NetLensInsightLevel,
        NetLensMasker,
        buildCurl,
        callToMarkdown,
        decodeBody,
        describeParseError,
        insightsFor,
        netLensMask;
export 'src/models.dart';
export 'src/net_lens.dart' show NetLens;
export 'src/screens.dart' show NetLensNavigatorObserver, NetLensScreen;
export 'src/sharing.dart';
export 'src/store.dart';
