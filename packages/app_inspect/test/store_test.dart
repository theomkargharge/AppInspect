import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppInspectStore store;
  final uri = Uri.parse('https://api.test/products?limit=2');

  setUp(() => store = AppInspectStore());

  test('tags each call with the screen on top', () {
    final home = store.startVisit('HomeScreen');
    final call = store.startCall(method: 'get', uri: uri);

    expect(call.visit, same(home));
    expect(call.method, 'GET');
    expect(call.path, '/products?limit=2');
    expect(store.callsFor(home), [call]);
  });

  test('flags the same call made again on the same screen', () {
    store.startVisit('ProductScreen');
    final first = store.startCall(method: 'GET', uri: uri);
    final second = store.startCall(method: 'GET', uri: uri);
    final third = store.startCall(method: 'GET', uri: uri);

    expect(first.repeatCount, 3);
    expect(second.repeatCount, 3);
    expect(third.isRepeated, isTrue);

    store.startVisit('CartScreen');
    expect(store.startCall(method: 'GET', uri: uri).isRepeated, isFalse);
  });

  test('keeps only the newest maxCalls calls', () {
    store.config = const AppInspectConfig(maxCalls: 3);
    for (var i = 0; i < 5; i++) {
      store.startCall(method: 'GET', uri: Uri.parse('https://api.test/$i'));
    }

    expect(store.calls.map((c) => c.uri.path), ['/2', '/3', '/4']);
  });

  test('counts failures until they are seen', () {
    final serverError = store.startCall(method: 'GET', uri: uri);
    final timeout = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/slow'));
    final ok = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/ok'));

    store.completeCall(serverError, statusCode: 500);
    store.failCall(timeout, error: 'Timeout');
    store.completeCall(ok, statusCode: 200);

    expect(store.unseenErrors.value, 2);
    expect(serverError.statusLabel, '500 Server error');
    expect(timeout.statusLabel, 'Timeout');
    expect(ok.statusLabel, '200 OK');
    expect(ok.isError, isFalse);

    store.markErrorsSeen();
    expect(store.unseenErrors.value, 0);
  });

  test('cuts long text bodies', () {
    store.config = const AppInspectConfig(maxBodyChars: 10);
    final call = store.startCall(method: 'GET', uri: uri);
    store.completeCall(call, statusCode: 200, body: 'x' * 50);

    expect(call.responseBody, 'x' * 10);
    expect(call.bodyTruncated, isTrue);
    expect(call.responseSize, 50);
  });

  test('ignores a second result for the same call', () {
    final call = store.startCall(method: 'GET', uri: uri);
    store.completeCall(call, statusCode: 200);
    store.failCall(call, error: 'Timeout');

    expect(call.statusLabel, '200 OK');
  });

  test('sizes decoded JSON only when asked, as an estimate', () async {
    final body = {
      'products': [
        {'title': 'Crème brûlée lip balm', 'price': 9.99, 'tags': ['beauty']},
      ],
      'total': 1,
    };
    final bytes = utf8.encode(jsonEncode(body)).length;
    final call = store.startCall(method: 'GET', uri: uri);
    store.completeCall(call, statusCode: 200, body: body);

    expect(call.responseSize, isNull, reason: 'capturing never encodes the body');

    expect(await store.estimateResponseSize(call), bytes);
    expect(call.responseSize, bytes);
    expect(call.responseSizeEstimated, isTrue);
  });

  test('keeps the size the client reported', () async {
    final call = store.startCall(method: 'GET', uri: uri);
    store.completeCall(call, statusCode: 200, body: {'id': 1}, size: 1749);

    expect(await store.estimateResponseSize(call), 1749);
    expect(call.responseSizeEstimated, isFalse);
  });

  test('leaves the size unknown when it can\'t be worked out', () async {
    final pending = store.startCall(method: 'GET', uri: uri);
    final timeout = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/slow'));
    store.failCall(timeout, error: 'Timeout');
    // A body from a custom decoder that can't be sent to another isolate.
    final port = ReceivePort();
    addTearDown(port.close);
    final odd = store.startCall(method: 'GET', uri: Uri.parse('https://api.test/odd'));
    store.completeCall(odd, statusCode: 200, body: {'port': port});

    for (final call in [pending, timeout, odd]) {
      expect(await store.estimateResponseSize(call), isNull);
      expect(call.responseSizeEstimated, isFalse);
    }
  });
}
