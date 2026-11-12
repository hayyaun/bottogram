import 'package:dio/dio.dart';

enum TelegramConnectionIssue { reconnecting, unavailable }

/// Watches Telegram's own bot identity and polling requests. Successful empty
/// polls count as recovery, and an explicit Bot API rejection is reachable.
Interceptor observeTelegramConnection(
  void Function(String method, bool reachable) onResult,
) {
  void report(RequestOptions request, Response<dynamic>? response) {
    final method = request.uri.pathSegments.lastOrNull;
    if (method != 'getMe' && method != 'getUpdates') return;
    final data = response?.data;
    final status = response?.statusCode;
    final reachedTelegram =
        status != null &&
        status < 500 &&
        data is Map &&
        ((data['ok'] == true &&
                (method == 'getMe'
                    ? data['result'] is Map
                    : data['result'] is List)) ||
            (data['ok'] == false &&
                data['error_code'] is int &&
                (data['error_code'] as int) >= 400 &&
                (data['error_code'] as int) < 500));
    onResult(method!, reachedTelegram);
  }

  return InterceptorsWrapper(
    onResponse: (response, handler) {
      report(response.requestOptions, response);
      handler.next(response);
    },
    onError: (error, handler) {
      if (error.type != DioExceptionType.cancel) {
        report(error.requestOptions, error.response);
      }
      handler.next(error);
    },
  );
}
