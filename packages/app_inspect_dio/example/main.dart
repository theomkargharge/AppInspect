import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect_dio/app_inspect_dio.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

// Add AppInspect last, so it sees the headers other interceptors add.
final Dio dio = Dio()..interceptors.add(AppInspectDioInterceptor());

void main() => runApp(AppInspect.wrap(const MyApp()));

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [AppInspect.navigatorObserver],
      home: Scaffold(
        body: Center(
          // Send a request, then tap the AppInspect bubble to see it.
          child: FilledButton(
            onPressed: () => dio.get<dynamic>('https://dummyjson.com/products/1'),
            child: const Text('Send a request'),
          ),
        ),
      ),
    );
  }
}
