import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The kind of a GraphQL operation.
enum AppInspectGraphQLType { query, mutation, subscription }

/// The GraphQL operation a call sends, read from its request.
///
/// GraphQL apps send every call to the same URL, such as `POST /graphql`, so
/// AppInspect names a call after its operation instead, such as
/// `query GetCart`. It reads the request the way GraphQL servers do: a JSON
/// body with `query` and `operationName`, the same as URL parameters for a
/// GET, an `application/graphql` body, a batch of operations, and persisted
/// queries that send only a name and a hash.
@immutable
class AppInspectGraphQL {
  const AppInspectGraphQL({this.type, this.name, this.query, this.variables, this.batchSize = 1});

  /// Query, mutation or subscription. Null for a persisted query, which
  /// sends a hash instead of the operation.
  final AppInspectGraphQLType? type;

  /// The operation's name, such as `GetCart`. For an operation without one,
  /// such as `{ products { id } }`, the first field it asks for: `products`.
  final String? name;

  /// The GraphQL document, as sent. Null for a persisted query.
  final String? query;

  /// The operation's variables, as sent.
  final Object? variables;

  /// How many operations the request sends. More than one in a batch.
  final int batchSize;

  /// Short text for the call list, such as `query GetCart`, or
  /// `query GetCart +2` for a batch of three.
  String get label {
    final kind = type?.name ?? 'operation';
    final base = name == null ? 'anonymous $kind' : (type == null ? name! : '$kind $name');
    return batchSize > 1 ? '$base +${batchSize - 1}' : base;
  }

  /// Bodies longer than this aren't read for an operation. GraphQL requests
  /// are small, and capturing has to stay cheap.
  static const int _maxBody = 256 * 1024;

  /// The operation [body] or [uri] sends, or null when the request isn't
  /// GraphQL. A file upload sends it in the `operations` field of a
  /// multipart form, which the adapters keep as `{'fields': {...}}`.
  static AppInspectGraphQL? fromRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Object? body,
  }) {
    try {
      if (body == null && method == 'GET' && uri.hasQuery) return _fromParameters(uri.queryParameters);
      if (body is String) {
        if (body.length > _maxBody) return null;
        final contentType = _header(headers, 'content-type') ?? '';
        if (contentType.contains('application/graphql') && !contentType.contains('json')) {
          return _fromDocument(body, null, null, required: false);
        }
        // Cheap checks first: most bodies aren't GraphQL.
        if (!body.contains('"query"') && !body.contains('"extensions"')) return null;
        final start = body.trimLeft();
        if (!start.startsWith('{') && !start.startsWith('[')) return null;
        return _fromJson(jsonDecode(body), looksLikeGraphQL: _looksLikeGraphQL(uri, contentType));
      }
      if (body case {'fields': {'operations': final String operations}}) {
        return _fromJson(jsonDecode(operations), looksLikeGraphQL: true);
      }
      if (body is Map || body is List) {
        return _fromJson(body, looksLikeGraphQL: _looksLikeGraphQL(uri, _header(headers, 'content-type') ?? ''));
      }
    } catch (_) {
      // A body AppInspect can't read is just not GraphQL.
    }
    return null;
  }

  static bool _looksLikeGraphQL(Uri uri, String contentType) =>
      uri.path.toLowerCase().contains('graphql') || contentType.contains('graphql');

  static AppInspectGraphQL? _fromJson(Object? json, {required bool looksLikeGraphQL}) {
    if (json is List) {
      final operations = [
        for (final item in json)
          if (_fromJson(item, looksLikeGraphQL: looksLikeGraphQL) case final AppInspectGraphQL op) op,
      ];
      if (operations.isEmpty || operations.length != json.length) return null;
      final first = operations.first;
      return AppInspectGraphQL(
        type: first.type,
        name: first.name,
        query: first.query,
        variables: first.variables,
        batchSize: operations.length,
      );
    }
    if (json is! Map) return null;
    final query = json['query'];
    final operationName = json['operationName'];
    final name = operationName is String && operationName.isNotEmpty ? operationName : null;
    if (query is String) return _fromDocument(query, name, json['variables'], required: !looksLikeGraphQL);
    // A persisted query sends a hash and, usually, the operation's name.
    final extensions = json['extensions'];
    if (query == null && extensions is Map && extensions['persistedQuery'] is Map) {
      return AppInspectGraphQL(name: name, variables: json['variables']);
    }
    return null;
  }

  static AppInspectGraphQL? _fromParameters(Map<String, String> parameters) {
    final query = parameters['query'];
    final operationName = parameters['operationName'];
    final name = operationName != null && operationName.isNotEmpty ? operationName : null;
    Object? variables = parameters['variables'];
    try {
      if (variables is String) variables = jsonDecode(variables);
    } on FormatException {
      // Keep the text.
    }
    if (query != null) return _fromDocument(query, name, variables, required: true);
    final extensions = parameters['extensions'];
    if (extensions != null && extensions.contains('persistedQuery')) {
      return AppInspectGraphQL(name: name, variables: variables);
    }
    return null;
  }

  /// Reads [document]. With [required], it must hold an operation, so that a
  /// search such as `{"query": "red shoes"}` isn't taken for GraphQL.
  static AppInspectGraphQL? _fromDocument(String document, String? operationName, Object? variables,
      {required bool required}) {
    final operations = _operations(document);
    if (operations.isEmpty) return required ? null : AppInspectGraphQL(name: operationName, query: document);
    final picked = operationName == null
        ? operations.first
        : operations.firstWhere((o) => o.name == operationName, orElse: () => operations.first);
    return AppInspectGraphQL(
      type: picked.type,
      name: operationName ?? picked.name ?? picked.firstField,
      query: document,
      variables: variables,
    );
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value.toLowerCase();
    }
    return null;
  }

  /// The operations defined in [document], in order. Fragments are skipped.
  ///
  /// A small scanner, not a full parser: it follows braces, parentheses,
  /// strings and comments, which is all it takes to find each operation's
  /// kind, name and first field.
  static List<_Operation> _operations(String document) {
    final operations = <_Operation>[];
    var depth = 0;
    var parens = 0;
    var inFragment = false;
    String? pendingType;
    String? pendingName;
    _Operation? awaitingField;
    // After `...`: the name of a fragment, or `on` of an inline one.
    var spread = false;
    var i = 0;
    final n = document.length;

    bool isNameStart(int c) => c == 0x5F || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
    bool isNamePart(int c) => isNameStart(c) || (c >= 0x30 && c <= 0x39);
    bool isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x2C;

    while (i < n) {
      final c = document.codeUnitAt(i);
      if (c == 0x2E && document.startsWith('...', i)) {
        spread = true;
        i += 3;
      } else if (c == 0x23) {
        // # comment, to the end of the line.
        final end = document.indexOf('\n', i);
        i = end < 0 ? n : end + 1;
      } else if (c == 0x22) {
        // "string" or """block string""".
        if (document.startsWith('"""', i)) {
          final end = document.indexOf('"""', i + 3);
          i = end < 0 ? n : end + 3;
        } else {
          i++;
          while (i < n && document.codeUnitAt(i) != 0x22) {
            i += document.codeUnitAt(i) == 0x5C ? 2 : 1;
          }
          i++;
        }
      } else if (c == 0x28) {
        parens++;
        i++;
      } else if (c == 0x29) {
        parens--;
        i++;
      } else if (c == 0x7B) {
        // {
        if (depth == 0 && parens == 0 && !inFragment) {
          final operation = _Operation(_typeOf(pendingType) ?? AppInspectGraphQLType.query, pendingName);
          operations.add(operation);
          awaitingField = operation;
          pendingType = pendingName = null;
        }
        depth++;
        i++;
      } else if (c == 0x7D) {
        // }
        depth--;
        if (depth <= 0) {
          depth = 0;
          inFragment = false;
          awaitingField = null;
        }
        i++;
      } else if (c == 0x24 || c == 0x40) {
        // $variable or @directive: skip its name.
        i++;
        while (i < n && isNamePart(document.codeUnitAt(i))) {
          i++;
        }
      } else if (isNameStart(c)) {
        final start = i;
        while (i < n && isNamePart(document.codeUnitAt(i))) {
          i++;
        }
        final word = document.substring(start, i);
        if (spread) {
          // `... on Cart` skips the type too.
          spread = word == 'on';
          continue;
        }
        if (parens > 0) continue;
        if (depth == 0) {
          if (inFragment) continue;
          if (word == 'fragment') {
            inFragment = true;
          } else if (pendingType == null && _typeOf(word) != null) {
            pendingType = word;
          } else if (pendingType != null && pendingName == null) {
            pendingName = word;
          }
        } else if (depth == 1 && awaitingField != null) {
          // An alias comes first, as in `cart: getCart`: take the field.
          var j = i;
          while (j < n && isSpace(document.codeUnitAt(j))) {
            j++;
          }
          if (j < n && document.codeUnitAt(j) == 0x3A) continue;
          awaitingField.firstField = word;
          awaitingField = null;
        }
      } else {
        i++;
      }
    }
    return operations;
  }

  static AppInspectGraphQLType? _typeOf(String? word) => switch (word) {
        'query' => AppInspectGraphQLType.query,
        'mutation' => AppInspectGraphQLType.mutation,
        'subscription' => AppInspectGraphQLType.subscription,
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is AppInspectGraphQL &&
      other.type == type &&
      other.name == name &&
      other.query == query &&
      other.batchSize == batchSize &&
      _sameJson(other.variables, variables);

  @override
  int get hashCode => Object.hash(type, name, query, batchSize);

  static bool _sameJson(Object? a, Object? b) {
    if (identical(a, b)) return true;
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }

  @override
  String toString() => 'AppInspectGraphQL($label)';
}

class _Operation {
  _Operation(this.type, this.name);

  final AppInspectGraphQLType type;
  final String? name;
  String? firstField;
}

/// An error a GraphQL server returned, often with a `200 OK` status.
@immutable
class AppInspectGraphQLError {
  const AppInspectGraphQLError({required this.message, this.path, this.code});

  /// The server's message, such as `Cart not found`.
  final String message;

  /// Where in the response it happened, such as `cart.items[0].price`.
  final String? path;

  /// The error's code, from `extensions.code`, such as `UNAUTHENTICATED`.
  final String? code;

  /// The message with its code and path, such as
  /// `Cart not found (NOT_FOUND, at cart)`.
  String get summary {
    final where = [if (code != null) code!, if (path != null) 'at $path'];
    return where.isEmpty ? message : '$message (${where.join(', ')})';
  }

  /// The errors in a decoded GraphQL response: its `errors` list, or the
  /// `errors` of each response in a batch.
  static List<AppInspectGraphQLError> listFrom(Object? response) {
    if (response is List) return [for (final item in response) ...listFrom(item)];
    if (response is! Map) return const [];
    final errors = response['errors'];
    if (errors is! List || errors.isEmpty) return const [];
    return [
      for (final error in errors)
        if (error is Map)
          AppInspectGraphQLError(
            message: '${error['message'] ?? 'Unknown error'}',
            path: _path(error['path']),
            code: switch (error['extensions']) {
              {'code': final Object code} => '$code',
              _ => null,
            },
          )
        else
          AppInspectGraphQLError(message: '$error'),
    ];
  }

  static String? _path(Object? path) {
    if (path is! List || path.isEmpty) return null;
    final out = StringBuffer();
    for (final part in path) {
      if (part is int) {
        out.write('[$part]');
      } else {
        if (out.isNotEmpty) out.write('.');
        out.write(part);
      }
    }
    return out.toString();
  }

  @override
  String toString() => 'AppInspectGraphQLError($summary)';
}
