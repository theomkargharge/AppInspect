import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';

class Order {
  Order(this.price);

  factory Order.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>;
    final first = items[0] as Map<String, dynamic>;
    return Order(first['price'] as int);
  }

  final int price;
}

AppInspectCall completedCall(Object body, {String path = '/orders/1'}) {
  final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test$path'));
  AppInspect.store.completeCall(call, statusCode: 200, body: body);
  return call;
}

/// Throws the same TypeError a bad `as int` cast does.
Object typeErrorFor(Object? value) {
  try {
    (value as dynamic) as int;
  } catch (e) {
    return e;
  }
  throw StateError('no error');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppInspect.store
      ..config = const AppInspectConfig()
      ..clear()
      ..clearLogs();
  });

  group('parse errors', () {
    test('AppInspect.parse names the exact field that broke', () {
      final json = {
        'data': {
          'items': [
            {'price': 9.99},
          ],
        },
      };
      final call = completedCall(json);

      expect(() => AppInspect.parse(json, Order.fromJson, call: call), throwsA(isA<TypeError>()));

      final error = call.parseError!;
      expect(error.field, 'data.items[0].price');
      expect(error.got, 'double');
      expect(error.expected, 'int');
      expect(call.isError, isTrue);
      expect(call.statusLabel, '200 OK');
      expect(AppInspect.store.unseenErrors.value, 1);
      expect(AppInspect.store.logs.last.source, 'Parse error');
      expect(
        insightsFor(call, slowThreshold: const Duration(seconds: 1)).first.detail,
        contains('the app failed at data.items[0].price: expected int, got double.'),
      );
    });

    test('AppInspect.parse returns the model when nothing breaks', () {
      final json = {
        'data': {
          'items': [
            {'price': 10},
          ],
        },
      };

      expect(AppInspect.parse(json, Order.fromJson).price, 10);
      expect(AppInspect.store.logs, isEmpty);
    });

    test('parseList names the item that broke', () {
      final json = [
        {'id': 1},
        {'id': '2'},
      ];
      final call = completedCall(json, path: '/ids');

      expect(
        () => AppInspect.parseList(json, (j) => j['id'] as int, call: call),
        throwsA(isA<TypeError>()),
      );
      expect(call.parseError!.field, '[1].id');
    });

    test('reportParseError finds the call by URL and guesses the field', () {
      final call = completedCall({
        'count': 2,
        'total': 9.99,
        'items': [
          {'price': 9.99},
        ],
      }, path: '/cart');

      AppInspect.reportParseError(typeErrorFor(9.99), StackTrace.current, uri: Uri.parse('https://api.test/cart'));

      final error = call.parseError!;
      expect(error.field, isNull);
      expect(error.likelyFields, ['total', 'items[0].price']);
      expect(describeParseError(call, error), contains('Likely field: total, items[0].price.'));
    });

    test('a number sent as text is the likely field for a number', () {
      final call = completedCall({'name': 'Shoes', 'price': '2499.00'}, path: '/product');
      Object error;
      try {
        ('2499.00' as dynamic) as num;
        return;
      } catch (e) {
        error = e;
      }

      AppInspect.reportParseError(error, StackTrace.current, call: call);

      expect(call.parseError!.likelyFields, ['price']);
    });

    test('names the app code that failed, even in a package named app_inspect_something', () {
      final call = completedCall({'total': 9.99}, path: '/carts/add');

      AppInspect.reportParseError(
        typeErrorFor(9.99),
        StackTrace.fromString('#0      new CartResult.fromJson (package:app_inspect_example/main.dart:44:29)\n'
            '#1      AppInspect.parse (package:app_inspect/src/app_inspect.dart:140:14)'),
        call: call,
      );

      expect(call.parseError!.where, 'CartResult.fromJson (main.dart:44)');
    });

    test('an error without a call still reaches the logs', () {
      AppInspect.reportParseError(typeErrorFor('x'), StackTrace.current, uri: Uri.parse('https://api.test/unknown'));

      expect(AppInspect.store.logs.single.message, startsWith('Couldn\'t read a response'));
    });
  });

  group('logs', () {
    test('AppInspect.log tags the entry with the screen', () {
      AppInspect.store.startVisit('CartScreen');
      AppInspect.log('Checkout started', level: AppInspectLogLevel.warning);

      final log = AppInspect.store.logs.single;
      expect(log.message, 'Checkout started');
      expect(log.level, AppInspectLogLevel.warning);
      expect(log.source, 'App');
      expect(log.visit.name, 'CartScreen');
    });

    test('failed calls are logged as warnings with their call', () {
      final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/x'));
      AppInspect.store.completeCall(call, statusCode: 503);

      final log = AppInspect.store.logs.single;
      expect(log.level, AppInspectLogLevel.warning);
      expect(log.message, 'GET /x → 503 Unavailable');
      expect(log.call, same(call));
    });

    test('debugPrint and Flutter errors are captured while hooked', () {
      AppInspect.debugInstallLogHooks();
      try {
        debugPrint('[Cart] adding product 1');
        FlutterError.reportError(FlutterErrorDetails(exception: StateError('Bad state in cart')));
      } finally {
        AppInspect.debugRemoveLogHooks();
      }
      debugPrint('after removing the hooks');

      final logs = AppInspect.store.logs;
      expect(logs.map((l) => l.source), ['debugPrint', 'Flutter error']);
      expect(logs.first.message, '[Cart] adding product 1');
      expect(logs.last.level, AppInspectLogLevel.error);
      expect(logs.last.message, contains('Bad state in cart'));
      expect(AppInspect.store.unseenErrors.value, 1);
    });

    test('debugPrint inside runZoned is logged once, not again as print', () {
      AppInspect.debugInstallLogHooks();
      try {
        AppInspect.runZoned(() => debugPrint('only once'));
      } finally {
        AppInspect.debugRemoveLogHooks();
      }

      expect(AppInspect.store.logs.where((l) => l.message == 'only once'), hasLength(1));
      expect(AppInspect.store.logs.single.source, 'debugPrint');
    });

    test('runZoned captures print', () {
      AppInspect.runZoned(() => print('hello from print')); // ignore: avoid_print

      expect(AppInspect.store.logs.single.message, 'hello from print');
      expect(AppInspect.store.logs.single.source, 'print');
    });

    test('keeps the newest entries when there are too many', () {
      AppInspect.store.config = const AppInspectConfig(maxLogs: 5);
      for (var i = 0; i < 300; i++) {
        AppInspect.log('line $i');
      }

      expect(AppInspect.store.logs.length, lessThanOrEqualTo(105));
      expect(AppInspect.store.logs.last.message, 'line 299');
    });
  });
}
