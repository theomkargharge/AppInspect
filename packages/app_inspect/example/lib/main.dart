import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect_dio/app_inspect_dio.dart';
import 'package:app_inspect_http/app_inspect_http.dart';

// The demo talks to dummyjson.com, a free fake REST API.
final Dio dio = Dio(BaseOptions(
  baseUrl: 'https://dummyjson.com',
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 15),
))
  // Add AppInspect last, so it sees the headers other interceptors add, such
  // as the token below. AppInspect masks it.
  ..interceptors.addAll([AuthInterceptor(), AppInspectDioInterceptor()]);

/// Adds the session token to every request, the way most apps do.
/// dummyjson.com doesn't check it on these endpoints.
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = 'Bearer kartly-session-7f3a9c2e5d41b8';
    handler.next(options);
  }
}

final AppInspectHttpClient httpClient = AppInspectHttpClient();

// AppInspect.runZoned also sends print() output to the AppInspect logs console.
void main() => AppInspect.runZoned(() {
      runApp(AppInspect.wrap(
        const ShopApp(),
        config: const AppInspectConfig(slowThreshold: Duration(milliseconds: 800)),
      ));
    });

/// What the app expects back from /carts/add.
///
/// The bug is on purpose: [total] is read as an int, but the server sends a
/// price such as 9.99. AppInspect shows the exact field that broke.
class CartResult {
  const CartResult({required this.id, required this.total, required this.totalQuantity});

  factory CartResult.fromJson(Map<String, dynamic> json) => CartResult(
        id: json['id'] as int,
        total: json['total'] as int,
        totalQuantity: json['totalQuantity'] as int,
      );

  final int id;
  final int total;
  final int totalQuantity;
}

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppInspect demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFE2582B), useMaterial3: true),
      navigatorObservers: [AppInspect.navigatorObserver],
      home: const HomeScreen(),
    );
  }
}

/// Two bottom tabs in an IndexedStack. Tabs don't push routes, so each one
/// is wrapped in AppInspectScreen to get its own name in the inspector.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          AppInspectScreen(name: 'ShopTab', child: ShopTab()),
          AppInspectScreen(name: 'AccountTab', child: AccountTab()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Shop'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}

class ShopTab extends StatefulWidget {
  const ShopTab({super.key});

  @override
  State<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<ShopTab> {
  List<dynamic>? _products;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    debugPrint('[Shop] Loading products');
    // This one fails with a 500, and the app hides it: no offers section.
    // The AppInspect bubble turns red, so QC still notices.
    dio.get<dynamic>('/http/500/Offers_service_down').ignore();
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/products',
        queryParameters: {'limit': 12, 'select': 'title,price,category,rating'},
      );
      if (mounted) setState(() => _products = res.data!['products'] as List<dynamic>);
    } on DioException {
      if (mounted) setState(() => _error = 'Couldn\'t load products. Pull down to try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    return Scaffold(
      appBar: AppBar(title: const Text('Kartly')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                avatar: const Icon(Icons.search_off, size: 18),
                label: const Text('Missing product (404)'),
                onPressed: () => dio.get<dynamic>('/products/0').ignore(),
              ),
              ActionChip(
                avatar: const Icon(Icons.timer_off_outlined, size: 18),
                label: const Text('Timeout'),
                onPressed: () => dio
                    .get<dynamic>(
                      '/products',
                      queryParameters: {'delay': 3000, 'limit': 1},
                      options: Options(receiveTimeout: const Duration(seconds: 1)),
                    )
                    .ignore(),
              ),
            ]),
            const SizedBox(height: 12),
            if (_error != null) Text(_error!),
            if (products == null && _error == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            for (final p in products ?? const <dynamic>[])
              Card(
                child: ListTile(
                  title: Text('${p['title']}'),
                  subtitle: Text('${p['category']} · ${p['rating']} rating'),
                  trailing: Text('\$${p['price']}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ProductScreen(id: p['id'] as int)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.id});

  final int id;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Map<String, dynamic>? _product;
  int? _reviewCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await dio.get<Map<String, dynamic>>(
      '/products/${widget.id}',
      queryParameters: {'select': 'title,price,category,description,stock'},
    );
    if (!mounted) return;
    setState(() => _product = res.data);

    // Slow on purpose: AppInspect flags it as slow.
    dio.get<Map<String, dynamic>>('/products/${widget.id}', queryParameters: {'select': 'reviews', 'delay': 1500}).then(
        (r) {
      if (mounted) setState(() => _reviewCount = (r.data!['reviews'] as List).length);
    }).ignore();

    // The same call three times, like an API call inside build().
    // AppInspect flags it as repeated.
    for (var i = 0; i < 3; i++) {
      dio.get<dynamic>('/products/category/${res.data!['category']}', queryParameters: {'limit': 4}).ignore();
    }
  }

  Future<void> _addToCart() async {
    final messenger = ScaffoldMessenger.of(context);
    debugPrint('[Cart] Adding product ${widget.id}');
    try {
      final res = await dio.post<dynamic>('/carts/add', data: {
        'userId': 1,
        'products': [
          {'id': widget.id, 'quantity': 1},
        ],
      });
      // The server answers 201 Created, but CartResult.fromJson throws.
      // QC only sees "Something went wrong". AppInspect shows why.
      final cart = AppInspectDio.parse(res, CartResult.fromJson);
      messenger.showSnackBar(SnackBar(content: Text('Added. ${cart.totalQuantity} items in your cart.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Something went wrong')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return Scaffold(
      appBar: AppBar(title: const Text('Product')),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${p['title']}', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('\$${p['price']} · ${p['stock']} in stock'),
                const SizedBox(height: 4),
                Text(_reviewCount == null ? 'Loading reviews…' : '$_reviewCount reviews'),
                const SizedBox(height: 12),
                Text('${p['description']}'),
                const SizedBox(height: 24),
                FilledButton(onPressed: _addToCart, child: const Text('Add to cart')),
              ],
            ),
    );
  }
}

/// Signs in with package:http, so you can see masking: the password, the
/// tokens and the Authorization header are hidden in AppInspect.
class AccountTab extends StatefulWidget {
  const AccountTab({super.key});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  String? _name;
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      // dummyjson.com's public demo account.
      final login = await httpClient.post(
        Uri.parse('https://dummyjson.com/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'emilys', 'password': 'emilyspass', 'expiresInMins': 30}),
      );
      final token = (jsonDecode(login.body) as Map<String, dynamic>)['accessToken'] as String;
      final me = await httpClient.get(
        Uri.parse('https://dummyjson.com/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final user = jsonDecode(me.body) as Map<String, dynamic>;
      // print() shows up in the AppInspect logs too, thanks to AppInspect.runZoned.
      // ignore: avoid_print
      print('[Auth] Signed in as ${user['username']}');
      if (mounted) setState(() => _name = '${user['firstName']} ${user['lastName']}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in failed')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_name == null ? 'You\'re signed out' : 'Signed in as $_name',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: Text(_busy ? 'Signing in…' : 'Sign in with the demo account'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Then tap the AppInspect bubble: the password and tokens are masked.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
