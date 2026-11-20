import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';

import 'helpers.dart';

AppInspectGraphQL? read(Object? body, {String method = 'POST', String url = 'https://api.shop.com/graphql'}) =>
    AppInspectGraphQL.fromRequest(
      method: method,
      uri: Uri.parse(url),
      headers: const {'content-type': 'application/json'},
      body: body,
    );

AppInspectCall graphQLCall(
  String query, {
  String? operationName,
  Map<String, Object?>? variables,
  Object? response = '{"data":{}}',
  int status = 200,
}) =>
    finishedCall(
      'POST',
      'https://api.shop.com/graphql',
      status: status,
      requestHeaders: {'content-type': 'application/json'},
      requestBody: jsonEncode({
        'query': query,
        if (operationName != null) 'operationName': operationName,
        if (variables != null) 'variables': variables,
      }),
      responseBody: response,
    );

void main() {
  group('reading the operation', () {
    test('a named query', () {
      final op = read('{"query":"query GetCart(\$id: ID!) { cart(id: \$id) { total } }","variables":{"id":"7"}}')!;
      expect(op.type, AppInspectGraphQLType.query);
      expect(op.name, 'GetCart');
      expect(op.label, 'query GetCart');
      expect(op.variables, {'id': '7'});
    });

    test('a mutation sent as a decoded map, as Dio does', () {
      final op = read({'query': 'mutation AddToCart { addToCart(id: 1) { id } }'})!;
      expect(op.type, AppInspectGraphQLType.mutation);
      expect(op.label, 'mutation AddToCart');
    });

    test('an anonymous query is named after its first field', () {
      expect(read('{"query":"{ products(first: 10) { id } }"}')!.label, 'query products');
      expect(read('{"query":"query { me { name } }"}')!.name, 'me');
    });

    test('an alias names the field it asks for', () {
      expect(read('{"query":"{ cart: getCart { id } }"}')!.name, 'getCart');
    });

    test('operationName picks the operation from a document with several', () {
      const doc = 'query A { a } mutation B { b }';
      final op = read(jsonEncode({'query': doc, 'operationName': 'B'}))!;
      expect(op.type, AppInspectGraphQLType.mutation);
      expect(op.name, 'B');
    });

    test('fragments, comments, strings and directives are skipped', () {
      const doc = '''
        # query NotThis { x }
        fragment CartFields on Cart { id total }
        subscription OnCart(\$id: ID! = "query Fake {") @live {
          ...CartFields
          cartChanged(note: """mutation Nope { }""") { id }
        }
      ''';
      final op = read(jsonEncode({'query': doc}))!;
      expect(op.type, AppInspectGraphQLType.subscription);
      expect(op.name, 'OnCart');
    });

    test('a spread before the first field', () {
      expect(read(jsonEncode({'query': '{ ...Fields ... on Query { x } products { id } }'}))!.name, 'products');
    });

    test('a GET with the query in the URL', () {
      final op = read(null,
          method: 'GET',
          url: 'https://api.shop.com/graphql?query=${Uri.encodeQueryComponent('query Me { me { id } }')}'
              '&variables=${Uri.encodeQueryComponent('{"a":1}')}')!;
      expect(op.label, 'query Me');
      expect(op.variables, {'a': 1});
    });

    test('an application/graphql body', () {
      final op = AppInspectGraphQL.fromRequest(
        method: 'POST',
        uri: Uri.parse('https://api.shop.com/gql'),
        headers: const {'Content-Type': 'application/graphql'},
        body: 'mutation Pay { pay { ok } }',
      )!;
      expect(op.label, 'mutation Pay');
    });

    test('a batch of operations', () {
      final op = read(jsonEncode([
        {'query': 'query A { a }'},
        {'query': 'query B { b }'},
        {'query': 'query C { c }'},
      ]))!;
      expect(op.batchSize, 3);
      expect(op.label, 'query A +2');
    });

    test('a file upload sends the operation in a multipart form', () {
      final op = read({
        'fields': {
          'operations': '{"query":"mutation Upload(\$file: Upload!) { upload(file: \$file) { id } }"}',
          'map': '{"0":["variables.file"]}',
        },
        'files': const [],
      }, url: 'https://api.shop.com/upload')!;
      expect(op.label, 'mutation Upload');
    });

    test('a persisted query sends only a name and a hash', () {
      final op = read(jsonEncode({
        'operationName': 'GetCart',
        'variables': {'id': 1},
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': 'abc'},
        },
      }))!;
      expect(op.type, isNull);
      expect(op.query, isNull);
      expect(op.label, 'GetCart');
    });

    test('REST bodies and searches are not GraphQL', () {
      final rest = 'https://api.shop.com/search';
      expect(read('{"query":"red shoes"}', url: rest), isNull);
      expect(read('{"query":"query"}', url: rest), isNull);
      expect(read({'query': 'shoes', 'page': 2}, url: rest), isNull);
      expect(read('{"userId":1}', url: rest), isNull);
      expect(read(null, method: 'GET', url: '$rest?query=shoes'), isNull);
      expect(read(null, method: 'GET', url: '$rest?query=query%20shoes'), isNull);
      expect(read([1, 2, 3], url: rest), isNull);
      expect(read('not json', url: rest), isNull);
    });
  });

  group('errors in the response', () {
    test('are read with their path and code', () {
      final errors = AppInspectGraphQLError.listFrom({
        'data': null,
        'errors': [
          {
            'message': 'Cart not found',
            'path': ['cart', 'items', 0],
            'extensions': {'code': 'NOT_FOUND'},
          },
          {'message': 'Slow down'},
        ],
      });
      expect(errors.map((e) => e.summary), ['Cart not found (NOT_FOUND, at cart.items[0])', 'Slow down']);
    });

    test('a response without errors has none', () {
      expect(AppInspectGraphQLError.listFrom({'data': {}}), isEmpty);
      expect(AppInspectGraphQLError.listFrom({'errors': []}), isEmpty);
      expect(AppInspectGraphQLError.listFrom('text'), isEmpty);
    });
  });

  group('captured calls', () {
    setUp(resetAppInspect);

    test('a 200 with GraphQL errors is a failure, turns the bubble red and is logged', () {
      final before = AppInspect.store.unseenErrors.value;
      final call = graphQLCall(
        'query GetCart { cart { id } }',
        response: '{"data":null,"errors":[{"message":"Cart not found","path":["cart"]}]}',
      );
      expect(call.graphQLErrors.single.message, 'Cart not found');
      expect(call.isError, isTrue);
      expect(AppInspect.store.unseenErrors.value, before + 1);
      expect(
        AppInspect.store.logs.last.message,
        'query GetCart → 200 OK, GraphQL error: Cart not found (at cart)',
      );
      final insight = insightsFor(call, slowThreshold: const Duration(seconds: 1)).first;
      expect(insight.title, 'The server returned a GraphQL error');
      expect(insight.level, AppInspectInsightLevel.error);
    });

    test('a decoded response with errors, as Dio gives it', () {
      final call = graphQLCall('query A { a }', response: {
        'errors': [
          {'message': 'Nope'},
        ],
      });
      expect(call.isError, isTrue);
    });

    test('a 4xx with GraphQL errors counts once', () {
      final before = AppInspect.store.unseenErrors.value;
      final logs = AppInspect.store.logs.length;
      graphQLCall('query A { a }', status: 400, response: '{"errors":[{"message":"Bad"}]}');
      expect(AppInspect.store.unseenErrors.value, before + 1);
      expect(AppInspect.store.logs.length, logs + 1);
    });

    test('a REST response with an errors field is left alone', () {
      final call = finishedCall('POST', 'https://api.shop.com/carts',
          requestBody: '{"userId":1}', responseBody: '{"errors":[{"message":"not graphql"}]}');
      expect(call.graphQL, isNull);
      expect(call.isError, isFalse);
    });

    test('different operations on one URL are not repeats', () {
      final a = graphQLCall('query GetCart { cart { id } }');
      final b = graphQLCall('query GetUser { me { id } }');
      final c = graphQLCall('query GetCart { cart { id } }', variables: {'page': 2});
      expect([a.isRepeated, b.isRepeated, c.isRepeated], [false, false, false]);
      final d = graphQLCall('query GetUser { me { id } }');
      expect(d.repeatCount, 2);
      expect(b.repeatCount, 2);
    });
  });

  group('exports', () {
    setUp(resetAppInspect);

    test('Markdown names the operation and its errors', () {
      final call = graphQLCall('query GetCart { cart { id } }',
          response: '{"errors":[{"message":"Cart not found","extensions":{"code":"NOT_FOUND"}}]}');
      final markdown =
          callToMarkdown(call, AppInspectMasker(AppInspect.config), slowThreshold: const Duration(seconds: 1));
      expect(markdown, startsWith('**query GetCart** · 200 OK'));
      expect(markdown, contains('GraphQL: POST /graphql'));
      expect(markdown, contains('Errors: Cart not found (NOT_FOUND)'));
    });

    test('Postman gets a GraphQL body with masked variables', () {
      final call = graphQLCall('mutation Login(\$p: String) { login(password: \$p) { token } }',
          variables: {'password': 'hunter2', 'user': 'emily'});
      final collection = jsonDecode(buildPostmanCollection([call], AppInspectMasker(AppInspect.config), name: 'x'))
          as Map<String, Object?>;
      final item = (collection['item']! as List).single as Map;
      expect(item['name'], 'mutation Login');
      final body = (item['request'] as Map)['body'] as Map;
      expect(body['mode'], 'graphql');
      final graphql = body['graphql'] as Map;
      expect(graphql['query'], contains('mutation Login'));
      final variables = jsonDecode(graphql['variables'] as String) as Map;
      expect(variables, {'password': appInspectMask, 'user': 'emily'});
    });

    test('HAR entries carry the operation', () {
      final call = graphQLCall('query GetCart { cart { id } }');
      final har = jsonDecode(buildHar([call], AppInspectMasker(AppInspect.config))) as Map;
      final entry = ((har['log'] as Map)['entries'] as List).single as Map;
      expect(entry['_graphql'], 'query GetCart');
    });
  });

  group('the inspector', () {
    setUp(resetAppInspect);

    testWidgets('names GraphQL calls after their operation and flags errors', (tester) async {
      await tester.pumpWidget(testApp(const Scaffold(body: Text('Home'))));
      await tester.pumpAndSettle();
      graphQLCall('query GetCart { cart { id } }',
          response: '{"errors":[{"message":"Cart not found","path":["cart"]}]}');
      graphQLCall('mutation AddToCart { addToCart(id: 1) { id } }');
      AppInspect.open();
      await tester.pumpAndSettle();

      expect(find.text('GetCart'), findsOneWidget);
      expect(find.text('AddToCart'), findsOneWidget);
      expect(find.text('QUERY'), findsOneWidget);
      expect(find.text('MUTATION'), findsOneWidget);
      expect(find.text('GraphQL error'), findsOneWidget);

      await tester.tap(find.text('GetCart'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The server returned a GraphQL error', findRichText: true), findsOneWidget);
      expect(find.text('query GetCart'), findsOneWidget);

      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();
      expect(find.text('GRAPHQL OPERATION'), findsOneWidget);
    });

    testWidgets('search finds a call by its operation name', (tester) async {
      await tester.pumpWidget(testApp(const Scaffold(body: Text('Home'))));
      await tester.pumpAndSettle();
      graphQLCall('query GetCart { cart { id } }');
      graphQLCall('query GetUser { me { id } }');
      AppInspect.open();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'getuser');
      await tester.pumpAndSettle();
      expect(find.text('GetUser'), findsOneWidget);
      expect(find.text('GetCart'), findsNothing);
    });
  });
}
