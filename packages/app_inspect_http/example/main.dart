import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect_http/app_inspect_http.dart';
import 'package:flutter/material.dart';

final AppInspectHttpClient client = AppInspectHttpClient(); // or AppInspectHttpClient(yourClient)

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
            onPressed: () => client.get(Uri.parse('https://dummyjson.com/products/1')),
            child: const Text('Send a request'),
          ),
        ),
      ),
    );
  }
}
