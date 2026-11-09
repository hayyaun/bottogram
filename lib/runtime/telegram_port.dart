import 'package:televerse/televerse.dart';
import 'ports.dart';

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
        'arguments': context.args,
      });
    });
  }

  @override
  Future<void> send(String chatId, String text) async {
    try {
      await bot.api.sendMessage(ID.create(int.parse(chatId)), text);
    } catch (_) {
      // SDK exceptions can contain authenticated URLs; never surface them.
      throw const RuntimeFailure(
        'Telegram did not confirm delivery. Retrying may duplicate a message.',
      );
    }
  }
}
