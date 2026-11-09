import 'package:televerse/televerse.dart';

import 'repository.dart';
import 'diagnostics.dart';

/// Observes documented Bot API responses before Televerse dispatches handlers.
/// It must return the original response even if local inbox storage fails.
class InboxTransformer implements Transformer {
  InboxTransformer(this.repository);
  final Future<InboxRepository> Function() repository;

  @override
  Future<Map<String, dynamic>> transform(
    APICaller call,
    APIMethod method, [
    Payload? payload,
  ]) async {
    final response = await call(method, payload);
    final result = response['result'];
    final incoming =
        method == APIMethod.getUpdates && result is List && result.isNotEmpty;
    final outgoing =
        result is Map &&
        result['message_id'] is int &&
        result['chat'] is Map &&
        (result['chat'] as Map)['type'] == 'private';
    if (!incoming && !outgoing) return response;
    InboxRepository? inbox;
    try {
      inbox = await repository();
      if (incoming) {
        await inbox.captureUpdates(result);
      } else if (outgoing) {
        await inbox.captureSent(Map<String, dynamic>.from(result));
      }
    } catch (_) {
      // Never expose request URLs/tokens or report a successful send as failed.
      inbox?.reportCacheFailure();
      if (inbox == null) InboxDiagnostics.reportUnavailable();
    }
    return response;
  }
}

String replyError(Object error) {
  if (error is TelegramException) {
    if (error.code == 403) {
      return 'This user blocked the bot or replies are not permitted.';
    }
    if (error.code == 401) {
      return 'The bot token is invalid or has been revoked.';
    }
    if (error.code == 429) {
      final seconds = error.parameters?.retryAfter;
      return seconds == null
          ? 'Telegram rate limit reached. Wait before trying again.'
          : 'Telegram rate limit reached. Try again in $seconds seconds.';
    }
    if (error.code == 400) {
      return 'Telegram could not send this reply. Check the chat and message length.';
    }
  }
  return 'The reply could not be confirmed. Check your connection and the conversation '
      'before retrying; it may already have been delivered.';
}
