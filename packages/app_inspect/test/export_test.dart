import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect/src/version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const masker = AppInspectMasker(AppInspectConfig());
  late AppInspectStore store;
  late AppInspectCall login;
  late AppInspectCall timeout;

  setUp(() {
    store = AppInspectStore()..startVisit('LoginScreen');
    login = store.startCall(
      method: 'POST',
      uri: Uri.parse('https://api.test/login?source=app'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer abcdefghijkl'},
      body: {'username': 'qa', 'password': 'hunter2'},
    );
    store.completeCall(login, statusCode: 200, body: '{"accessToken":"secret","name":"QA"}');
    timeout = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/slow'));
    store.failCall(timeout, error: 'Timeout');
    store.startCall(method: 'GET', uri: Uri.parse('https://api.test/pending'));
  });

  test('HAR has every finished call, masked', () {
    final har = jsonDecode(buildHar(store.calls, masker)) as Map<String, dynamic>;
    final log = har['log'] as Map<String, dynamic>;
    final entries = log['entries'] as List<dynamic>;

    expect(log['version'], '1.2');
    expect(entries, hasLength(2), reason: 'the pending call is skipped');

    final first = entries[0] as Map<String, dynamic>;
    final request = first['request'] as Map<String, dynamic>;
    expect(request['method'], 'POST');
    expect(request['url'], 'https://api.test/login?source=app');
    expect(request['headers'], contains(equals({'name': 'authorization', 'value': 'Bearer abcd$appInspectMask'})));
    expect(request['queryString'], [
      {'name': 'source', 'value': 'app'},
    ]);
    expect((request['postData'] as Map)['text'], isNot(contains('hunter2')));
    final response = first['response'] as Map<String, dynamic>;
    expect(response['status'], 200);
    expect((response['content'] as Map)['text'], isNot(contains('secret')));
    expect(first['_screen'], 'LoginScreen');

    final second = entries[1] as Map<String, dynamic>;
    expect((second['response'] as Map)['status'], 0);
    expect((second['response'] as Map)['statusText'], 'Timeout');
    expect(second['_issue'], 'Timeout');
  });

  test('Postman collection repeats the request, masked', () {
    final collection = jsonDecode(buildPostmanCollection([login], masker, name: 'Login')) as Map<String, dynamic>;

    expect((collection['info'] as Map)['schema'], contains('v2.1.0'));
    final item = (collection['item'] as List).single as Map<String, dynamic>;
    expect(item['name'], 'POST /login?source=app');
    final request = item['request'] as Map<String, dynamic>;
    expect(request['url'], 'https://api.test/login?source=app');
    expect(request['header'], contains(equals({'key': 'authorization', 'value': 'Bearer abcd$appInspectMask'})));
    expect((request['body'] as Map)['raw'], allOf(contains('"username":"qa"'), isNot(contains('hunter2'))));
  });

  test('logs as text, with stack traces indented', () {
    final log = store.addLog(AppInspectLogLevel.error, 'Boom', source: 'Flutter error', details: '#0 main\n#1 run');

    final text = logsToText([log]);

    expect(text, contains('E [Flutter error] LoginScreen: Boom'));
    expect(text, contains('    #0 main\n    #1 run'));
  });

  test('bug report Markdown has the note, info, calls, failures and logs', () {
    final warning = store.logs.firstWhere((l) => l.source == 'Network');

    final md = buildReportMarkdown(
      screen: login.visit,
      note: 'Sign in spins forever.',
      calls: [login, timeout],
      logs: [warning],
      info: {'App': 'Kartly 2.3.1 (231)'},
      masker: masker,
      slowThreshold: const Duration(seconds: 1),
      now: DateTime(2026, 10, 16, 10, 30),
    );

    expect(md, startsWith('## Bug on LoginScreen'));
    expect(md, contains('Sign in spins forever.'));
    expect(md, contains('- **App:** Kartly 2.3.1 (231)'));
    expect(md, contains('- **Reported:** 2026-10-16 10:30:00'));
    expect(md, contains('| `POST /login?source=app` | 200 OK |'));
    expect(md, contains('#### GET /slow · Timeout'));
    expect(md, contains("curl -X GET 'https://api.test/slow'"));
    expect(md, contains('### Errors and warnings'));
    expect(md, isNot(contains('hunter2')));
  });

  test('a token in the URL is masked in every export and in the logs', () {
    final feed = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/feed?access_token=SECRET&page=1'));
    store.completeCall(feed, statusCode: 500, body: '{}');

    final exports = [
      buildCurl(feed, masker),
      buildHar([feed], masker),
      buildPostmanCollection([feed], masker, name: 'Feed'),
      callToMarkdown(feed, masker, slowThreshold: const Duration(seconds: 1)),
      store.logs.last.message,
    ];
    for (final text in exports) {
      expect(text, isNot(contains('SECRET')));
    }
    expect(store.logs.last.message, 'GET /feed?access_token=$appInspectMask&page=1 → 500 Server error');

    final har = jsonDecode(buildHar([feed], masker)) as Map<String, dynamic>;
    final request = ((har['log'] as Map)['entries'] as List).single['request'] as Map<String, dynamic>;
    expect(request['queryString'], [
      {'name': 'access_token', 'value': appInspectMask},
      {'name': 'page', 'value': '1'},
    ]);
  });

  test('the version in exports and Settings is the one in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(pubspec)!.group(1), appInspectVersion);
    expect(buildHar(const [], masker), contains('"version": "$appInspectVersion"'));
  });
}
