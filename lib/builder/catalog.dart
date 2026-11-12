import 'package:flutter/widgets.dart';

import '../l10n/strings.dart';

/// Shared labels and capabilities for the editor and execution validator.
abstract final class BuilderCatalog {
  static String label(BuildContext context, String kind) => switch (kind) {
    'renderList' => context.strings.renderList,
    'sql' => context.strings.runSQL,
    'reply' => context.strings.sendText,
    'dice' => context.strings.sendDice,
    'editText' => context.strings.editMessageText,
    'editKeyboard' => context.strings.editMessageButtons,
    'callbackAnswer' => context.strings.answerButtonClick,
    'inlineAnswer' => context.strings.answerInlineQuery,
    'photo' => context.strings.sendPhoto,
    'video' => context.strings.sendVideo,
    'document' => context.strings.sendDocument,
    'audio' => context.strings.sendAudio,
    'voice' => context.strings.sendVoice,
    'animation' => context.strings.sendAnimation,
    'sticker' => context.strings.sendSticker,
    'deleteMessage' => context.strings.deleteMessage,
    'pinMessage' => context.strings.pinMessage,
    'http' => context.strings.callExternalAPI,
    'setVariable' => context.strings.setVariable,
    'incrementVariable' => context.strings.incrementVariable,
    'condition' => context.strings.checkCondition,
    'wait' => context.strings.wait,
    _ => kind,
  };
  static const media = {
    'photo',
    'video',
    'document',
    'audio',
    'voice',
    'animation',
    'sticker',
  };
  static const messages = {
    'reply',
    'editText',
    'inlineAnswer',
    'photo',
    'video',
    'document',
    'audio',
    'voice',
    'animation',
  };
  static const targets = {
    'editText',
    'editKeyboard',
    'deleteMessage',
    'pinMessage',
  };
  static const variables = {'setVariable', 'incrementVariable'};
  static bool hasChat(String kind) => !{
    'callbackAnswer',
    'inlineAnswer',
    'http',
    'setVariable',
    'incrementVariable',
    'condition',
    'renderList',
    'wait',
  }.contains(kind);
}
