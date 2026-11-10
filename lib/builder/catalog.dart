/// Shared labels and capabilities for the editor and execution validator.
abstract final class BuilderCatalog {
  static const labels = <String, String>{
    'renderList': 'Render list',
    'sql': 'Run SQL',
    'reply': 'Send text',
    'dice': 'Send dice',
    'editText': 'Edit message text',
    'editKeyboard': 'Edit message buttons',
    'callbackAnswer': 'Answer button click',
    'inlineAnswer': 'Answer inline query',
    'photo': 'Send photo',
    'video': 'Send video',
    'document': 'Send document',
    'audio': 'Send audio',
    'voice': 'Send voice',
    'animation': 'Send animation',
    'sticker': 'Send sticker',
    'deleteMessage': 'Delete message',
    'pinMessage': 'Pin message',
    'http': 'Call external API',
    'setVariable': 'Set variable',
    'incrementVariable': 'Increment variable',
    'condition': 'Check condition',
    'wait': 'Wait',
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
