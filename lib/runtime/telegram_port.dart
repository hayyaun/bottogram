import 'dart:convert';
import 'dart:typed_data';
import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';
import 'ports.dart';
import 'telegram_config.dart';

class BotTelegramPort
    implements TelegramPort, TelegramInteractions, TelegramNotifications {
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
  Future<bool> canPost(
    String chatId, {
    Set<String> chatTypes = const {'channel'},
    bool photo = true,
  }) async {
    final id = ID.create(int.parse(chatId));
    try {
      final chat = await bot.api
          .getChat(id)
          .timeout(const Duration(seconds: 10));
      if (!chatTypes.contains(chat.type.name)) return false;
      final botId = bot.me.id;
      if (botId == null) return false;
      final member = await bot.api
          .getChatMember(id, botId)
          .timeout(const Duration(seconds: 10));
      if (member is ChatMemberOwner) return true;
      if (chat.type == ChatType.channel) {
        return member is ChatMemberAdministrator &&
            member.canPostMessages == true;
      }
      return switch (member) {
        ChatMemberAdministrator() => true,
        ChatMemberMember() =>
          (photo
                  ? chat.permissions?.canSendPhotos
                  : chat.permissions?.canSendMessages) ==
              true,
        ChatMemberRestricted() =>
          member.isMember &&
              (photo ? member.canSendPhotos : member.canSendMessages),
        _ => false,
      };
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
  ) async {
    final chat = ID.create(int.parse(event['chatId'] as String));
    if (event['interaction'] == 'widget' && event['editWidget'] == true) {
      await _deliver(
        () => bot.api.editMessageWidgetData(
          chatId: chat,
          messageId: event['messageId'] as int,
          chatData: jsonEncode(data),
        ),
      );
      return;
    }
    await _deliver(
      () => bot.api.sendWidget(
        chat,
        html,
        chatData: jsonEncode(data),
        caption: caption,
        allowQueries: true,
        replyMarkup: _keyboard(keyboard),
      ),
    );
    if (event['interaction'] == 'widget' && event['replaceWidget'] == true) {
      try {
        await bot.api
            .deleteMessage(chat, event['messageId'] as int)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // An older message may be outside Telegram's deletion window.
      }
    }
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
  Future<void> send(String chatId, String text, {Json? replyMarkup}) =>
      _send(chatId, text, replyMarkup: replyMarkup);

  @override
  Future<void> notify(String chatId, String text) =>
      _send(chatId, text, notification: true);

  Future<void> _send(
    String chatId,
    String text, {
    Json? replyMarkup,
    bool notification = false,
  }) async {
    try {
      await bot.api
          .sendMessage(
            ID.create(int.parse(chatId)),
            text,
            replyMarkup: replyMarkup == null
                ? null
                : InlineKeyboard.fromJson(replyMarkup),
          )
          .timeout(const Duration(seconds: 25));
    } on TelegramException catch (error) {
      if (notification && (error.code == 400 || error.code == 403)) {
        throw const RuntimeFailure(
          'Telegram refused delivery to this chat.',
          code: 'telegram.recipient_rejected',
        );
      }
      throw RuntimeFailure(
        'Telegram did not confirm delivery. Retrying may duplicate a message.',
        code: 'telegram.delivery_unconfirmed',
        retryAfter: error.parameters?.retryAfter == null
            ? null
            : Duration(seconds: error.parameters!.retryAfter!),
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
  Future<bool> synchronizeCommands(
    Json config, {
    Iterable<String> adminIds = const [],
  }) async {
    final public = config['commands'] as List?;
    if (public == null) return true;
    List<BotCommand> commands(List entries) => [
      for (final entry in entries.cast<Json>())
        BotCommand(
          command: entry['command'],
          description: entry['description'],
        ),
    ];
    Future<bool> set(List entries, BotCommandScope scope) async {
      try {
        return await bot.api
            .setMyCommands(commands(entries), scope: scope, languageCode: '')
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        return false;
      }
    }

    var success = await set(public, const BotCommandScopeAllPrivateChats());
    final adminCommands = config['adminCommands'] as List? ?? const [];
    for (final admin in adminIds) {
      final published = await set([
        ...public,
        ...adminCommands,
      ], BotCommandScopeChat(chatId: ID.create(int.parse(admin))));
      success = success && published;
    }
    return success;
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
