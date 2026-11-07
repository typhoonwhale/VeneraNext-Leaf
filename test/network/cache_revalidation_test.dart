import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/network/app_dio.dart';
import 'package:venera_next/network/cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.isWindows) await rhttp.Rhttp.init();
  });
  const url = 'http://127.0.0.1:1/cache-owner';
  final cache = NetworkCacheManager();

  setUp(() {
    final initialized = App.isInitialized;
    final muted = Log.isMuted;
    App.isInitialized = true;
    Log.isMuted = true;
    cache.clear();
    addTearDown(() {
      App.isInitialized = initialized;
      Log.isMuted = muted;
      cache.clear();
    });
  });

  void seed({
    Duration age = const Duration(minutes: 1),
    Map<String, dynamic> headers = const {},
    ResponseType? responseType,
    Object data = 'cached',
  }) => cache.setCache(
    NetworkCache(
      uri: Uri.parse(url),
      requestHeaders: headers,
      responseHeaders: const {},
      data: data,
      time: DateTime.now().subtract(age),
      size: 6,
      responseType: responseType,
    ),
  );

  Future<Response<String>> get(
    _Adapter adapter, {
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) {
    final dio = AppDio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    return dio.get<String>(
      url,
      options: Options(headers: headers),
      cancelToken: cancelToken,
    );
  }

  test('fresh cache is reused without a request', () async {
    seed(age: const Duration(seconds: 1));
    final adapter = _Adapter((_) async => ResponseBody.fromString('new', 200));
    final response = await get(adapter);
    expect(response.data, 'cached');
    expect(response.headers.value('venera-cache'), 'true');
    expect(adapter.methods, isEmpty);
  });

  test('cache older than 5 seconds is refreshed with one GET', () async {
    seed(age: const Duration(seconds: 6));
    final adapter = _Adapter((_) async => ResponseBody.fromString('new', 200));
    final response = await get(adapter);
    expect(response.data, 'new');
    expect(response.headers.value('venera-cache'), isNull);
    expect(adapter.methods, ['GET']);
    expect(cache.getCache(Uri.parse(url))!.data, 'new');
  });

  test('cache-time long reuses for 6 hours then sends only GET', () async {
    final headers = {'cache-time': 'long'};
    seed(age: const Duration(hours: 5));
    final reused = _Adapter((_) async => ResponseBody.fromString('new', 200));
    expect((await get(reused, headers: headers)).data, 'cached');
    expect(reused.methods, isEmpty);

    seed(age: const Duration(hours: 7));
    final expired = _Adapter((_) async => ResponseBody.fromString('new', 200));
    expect((await get(expired, headers: headers)).data, 'new');
    expect(expired.methods, ['GET']);
    expect(cache.getCache(Uri.parse(url))!.data, 'new');
  });

  test('cache-time no bypasses a fresh cache', () async {
    seed(age: Duration.zero);
    final adapter = _Adapter((_) async => ResponseBody.fromString('new', 200));
    expect((await get(adapter, headers: {'cache-time': 'no'})).data, 'new');
    expect(adapter.methods, ['GET']);
  });

  test('request cancelled before cache reuse is rejected', () async {
    seed(age: Duration.zero);
    final adapter = _Adapter((_) async => ResponseBody.fromString('new', 200));
    final token = CancelToken()..cancel('caller closed');
    await expectLater(
      get(adapter, cancelToken: token),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(adapter.methods, isEmpty);
  });

  test('cleared cache cannot return its old body', () async {
    seed();
    cache.clear();
    final adapter = _Adapter((_) async => ResponseBody.fromString('new', 200));
    expect((await get(adapter)).data, 'new');
    expect(adapter.methods, ['GET']);
  });

  test('authorization changes cannot reuse another credential cache', () async {
    seed(age: Duration.zero, headers: {'authorization': 'Bearer first'});
    final adapter = _Adapter(
      (_) async => ResponseBody.fromString('current account', 200),
    );
    final dio = AppDio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final response = await dio.get<String>(
      url,
      options: Options(headers: {'authorization': 'Bearer second'}),
    );
    expect(response.data, 'current account');
    expect(adapter.methods, ['GET']);
  });

  test(
    'response representation changes cannot reuse a cached string as bytes',
    () async {
      seed(age: Duration.zero, responseType: ResponseType.plain);
      final adapter = _Adapter(
        (_) async => ResponseBody.fromString('bytes', 200),
      );
      final dio = AppDio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      expect(response.data, 'bytes'.codeUnits);
      expect(adapter.methods, ['GET']);
    },
  );

  for (final streaming in [false, true]) {
    test(
      'GET payload bypasses cache and preserves its body: stream=$streaming',
      () async {
        final contentType = streaming
            ? 'application/octet-stream'
            : 'application/json';
        seed(age: Duration.zero, headers: {'content-type': contentType});
        final cached = cache.getCache(Uri.parse(url));
        final adapter = _Adapter(
          (_) async => ResponseBody.fromString('filtered result', 200),
          consumeInput: true,
        );
        final dio = AppDio()..httpClientAdapter = adapter;
        addTearDown(() => dio.close(force: true));
        final response = await dio.get<String>(
          url,
          data: streaming
              ? Stream<Uint8List>.value(
                  Uint8List.fromList('new filter'.codeUnits),
                )
              : {'filter': 'new'},
          options: Options(headers: {'content-type': contentType}),
        );
        expect(response.data, 'filtered result');
        expect(adapter.methods, ['GET']);
        expect(String.fromCharCodes(adapter.upload), contains('new'));
        expect(cache.getCache(Uri.parse(url)), same(cached));
      },
    );
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond, {this.consumeInput = false});
  final Future<ResponseBody> Function(RequestOptions) respond;
  final bool consumeInput;
  final upload = <int>[];
  final methods = <String>[];
  int closes = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    methods.add(options.method);
    if (consumeInput && requestStream != null) {
      await for (final chunk in requestStream) {
        upload.addAll(chunk);
      }
    }
    return respond(options);
  }

  @override
  void close({bool force = false}) => closes++;
}
