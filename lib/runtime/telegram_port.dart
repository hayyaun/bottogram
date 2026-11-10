import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';
import 'ports.dart';
import 'telegram_config.dart';

class BotTelegramPort implements TelegramPort {
  BotTelegramPort(this.bot);
  final Bot bot;
  @override
  void command(String command, void Function(Json event) receive) {
    bot.command(command, (context) async {
      final chat = context.chat;
      if (chat == null) return;
      receive({
        'id': context.update.updateId.toString(),
        'chatId': chat.id.toString(),
        'chatType': chat.type.name,
        'arguments': context.args,
      });
    });
  }

  @override
  Future<void> send(String chatId, String text, {Json? replyMarkup}) async {
    try {
      await bot.api.sendMessage(
        ID.create(int.parse(chatId)),
        text,
        replyMarkup: replyMarkup == null
            ? null
            : InlineKeyboard.fromJson(replyMarkup),
      );
    } catch (_) {
      // SDK exceptions can contain authenticated URLs; never surface them.
      throw const RuntimeFailure(
        'Telegram did not confirm delivery. Retrying may duplicate a message.',
      );
    }
  }

  /// Synchronizing an optional menu never blocks independent automations.
  Future<bool> synchronizeMenu(
    Json telegramConfig,
    Map<String, String> fields,
  ) async {
    try {
      final menu = telegramConfig['menuButton'] as Json;
      return await bot.api
          .setChatMenuButton(
            MenuButton.webApp(
              text: menu['text'] as String,
              webApp: WebAppInfo(
                url: resolveWebAppTarget(menu['webApp'] as Json, fields),
              ),
            ),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return false;
    }
  }
}
