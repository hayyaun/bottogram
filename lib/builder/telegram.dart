import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';
import 'engine.dart';
import 'values.dart';

/// Typed, supported Televerse methods retain the app's inbox transformers.
class BuilderTelegramPort implements BuilderTelegram {
  BuilderTelegramPort(this.api);
  final RawAPI api;
  final Set<String> _answeredCallbacks = {};
  bool takeCallbackAnswer(String id) => _answeredCallbacks.remove(id);
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
    final keyboard = keyboardJson == null
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

    final text = value('text');
    switch (kind) {
      case 'reply':
        return sent(
          await api.sendMessage(
            chat(),
            required('text'),
            parseMode: parseMode,
            replyMarkup: keyboard,
          ),
        );
      case 'dice':
        return sent(await api.sendDice(chat()));
      case 'editText':
        if (value('inlineMessageId').isNotEmpty) {
          return {
            'ok': await api.editInlineMessageText(
              value('inlineMessageId'),
              required('text'),
              parseMode: parseMode,
              replyMarkup: inlineKeyboard(),
            ),
          };
        }
        return sent(
          await api.editMessageText(
            chat(),
            message(),
            required('text'),
            parseMode: parseMode,
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
