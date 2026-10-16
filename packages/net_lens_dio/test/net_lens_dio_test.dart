import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, SocketException;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_lens/net_lens.dart';
import 'package:net_lens_dio/net_lens_dio.dart';

/// Answers requests without a network.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.answer);

  final ResponseBody Function(RequestOptions options) answer;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      answer(options);

  @override
  void close({bool force = false}) {}
}

Dio dioWith(ResponseBody Function(RequestOptions options) answer) => Dio(BaseOptions(baseUrl: 'https://api.test'))
  ..httpClientAdapter = FakeAdapter(answer)
  ..interceptors.add(NetLensDioInterceptor());

ResponseBody json(String body, int status) => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Asks for the body as a stream, the way large files are read.
Future<Response<ResponseBody>> getStream(Dio dio, String path) =>
    dio.get<ResponseBody>(path, options: Options(responseType: ResponseType.stream));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(NetLens.store.clear);

  test('records a call with the headers and bodies', () async {
    final dio = dioWith((_) => json('{"id":1,"accessToken":"t"}', 200));

    await dio.post<dynamic>(
      '/login',
      data: {'username': 'qa', 'password': 'p'},
      options: Options(headers: {'Authorization': 'Bearer abcdefghijkl'}),
    );

    final call = NetLens.store.calls.single;
    expect(call.method, 'POST');
    expect(call.uri.toString(), 'https://api.test/login');
    expect(call.source, 'Dio');
    expect(call.requestHeaders['Authorization'], 'Bearer abcdefghijkl');
    expect(call.requestBody, {'username': 'qa', 'password': 'p'});
    expect(call.statusCode, 200);
    expect(call.responseBody, {'id': 1, 'accessToken': 't'});
    expect(call.isError, isFalse);
    expect(call.duration, isNotNull);
  });

  test('keeps the body of an error response', () async {
    final dio = dioWith((_) => json('{"message":"Product not found"}', 404));

    await expectLater(dio.get<dynamic>('/products/0'), throwsA(isA<DioException>()));

    final call = NetLens.store.calls.single;
    expect(call.statusLabel, '404 Not found');
    expect(call.isError, isTrue);
    expect(call.responseBody, {'message': 'Product not found'});
    expect(NetLens.store.unseenErrors.value, 1);
  });

  test('sizes a JSON response without a Content-Length when the call is opened', () async {
    // Like dummyjson.com: gzipped and chunked, so there's no Content-Length.
    const body = '{"products":[{"id":1,"title":"Crème brûlée lip balm","price":9.99}],"total":1}';
    final dio = dioWith((_) => json(body, 200));

    await dio.get<dynamic>('/products/category/beauty', queryParameters: {'limit': 4});

    final call = NetLens.store.calls.single;
    expect(call.responseBody, isA<Map<String, dynamic>>());
    expect(call.responseSize, isNull, reason: 'capturing never encodes the body');

    expect(await NetLens.store.estimateResponseSize(call), utf8.encode(body).length);
    expect(call.responseSizeEstimated, isTrue);
  });

  test('keeps the Content-Length the server sent', () async {
    final dio = dioWith((_) => ResponseBody.fromString(
          '{"id":1}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
            Headers.contentLengthHeader: ['8'],
          },
        ));

    await dio.get<dynamic>('/products/1');

    final call = NetLens.store.calls.single;
    expect(call.responseSize, 8);
    expect(await NetLens.store.estimateResponseSize(call), 8);
    expect(call.responseSizeEstimated, isFalse);
  });

  test('sizes a streamed response once the app has read it', () async {
    final chunks = [utf8.encode('id,total\n'), utf8.encode('1,9.99\n'), utf8.encode('2,12.50\n')];
    final dio = dioWith((_) => ResponseBody(Stream.fromIterable(chunks), 200));

    final res = await getStream(dio, '/orders/export');

    final call = NetLens.store.calls.single;
    expect(call.responseBody, '<streamed response>');
    expect(call.responseSize, isNull, reason: 'the placeholder is not the body');
    expect(await NetLens.store.estimateResponseSize(call), isNull, reason: 'opening it early guesses nothing');

    expect(await res.data!.stream.toList(), chunks, reason: 'the app gets the bytes as they came');
    expect(call.responseSize, 24);
    expect(call.responseSizeEstimated, isFalse);
  });

  test('sizes a download', () async {
    final pdf = Uint8List.fromList(List.generate(3000, (i) => i % 256));
    final dio = dioWith((_) => ResponseBody(Stream.fromIterable([pdf.sublist(0, 1024), pdf.sublist(1024)]), 200));
    final dir = Directory.systemTemp.createTempSync('net_lens_dio_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/receipt.pdf');

    await dio.download('/receipts/7.pdf', file.path);

    expect(file.readAsBytesSync(), pdf);
    expect(NetLens.store.calls.single.responseSize, 3000);
  });

  test('keeps the Content-Length of a streamed response', () async {
    // Gzipped: the header counts the bytes sent, the stream gives them unzipped.
    final dio = dioWith((_) => ResponseBody(
          Stream.value(Uint8List(5971)),
          200,
          headers: {
            Headers.contentLengthHeader: ['1749'],
            Headers.contentEncodingHeader: ['gzip'],
          },
        ));

    final res = await getStream(dio, '/products');
    final call = NetLens.store.calls.single;
    expect(call.responseSize, 1749);

    await res.data!.stream.drain<void>();
    expect(call.responseSize, 1749);
  });

  test('leaves a streamed size unknown if the stream breaks or the app stops early', () async {
    Stream<Uint8List> cutOff() async* {
      yield Uint8List(3);
      throw const SocketException('Connection reset by peer');
    }

    final broken = await getStream(dioWith((_) => ResponseBody(cutOff(), 200)), '/backup.zip');
    final errors = <Object>[];
    final done = Completer<void>();
    broken.data!.stream.listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future;
    expect(errors.single, isA<SocketException>(), reason: 'the app sees the error as it was');

    final big = await getStream(
      dioWith((_) => ResponseBody(Stream.fromIterable([Uint8List(3), Uint8List(4)]), 200)),
      '/video.mp4',
    );
    await big.data!.stream.first;

    expect(NetLens.store.calls.map((c) => c.responseSize), [null, null]);
  });

  testWidgets('tells the inspector when a streamed size comes in', (tester) async {
    final dio = dioWith((_) => ResponseBody(Stream.value(Uint8List(5)), 200));
    final res = await tester.runAsync(() => getStream(dio, '/avatar.png'));
    // Let the call list hear about the call itself first.
    await tester.pump();
    var notified = false;
    void listener() => notified = true;
    NetLens.store.addListener(listener);
    addTearDown(() => NetLens.store.removeListener(listener));

    await tester.runAsync(() => res!.data!.stream.drain<void>());
    await tester.pump();

    expect(NetLens.store.calls.single.responseSize, 5);
    expect(notified, isTrue, reason: 'the call list shows the size');
  });

  test('keeps a streamed size when a later interceptor rejects the response', () async {
    final dio = dioWith((_) => ResponseBody(Stream.value(utf8.encode('{"error":"token expired"}')), 200))
      ..interceptors.add(InterceptorsWrapper(
        onResponse: (res, handler) async {
          // Reads the body, finds an error in it, and passes the response to
          // the error interceptors, NetLens's too.
          await (res.data as ResponseBody).stream.drain<void>();
          handler.reject(DioException(requestOptions: res.requestOptions, response: res), true);
        },
      ));

    await expectLater(getStream(dio, '/session'), throwsA(isA<DioException>()));

    expect(NetLens.store.calls.single.responseSize, 25);
  });

  test('leaves the size unknown when the stream is shared between readers', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = FakeAdapter((_) => ResponseBody(Stream.value(Uint8List(5)), 200))
      ..interceptors.addAll([
        InterceptorsWrapper(onResponse: (res, handler) {
          // Lets two readers share the body, say a file writer and a preview.
          final body = res.data as ResponseBody;
          body.stream = body.stream.asBroadcastStream();
          handler.next(res);
        }),
        NetLensDioInterceptor(),
      ]);

    final res = await getStream(dio, '/live');
    await Future.wait([res.data!.stream.drain<void>(), res.data!.stream.drain<void>()]);

    expect(NetLens.store.calls.single.responseSize, isNull);
  });

  test('turns a timeout into plain words', () async {
    final dio = dioWith((o) => throw DioException(requestOptions: o, type: DioExceptionType.receiveTimeout));

    await expectLater(dio.get<dynamic>('/slow'), throwsA(isA<DioException>()));

    final call = NetLens.store.calls.single;
    expect(call.state, NetLensCallState.failed);
    expect(call.statusLabel, 'Timeout');
  });

  test('NetLensDio.parse links a parse error to its call, with the field', () async {
    final dio = dioWith((_) => json('{"id":7,"total":9.99}', 201));
    final res = await dio.post<dynamic>('/carts/add', data: {'id': 1});

    expect(() => NetLensDio.parse(res, (j) => j['total'] as int), throwsA(isA<TypeError>()));

    final call = NetLens.store.calls.single;
    expect(NetLensDio.callFor(res.requestOptions), same(call));
    expect(call.parseError!.field, 'total');
    expect(call.statusLabel, '201 Created');
  });

  test('reportParseError links Retrofit-style parse errors', () async {
    final dio = dioWith((_) => json('{"name":"Shoes","price":"12.50"}', 200));
    final res = await dio.get<dynamic>('/products/1');

    try {
      ((res.data as Map)['price'] as dynamic) as num;
    } catch (e, s) {
      NetLensDio.reportParseError(res.requestOptions, e, s);
    }

    expect(NetLens.store.calls.single.parseError!.likelyFields, ['price']);
  });

  test('describes form uploads without keeping the file', () async {
    final dio = dioWith((_) => json('{}', 201));

    await dio.post<dynamic>('/upload', data: FormData.fromMap({
      'note': 'receipt',
      'file': MultipartFile.fromBytes([1, 2, 3], filename: 'a.png'),
    }));

    expect(NetLens.store.calls.single.requestBody, {
      'fields': {'note': 'receipt'},
      'files': [
        {'field': 'file', 'filename': 'a.png', 'bytes': 3, 'contentType': 'image/png'},
      ],
    });
  });
}
