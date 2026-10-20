import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect_http/app_inspect_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppInspect.store
      ..config = const AppInspectConfig()
      ..clear();
  });

  test('records a call and hands the body on unchanged', () async {
    final client = AppInspectHttpClient(MockClient((request) async {
      return http.Response('{"ok":true}', 201, headers: {'content-type': 'application/json'});
    }));

    final response = await client.post(
      Uri.parse('https://api.test/items'),
      headers: {'content-type': 'application/json'},
      body: '{"name":"a"}',
    );

    expect(response.body, '{"ok":true}');
    final call = AppInspect.store.calls.single;
    expect(call.source, 'http');
    expect(call.method, 'POST');
    expect(call.requestBody, '{"name":"a"}');
    expect(call.statusLabel, '201 Created');
    expect(call.responseBody, '{"ok":true}');
    expect(call.responseSize, 11);
  });

  test('keeps only the start of a large body but passes all of it on', () async {
    AppInspect.store.config = const AppInspectConfig(maxBodyChars: 5);
    final client = AppInspectHttpClient(MockClient((_) async {
      return http.Response('0123456789', 200, headers: {'content-type': 'text/plain'});
    }));

    final response = await client.get(Uri.parse('https://api.test/big'));

    expect(response.body, '0123456789');
    final call = AppInspect.store.calls.single;
    expect(call.responseBody, '01234');
    expect(call.bodyTruncated, isTrue);
    expect(call.responseSize, 10);
  });

  test('records a failure in plain words and rethrows it', () async {
    final client = AppInspectHttpClient(MockClient((_) async {
      throw http.ClientException('Failed host lookup: api.test');
    }));

    await expectLater(client.get(Uri.parse('https://api.test/x')), throwsA(isA<http.ClientException>()));

    final call = AppInspect.store.calls.single;
    expect(call.statusLabel, 'No connection');
    expect(AppInspect.store.unseenErrors.value, 1);
  });

  test('a response the app stops reading early doesn\'t stay pending', () async {
    final client = AppInspectHttpClient(MockClient.streaming((request, body) async {
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode('line 1\n'), utf8.encode('line 2\n')]),
        200,
        contentLength: 14,
        headers: {'content-type': 'text/plain'},
      );
    }));

    final response = await client.send(http.Request('GET', Uri.parse('https://api.test/feed')));
    expect(await response.stream.first, utf8.encode('line 1\n'));

    final call = AppInspect.store.calls.single;
    expect(call.isPending, isFalse);
    expect(call.statusLabel, '200 OK');
    expect(call.responseBody, 'line 1\n');
    expect(call.responseSize, 14, reason: 'the size the server announced');
    expect(call.bodyTruncated, isTrue);
  });

  test('passes pauses on to the response, and still records it', () async {
    final client = AppInspectHttpClient(MockClient((_) async => http.Response('{"items":[1,2,3]}', 200)));

    final response = await client.send(http.Request('GET', Uri.parse('https://api.test/items')));
    final bytes = <int>[];
    final done = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = response.stream.listen((chunk) {
      bytes.addAll(chunk);
      sub.pause(Future<void>.delayed(const Duration(milliseconds: 10)));
    }, onDone: done.complete);
    await done.future;

    expect(utf8.decode(bytes), '{"items":[1,2,3]}');
    final call = AppInspect.store.calls.single;
    expect(call.statusLabel, '200 OK');
    expect(call.responseBody, '{"items":[1,2,3]}');
    expect(call.bodyTruncated, isFalse);
  });
}
