import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect/src/format.dart' show formatRequestSize;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const masker = AppInspectMasker(AppInspectConfig());

  test('masks a bearer token but keeps its start', () {
    expect(masker.header('Authorization', 'Bearer abcdefghijklmnop'), 'Bearer abcd$appInspectMask');
    expect(masker.header('cookie', 'session=1'), appInspectMask);
    expect(masker.header('Accept', 'application/json'), 'application/json');
  });

  test('masks sensitive JSON keys at any depth', () {
    final masked = masker.json({
      'user': {'name': 'Asha', 'password': 'hunter2'},
      'sessions': [
        {'accessToken': 'abc', 'device': 'Pixel 7'},
      ],
    });

    expect(masked, {
      'user': {'name': 'Asha', 'password': appInspectMask},
      'sessions': [
        {'accessToken': appInspectMask, 'device': 'Pixel 7'},
      ],
    });
  });

  test('shows real values when masking is off', () {
    const off = AppInspectMasker(AppInspectConfig(), enabled: false);
    expect(off.header('Authorization', 'Bearer abcdefghijklmnop'), 'Bearer abcdefghijklmnop');
    expect(off.json({'password': 'p'}), {'password': 'p'});
  });

  test('builds a cURL command that repeats the call', () {
    final store = AppInspectStore();
    final call = store.startCall(
      method: 'POST',
      uri: Uri.parse('https://api.test/cart?x=1'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer secret-token-123'},
      body: {'id': 1, 'note': "it's", 'password': 'hunter2'},
    );

    final curl = buildCurl(call, masker);

    expect(curl, startsWith("curl -X POST 'https://api.test/cart?x=1'"));
    expect(curl, contains("-H 'content-type: application/json'"));
    expect(curl, contains("-H 'authorization: Bearer secr$appInspectMask'"));
    expect(curl, contains(r"it'\''s"));
    expect(curl, isNot(contains('hunter2')));
  });

  test('decodes JSON text and leaves other text alone', () {
    expect(decodeBody('{"a":[1,2]}'), {
      'a': [1, 2],
    });
    expect(decodeBody('plain text'), 'plain text');
    expect(decodeBody('{not json'), '{not json');
    expect(decodeBody(<int>[1, 2, 3]), '<3 bytes of binary data>');
  });

  test('sizes a request body in UTF-8 bytes, and decoded JSON as an estimate', () async {
    expect(await formatRequestSize(null), '—');
    // Text and binary data are sized at once, so the size is there on the
    // first frame. The accent takes two bytes.
    expect(formatRequestSize('Crème'), isA<SynchronousFuture<String>>());
    expect(await formatRequestSize('Crème'), '6 B');
    expect(await formatRequestSize(<int>[1, 2, 3]), '3 B');
    // {"name":"Crème"}, written out on another isolate.
    expect(await formatRequestSize({'name': 'Crème'}), '≈ 17 B');
  });

  test('explains problems in plain words', () {
    final store = AppInspectStore();
    const slowLimit = Duration(seconds: 1);

    final server = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/a'));
    store.completeCall(server, statusCode: 503);
    expect(insightsFor(server, slowThreshold: slowLimit).first.title, 'Server error');

    final offline = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/b'));
    store.failCall(offline, error: 'No connection');
    expect(insightsFor(offline, slowThreshold: slowLimit).first.title, 'Couldn\'t reach the server');

    final repeated = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/b'));
    expect(insightsFor(repeated, slowThreshold: slowLimit).map((i) => i.title), contains('Called 2 times in a row'));
  });

  test('writes a Markdown summary for sharing', () {
    final store = AppInspectStore()..startVisit('CartScreen');
    final call = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/cart'));
    store.completeCall(call, statusCode: 500, body: '{"error":"down"}');

    final md = callToMarkdown(call, masker, slowThreshold: const Duration(seconds: 1));

    expect(md, startsWith('**GET /cart** · 500 Server error'));
    expect(md, contains('Screen: CartScreen'));
    expect(md, contains('Issue: Server error'));
    expect(md, contains("curl -X GET 'https://api.test/cart'"));
    expect(md, contains('"error": "down"'));
  });
}
