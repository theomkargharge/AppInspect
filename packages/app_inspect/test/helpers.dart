import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';

/// Loads Roboto from the Flutter SDK, so text in tests has the widths it has
/// on a phone. Without it, every letter is a 1em square, which is stricter,
/// so the tests still run when the fonts aren't there.
Future<void> loadRoboto() async {
  // flutter_tester lives in bin/cache/artifacts/engine/<platform>/.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final files = [
    for (final name in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold', 'Roboto-Black'])
      File('${artifacts.path}/material_fonts/$name.ttf'),
  ].where((f) => f.existsSync()).toList();
  if (files.isEmpty) return;
  final loader = FontLoader('Roboto');
  for (final file in files) {
    loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
}

/// Sizes the test screen like a phone, in logical pixels.
void setScreen(WidgetTester tester, Size size, {double textScale = 1, double ratio = 3}) {
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// The app under test: AppInspect around a MaterialApp.
Widget testApp(Widget home, {AppInspectConfig config = const AppInspectConfig()}) => AppInspect.wrap(
      MaterialApp(navigatorObservers: [AppInspect.navigatorObserver], home: home),
      config: config,
    );

/// Records what AppInspect copies to the clipboard.
List<String> mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// Puts AppInspect back the way a fresh app starts.
void resetAppInspect() {
  AppInspect.close();
  AppInspect.store
    ..clear()
    ..clearLogs();
  AppInspect.maskData.value = true;
  AppInspect.darkTheme.value = false;
  AppInspect.slowThreshold.value = const Duration(seconds: 1);
}

/// A finished call that took [took].
AppInspectCall finishedCall(
  String method,
  String url, {
  int status = 200,
  Object? requestBody,
  Object? responseBody,
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  Duration took = const Duration(milliseconds: 180),
}) {
  final call =
      AppInspect.store.startCall(method: method, uri: Uri.parse(url), headers: requestHeaders, body: requestBody);
  AppInspect.store.completeCall(call, statusCode: status, headers: responseHeaders, body: responseBody);
  call.endedAt = call.startedAt.add(took);
  return call;
}

/// Calls like a real shop app makes: successes, failures, a parse error, a
/// slow call, repeats, a pending call, binary and text bodies, and long URLs.
void seedRealisticCalls() {
  final store = AppInspect.store;
  finishedCall(
    'GET',
    'https://dummyjson.com/products?limit=12&select=title,price,category,rating',
    requestHeaders: {
      'accept': 'application/json',
      'authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MSwidXNlcm5hbWUiOiJlbWlseXMifQ.sig',
      'x-app-version': '2.3.1 (231)',
    },
    responseHeaders: {'content-type': 'application/json; charset=utf-8', 'x-request-id': 'b6a1c7e2-1f2d-4c5e-9a8b'},
    responseBody: jsonEncode({
      'products': [
        for (var i = 1; i <= 12; i++)
          {
            'id': i,
            'title': 'Essence Mascara Lash Princess, extra long product title number $i',
            'price': 9.99 + i,
            'category': 'beauty',
            'rating': 4.94,
            'tags': ['beauty', 'mascara'],
            'dimensions': {'width': 23.17, 'height': 14.43, 'depth': 28.01},
          },
      ],
      'total': 194,
      'skip': 0,
      'limit': 12,
    }),
  );
  finishedCall('GET', 'https://dummyjson.com/http/500/Offers_service_down',
      status: 500, responseBody: '{"status":"500","message":"Offers_service_down"}');
  final cart = finishedCall(
    'POST',
    'https://dummyjson.com/carts/add',
    status: 201,
    requestHeaders: {'content-type': 'application/json'},
    requestBody: {
      'userId': 1,
      'products': [
        {'id': 1, 'quantity': 1},
      ],
      'password': 'hunter2',
    },
    responseBody: '{"id":51,"products":[{"id":1,"title":"Essence Mascara","price":9.99,"quantity":1}],"total":9.99,'
        '"discountedTotal":9.99,"userId":1,"totalProducts":1,"totalQuantity":1}',
  );
  try {
    AppInspect.parse(decodeBody(cart.responseBody), (j) => j['total'] as int, call: cart);
  } catch (_) {}
  finishedCall('GET', 'https://dummyjson.com/products/1?select=reviews&delay=1500',
      took: const Duration(milliseconds: 1840), responseBody: '{"reviews":[]}');
  for (var i = 0; i < 3; i++) {
    finishedCall('GET', 'https://dummyjson.com/products/category/beauty?limit=4', responseBody: '{"products":[]}');
  }
  final timeout = store.startCall(method: 'GET', uri: Uri.parse('https://dummyjson.com/products?delay=3000&limit=1'));
  store.failCall(timeout, error: 'Timeout', detail: 'The request took longer than 0:00:01.000000 to receive data.');
  final custom = store.startCall(method: 'PATCH', uri: Uri.parse('https://api.example.com/v2/profile'));
  store.failCall(
    custom,
    error: 'SocketException: Connection reset by peer (OS Error: Connection reset by peer, errno = 54), '
        'address = api.example.com, port = 61234',
  );
  finishedCall(
    'DELETE',
    'https://api.example.com/v2/users/12345/addresses/67890/very/long/path/segment/that/keeps/going/'
        'and/going?force=true&reason=customer_requested_account_cleanup_after_duplicate_signup',
    status: 401,
    requestHeaders: {'authorization': 'Basic dXNlcjpwYXNz', 'cookie': 'session=abc123; theme=dark'},
    responseBody: '{"error":"unauthorized"}',
  );
  finishedCall('GET', 'https://cdn.example.com/banner.png',
      responseHeaders: {'content-type': 'image/png'}, responseBody: List<int>.filled(2048, 7));
  finishedCall('GET', 'https://example.com/terms',
      responseHeaders: {'content-type': 'text/html'},
      responseBody: '<html><body>${'Terms and conditions. ' * 40}</body></html>');
  final typedOver = store.startCall(method: 'GET', uri: Uri.parse('https://dummyjson.com/products/search?q=sho'));
  store.cancelCall(typedOver);
  store.startCall(method: 'GET', uri: Uri.parse('https://dummyjson.com/auth/me'));
}

/// Log entries of every level, some with details and calls.
void seedRealisticLogs() {
  AppInspect.log('[Shop] Loading products');
  AppInspect.log('Checkout started', level: AppInspectLogLevel.debug);
  AppInspect.log('Cart total looks wrong', level: AppInspectLogLevel.warning);
  AppInspect.log(
    'A RenderFlex overflowed by 32 pixels on the right. The overflowing RenderFlex has an orientation of '
    'Axis.horizontal and its children are too wide for the space it has.',
    level: AppInspectLogLevel.error,
    stackTrace: StackTrace.current,
  );
}
