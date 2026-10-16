import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:net_lens/net_lens.dart';
import 'package:net_lens_http/net_lens_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NetLens.store
      ..config = const NetLensConfig()
      ..clear();
  });

  test('records a call and hands the body on unchanged', () async {
    final client = NetLensHttpClient(MockClient((request) async {
      return http.Response('{"ok":true}', 201, headers: {'content-type': 'application/json'});
    }));

    final response = await client.post(
      Uri.parse('https://api.test/items'),
      headers: {'content-type': 'application/json'},
      body: '{"name":"a"}',
    );

    expect(response.body, '{"ok":true}');
    final call = NetLens.store.calls.single;
    expect(call.source, 'http');
    expect(call.method, 'POST');
    expect(call.requestBody, '{"name":"a"}');
    expect(call.statusLabel, '201 Created');
    expect(call.responseBody, '{"ok":true}');
    expect(call.responseSize, 11);
  });

  test('keeps only the start of a large body but passes all of it on', () async {
    NetLens.store.config = const NetLensConfig(maxBodyChars: 5);
    final client = NetLensHttpClient(MockClient((_) async {
      return http.Response('0123456789', 200, headers: {'content-type': 'text/plain'});
    }));

    final response = await client.get(Uri.parse('https://api.test/big'));

    expect(response.body, '0123456789');
    final call = NetLens.store.calls.single;
    expect(call.responseBody, '01234');
    expect(call.bodyTruncated, isTrue);
    expect(call.responseSize, 10);
  });

  test('records a failure in plain words and rethrows it', () async {
    final client = NetLensHttpClient(MockClient((_) async {
      throw http.ClientException('Failed host lookup: api.test');
    }));

    await expectLater(client.get(Uri.parse('https://api.test/x')), throwsA(isA<http.ClientException>()));

    final call = NetLens.store.calls.single;
    expect(call.statusLabel, 'No connection');
    expect(NetLens.store.unseenErrors.value, 1);
  });
}
