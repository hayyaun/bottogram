import 'dart:convert';

import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';
import 'engine.dart';
import 'rich_message.dart';
import 'values.dart';

/// Typed, supported Televerse methods retain the app's inbox transformers.
class BuilderTelegramPort implements BuilderTelegram {
  BuilderTelegramPort(this.api);
  final RawAPI api;
  final Set<String> _answeredCallbacks = {};
  bool takeCallbackAnswer(String id) => _answeredCallbacks.remove(id);
  bool takeWidgetAnswer(String id) => _answeredCallbacks.remove('widget:$id');
  @override
  Future<BuilderJson> execute(String kind, BuilderJson arguments) async {
    String value(String key) => arguments[key]?.toString() ?? '';
    String required(String key) {
      final result = value(key);
      if (result.isEmpty) throw BuilderFailure('This action requires $key.');
      return result;
    }

    ID chat() {
      final target = required('chatId');
      return ID.create(int.tryParse(target) ?? target);
    }

    int message() {
      final id = int.tryParse(value('messageId'));
      if (id == null || id < 1) {
        throw const BuilderFailure('Select a valid target message ID.');
      }
      return id;
    }

    final parseMode = arguments['format'] == 'MarkdownV2'
        ? ParseMode.markdownV2
        : null;
    final rawKeyboard = arguments['keyboard'];
    final keyboardJson = rawKeyboard == null
        ? null
        : Map<String, dynamic>.from(rawKeyboard as Map);
    final keyboard =
        keyboardJson == null ||
            (arguments['richBlocks'] != null &&
                (keyboardJson['inline_keyboard'] as List?)?.isEmpty == true)
        ? null
        : keyboardJson.containsKey('inline_keyboard')
        ? InlineKeyboardMarkup.fromJson(keyboardJson)
        : ReplyMarkup.fromJson(keyboardJson);
    InlineKeyboardMarkup? inlineKeyboard() {
      if (keyboard != null && keyboard is! InlineKeyboardMarkup) {
        throw const BuilderFailure('This action requires an inline keyboard.');
      }
      return keyboard as InlineKeyboardMarkup?;
    }

    BuilderJson sent(Message result) => {
      'ok': true,
      'messageId': result.messageId,
      'chatId': result.chat.id,
    };
    InputFile media() {
      final source = required('media');
      if (source.startsWith('/') ||
          source.startsWith('\\') ||
          RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source)) {
        throw const BuilderFailure(
          'Local media paths are unavailable. Use a Telegram file ID or HTTP(S) URL.',
        );
      }
      final uri = Uri.tryParse(source);
      if (uri == null) {
        throw const BuilderFailure(
          'Enter a valid media URL or Telegram file ID.',
        );
      }
      if (uri.hasScheme) {
        if (!{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment) {
          throw const BuilderFailure(
            'Media requires a Telegram file ID or a valid HTTP(S) URL.',
          );
        }
        return InputFile.fromUrl(source);
      }
      return InputFile.fromFileId(source);
    }

    final widget = arguments['widget'];
    if (widget is Map) {
      final target = int.tryParse(value('chatId'));
      if (target == null || target < 1) {
        throw const BuilderFailure('Widgets require a private chat.');
      }
      final data = widget['chatData'];
      final chatData = data == null
          ? null
          : data is String
          ? data
          : jsonEncode(data);
      if (chatData != null &&
          (utf8.encode(chatData).length > 1024 ||
              chatData.contains('\u0000'))) {
        throw const BuilderFailure(
          'Widget chat data must be at most 1024 UTF-8 bytes.',
        );
      }
      if (kind == 'editText') {
        return {
          'ok': await api.editMessageWidgetData(
            chatId: chat(),
            messageId: message(),
            chatData: chatData,
          ),
          'messageId': message(),
          'widget': true,
        };
      }
      final html = widget['html'] as String;
      if (html.isEmpty ||
          utf8.encode(html).length > 32768 ||
          html.contains('\u0000')) {
        throw const BuilderFailure('Widget HTML must be 1–32768 UTF-8 bytes.');
      }
      return {
        ...sent(
          await api.sendWidget(
            chat(),
            html,
            chatData: chatData,
            allowQueries: widget['allowQueries'] == true,
            caption: widget['caption'] == ''
                ? null
                : widget['caption'] as String?,
          ),
        ),
        'widget': true,
      };
    }
    final draftId = value('draftId');
    final richBlocks = arguments['richBlocks'];
    final rich = richBlocks == null
        ? null
        : BuilderRichMessage.build(richBlocks, draft: draftId.isNotEmpty);
    if (draftId.isNotEmpty) {
      final id = int.tryParse(draftId);
      final target = int.tryParse(value('chatId'));
      if (kind != 'reply' ||
          rich == null ||
          keyboard != null ||
          id == null ||
          id <= 0 ||
          target == null ||
          target <= 0 ||
          target != arguments['userId']) {
        throw const BuilderFailure(
          'A rich draft requires a private chat, draft ID and rich content.',
        );
      }
      return {'ok': await api.sendRichMessageDraft(chat(), id, rich)};
    }

    final text = value('text');
    switch (kind) {
      case 'reply':
        final result = rich != null
            ? await api.sendRichMessage(chat(), rich, replyMarkup: keyboard)
            : await api.sendMessage(
                chat(),
                required('text'),
                parseMode: parseMode,
                replyMarkup: keyboard,
              );
        return {
          ...sent(result),
          if (arguments['widgetConfigured'] == true) 'widget': false,
        };
      case 'dice':
        return sent(await api.sendDice(chat()));
      case 'editText':
        if (value('inlineMessageId').isNotEmpty) {
          return {
            'ok': await api.editInlineMessageText(
              value('inlineMessageId'),
              rich == null ? required('text') : null,
              richMessage: rich,
              parseMode: rich == null ? parseMode : null,
              replyMarkup: inlineKeyboard(),
            ),
          };
        }
        return sent(
          await api.editMessageText(
            chat(),
            message(),
            rich == null ? required('text') : null,
            richMessage: rich,
            parseMode: rich == null ? parseMode : null,
            replyMarkup: inlineKeyboard(),
          ),
        );
      case 'editKeyboard':
        // An omitted keyboard explicitly removes the old inline keyboard.
        if (value('inlineMessageId').isNotEmpty) {
          return {
            'ok': await api.editInlineMessageReplyMarkup(
              value('inlineMessageId'),
              replyMarkup: inlineKeyboard(),
            ),
          };
        }
        return sent(
          await api.editMessageReplyMarkup(
            chat(),
            message(),
            replyMarkup: inlineKeyboard(),
          ),
        );
      case 'callbackAnswer':
        if (value('widgetQueryId').isNotEmpty) {
          if (utf8.encode(text).length > 1024) {
            throw const BuilderFailure(
              'A widget answer is limited to 1024 UTF-8 bytes.',
            );
          }
          final id = required('widgetQueryId');
          final answered = await api.answerWidgetQuery(
            id,
            data: text.isEmpty ? null : text,
          );
          if (answered) _answeredCallbacks.add('widget:$id');
          return {'ok': answered};
        }
        if (text.length > 200) {
          throw const BuilderFailure(
            'A button notification is limited to 200 characters.',
          );
        }
        final answered = await api.answerCallbackQuery(
          required('callbackId'),
          text: text,
          showAlert: arguments['showAlert'] == true,
        );
        _answeredCallbacks.add(required('callbackId'));
        return {'ok': answered};
      case 'inlineAnswer':
        return {
          'ok': await api.answerInlineQuery(
            required('inlineQueryId'),
            [
              InlineQueryResultArticle(
                id: 'answer',
                title: required('title'),
                inputMessageContent: InputTextMessageContent(
                  messageText: required('text'),
                  parseMode: parseMode,
                ),
                replyMarkup: inlineKeyboard(),
              ),
            ],
            cacheTime: 0,
            isPersonal: true,
          ),
        };
      case 'photo':
        return sent(
          await api.sendPhoto(
            chat(),
            media(),
            caption: text.isEmpty ? null : text,
            parseMode: parseMode,
            replyMarkup: keyboard,
          ),
        );
      case 'video':
        return sent(
          await api.sendVideo(
            chat(),
            media(),
            caption: text.isEmpty ? null : text,
            parseMode: parseMode,
            replyMarkup: keyboard,
          ),
        );
      case 'audio':
        return sent(
          await api.sendAudio(
            chat(),
            media(),
            caption: text.isEmpty ? null : text,
            parseMode: parseMode,
            replyMarkup: keyboard,
          ),
        );
      case 'document':
        return sent(
          await api.sendDocument(
            chat(),
            media(),
            caption: text.isEmpty ? null : text,
            parseMode: parseMode,
            replyMarkup: keyboard,
          ),
        );
      case 'animation':
        return sent(
          await api.sendAnimation(
            chat(),
            media(),
            caption: text.isEmpty ? null : text,
            parseMode: parseMode,
            replyMarkup: keyboard,
          ),
        );
      case 'voice':
        return sent(
          await api.sendVoice(
            chat(),
            media(),
            caption: text.isEmpty ? null : text,
            parseMode: parseMode,
            replyMarkup: keyboard,
          ),
        );
      case 'sticker':
        return sent(
          await api.sendSticker(chat(), media(), replyMarkup: inlineKeyboard()),
        );
      case 'deleteMessage':
        return {'ok': await api.deleteMessage(chat(), message())};
      case 'pinMessage':
        return {'ok': await api.pinChatMessage(chat(), message())};
      default:
        throw const BuilderFailure('Unsupported Telegram action.');
    }
  }
}
