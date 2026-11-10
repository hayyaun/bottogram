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
        code: 'telegram.delivery_unconfirmed',
      );
    }
  }

  /// Synchronizing an optional menu never blocks independent automations.
  Future<bool> synchronizeMenu(
    Json telegramConfig,
    Map<String, String> fields,
  ) async {
    if (telegramConfig['menuButton'] == null) return true;
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

  /// An absent declaration leaves commands already configured in Telegram alone.
  Future<bool> synchronizeCommands(Json telegramConfig) async {
    if (telegramConfig['commands'] == null) return true;
    try {
      return await bot.api
          .setMyCommands(
            [
              for (final entry in telegramConfig['commands'] as List)
                BotCommand(
                  command: (entry as Json)['command'] as String,
                  description: entry['description'] as String,
                ),
            ],
            scope: const BotCommandScopeAllPrivateChats(),
            languageCode: '',
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // SDK failures may include the token-bearing URL or response body.
      return false;
    }
  }
}
