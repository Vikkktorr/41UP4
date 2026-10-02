import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // kDebugMode, debugPrint

import 'api_exceptions.dart';
import 'config.dart';

/// Настроенный клиент Dio: базовый адрес, таймауты, общая обработка
/// ошибок, журнал запросов и повтор при сетевом сбое.
///
/// [debugQuery] — учебные параметры `__fail` и `__delay`, которые меню
/// отладки добавляет к каждому запросу. [retryDelay] — пауза перед первым
/// повтором; в тестах её обнуляют.
Dio buildDio({
  String? Function()? tokenProvider,
  Map<String, Object> Function()? debugQuery,
  Duration retryDelay = const Duration(milliseconds: 500),
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
      // Не бросать исключение на кодах 4xx — разберём их сами
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokenProvider?.call();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        final extra = debugQuery?.call();
        if (extra != null && extra.isNotEmpty) {
          options.queryParameters = {...options.queryParameters, ...extra};
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        // Коды 4xx попадают сюда, а не в onError, из-за validateStatus.
        final status = response.statusCode ?? 0;
        if (status >= 400) {
          // Просто написать `throw mapHttpError(...)` нельзя: dio перехватит
          // любое исключение из интерсептора и завернёт его в DioException
          // с типом unknown, а наш ValidationException окажется спрятан
          // внутри поля error. Поэтому отправляем ответ по ветке ошибок сами,
          // приложив уже разобранное исключение.
          return handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: mapHttpError(status, response.data),
            ),
            true,
          );
        }
        _log(response.requestOptions, '$status');
        return handler.next(response);
      },
      onError: (error, handler) {
        // Сюда приходят сетевые сбои, таймауты, коды 5xx
        // и всё, что отклонил обработчик выше.
        final status = error.response?.statusCode;
        _log(
          error.requestOptions,
          status != null ? '$status' : 'сбой: ${error.type.name}',
        );
        return handler.next(error);
      },
    ),
  );

  dio.interceptors.add(RetryInterceptor(dio, firstDelay: retryDelay));

  return dio;
}

/// В режиме отладки в консоль выводятся метод, адрес и код ответа.
void _log(RequestOptions options, String result) {
  if (kDebugMode) {
    debugPrint('[API] ${options.method} ${options.uri} → $result');
  }
}

/// Автоматический повтор при сетевом сбое: не более трёх повторов,
/// пауза каждый раз удваивается (0,5 → 1 → 2 с).
///
/// Повторяются только операции чтения (GET). Повторять создание записи
/// нельзя: первый запрос мог дойти до сервера, и повтор создал бы дубль.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(
    this._dio, {
    this.maxRetries = 3,
    this.firstDelay = const Duration(milliseconds: 500),
  });

  final Dio _dio;
  final int maxRetries;
  final Duration firstDelay;

  static const _attemptKey = 'retryAttempt';

  static bool _isNetworkFailure(DioException e) => switch (e.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => true,
    _ => false,
  };

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = options.extra[_attemptKey] as int? ?? 0;
    if (options.method != 'GET' ||
        !_isNetworkFailure(err) ||
        attempt >= maxRetries) {
      return handler.next(err);
    }

    final delay = firstDelay * (1 << attempt);
    if (kDebugMode) {
      debugPrint(
        '[API] повтор ${attempt + 1} из $maxRetries через '
        '${delay.inMilliseconds} мс: ${options.uri}',
      );
    }
    await Future<void>.delayed(delay);
    // Пока шла пауза, запрос могли отменить как устаревший.
    if (options.cancelToken?.isCancelled ?? false) return handler.next(err);

    options.extra[_attemptKey] = attempt + 1;
    try {
      return handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      return handler.next(e);
    }
  }
}
