import 'dart:convert';
import 'dart:typed_data';
import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';
import 'ports.dart';
import 'telegram_config.dart';

class BotTelegramPort implements TelegramPort, TelegramInteractions {
  BotTelegramPort(this.bot);
  final Bot bot;
  final _commands = <String, List<void Function(Json)>>{};
  final _interactions = <String, List<void Function(Json)>>{};

  @override
  String get username => bot.me.username ?? '';

  @override
  void command(String command, void Function(Json event) receive) {
    final listeners = _commands.putIfAbsent(command, () {
      bot.command(command, (context) async {
        final chat = context.chat;
        if (chat == null) return;
        for (final listener in _commands[command]!) {
          listener({
            'id': context.update.updateId.toString(),
            'chatId': chat.id.toString(),
            'chatType': chat.type.name,
            'senderId': context.from?.id.toString(),
            'firstName': context.from?.firstName,
            'arguments': context.args,
          });
        }
      });
      return [];
    });
    listeners.add(receive);
  }

  @override
  void interaction(String kind, void Function(Json event) receive) {
    final listeners = _interactions.putIfAbsent(kind, () {
      if (kind == 'widget') {
        bot.onWidgetQuery((context) async {
          final query = context.widgetQuery!;
          final type = query.type;
          if (query.chat?.type == ChatType.private &&
              query.chat?.id == query.from.id &&
              query.messageId != null &&
              query.widgetId == null &&
              type is WidgetQueryTypeData &&
              type.walletCard == null) {
            _dispatch(
              kind,
              context.update.updateId,
              query.from,
              query.messageId!,
              query.data,
            );
          }
          try {
            await bot.api.answerWidgetQuery(query.id);
          } catch (_) {
            // The interaction may have expired while the client was offline.
          }
        });
      } else {
        bot.onCallbackQuery((context) async {
          final query = context.callbackQuery!;
          final message = query.message;
          final data = query.data;
          if (message?.chat.type == ChatType.private &&
              message?.chat.id == query.from.id &&
              data != null) {
            _dispatch(
              kind,
              context.update.updateId,
              query.from,
              message!.messageId,
              data,
            );
          }
          try {
            await bot.api.answerCallbackQuery(query.id);
          } catch (_) {
            // An expired tap should not interrupt polling.
          }
        });
      }
      return [];
    });
    listeners.add(receive);
  }

  void _dispatch(
    String kind,
    int updateId,
    User from,
    int messageId,
    String data,
  ) {
    for (final listener in _interactions[kind]!) {
      listener({
        'id': updateId.toString(),
        'chatId': from.id.toString(),
        'senderId': from.id.toString(),
        'firstName': from.firstName,
        'chatType': 'private',
        'messageId': messageId,
        'interaction': kind,
        'arguments': [data],
      });
    }
  }

  @override
  Future<bool> canPost(String chatId) async {
    final id = ID.create(int.parse(chatId));
    try {
      final chat = await bot.api
          .getChat(id)
          .timeout(const Duration(seconds: 10));
      if (chat.type != ChatType.channel) return false;
      final botId = bot.me.id;
      if (botId == null) return false;
      final member = await bot.api
          .getChatMember(id, botId)
          .timeout(const Duration(seconds: 10));
      return member is ChatMemberOwner ||
          member is ChatMemberAdministrator && member.canPostMessages == true;
    } catch (_) {
      return false;
    }
  }

  InlineKeyboard? _keyboard(Json? value) =>
      value == null ? null : InlineKeyboard.fromJson(value);

  @override
  Future<void> photo(
    String chatId,
    Uint8List bytes,
    String caption,
    Json? keyboard,
  ) => _deliver(
    () => bot.api.sendPhoto(
      ID.create(int.parse(chatId)),
      InputFile.fromBytes(bytes, name: 'photo.jpg', mimeType: 'image/jpeg'),
      caption: caption,
      replyMarkup: _keyboard(keyboard),
    ),
  );

  @override
  Future<void> widget(
    Json event,
    String html,
    Json data,
    String caption,
    Json? keyboard,
  ) {
    final chat = ID.create(int.parse(event['chatId'] as String));
    if (event['interaction'] == 'widget' && event['editWidget'] == true) {
      return _deliver(
        () => bot.api.editMessageWidgetData(
          chatId: chat,
          messageId: event['messageId'] as int,
          chatData: jsonEncode(data),
        ),
      );
    }
    return _deliver(
      () => bot.api.sendWidget(
        chat,
        html,
        chatData: jsonEncode(data),
        caption: caption,
        allowQueries: true,
        replyMarkup: _keyboard(keyboard),
      ),
    );
  }

  Future<void> _deliver(Future<dynamic> Function() request) async {
    try {
      await request().timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const RuntimeFailure(
        'Telegram did not confirm delivery. Retrying may duplicate a message.',
        code: 'telegram.delivery_unconfirmed',
      );
    }
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
            menu['type'] == 'commands'
                ? const MenuButton.commands()
                : MenuButton.webApp(
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
  Future<bool> synchronizeCommands(Json config, {String? adminId}) async {
    final public = config['commands'] as List?;
    if (public == null) return true;
    List<BotCommand> commands(List entries) => [
      for (final entry in entries.cast<Json>())
        BotCommand(
          command: entry['command'],
          description: entry['description'],
        ),
    ];
    try {
      final success = await bot.api
          .setMyCommands(
            commands(public),
            scope: const BotCommandScopeAllPrivateChats(),
            languageCode: '',
          )
          .timeout(const Duration(seconds: 10));
      if (!success || adminId == null) return success;
      return await bot.api
          .setMyCommands(
            commands([...public, ...config['adminCommands'] as List]),
            scope: BotCommandScopeChat(chatId: ID.create(int.parse(adminId))),
            languageCode: '',
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearAdminCommands(String adminId) async {
    try {
      return await bot.api
          .deleteMyCommands(
            scope: BotCommandScopeChat(chatId: ID.create(int.parse(adminId))),
            languageCode: '',
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return false;
    }
  }
}
