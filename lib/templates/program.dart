import 'dart:convert';
import '../builder/store.dart';
import '../builder/values.dart';
import '../units/virt_act.dart';
import '../units/virt_event.dart';
import 'model.dart';
export '../units/virt_act.dart';
export '../units/virt_event.dart';
export 'model.dart';

typedef Acts = List<VirtAct>;
Map<String, dynamic> when(String left, dynamic right, [String op = 'equals']) =>
    {'left': left, 'operator': op, 'right': right};
Map<String, dynamic> button(String text, String data) => {
  'text': text,
  'callback_data': data,
};
Map<String, dynamic> keyboard(List<List<Map<String, dynamic>>> rows) => {
  'inline_keyboard': rows,
};
VirtAct sql(
  String name,
  String statement, [
  List<dynamic> parameters = const [],
  Map<String, dynamic> config = const {},
]) => templateAction(VirtActType.sql, statement, name, {
  'parameters': jsonEncode(parameters),
  ...config,
});
VirtAct say(
  String name,
  String text, {
  Map<String, dynamic>? buttons,
  Map<String, dynamic>? only,
  List<Map<String, dynamic>>? rich,
  String? draftId,
}) => templateAction(VirtActType.reply, text, name, {
  if (buttons != null) 'keyboard': buttons,
  if (rich != null) 'richBlocks': jsonEncode(rich),
  if (draftId != null) 'draftId': draftId,
  if (only != null) 'when': only,
});
Map<String, dynamic> heading(String text) => {'type': 'heading', 'text': text};
Map<String, dynamic> paragraph(String text) => {
  'type': 'paragraph',
  'text': text,
};
Map<String, dynamic> details(String summary, String body) => {
  'type': 'details',
  'summary': summary,
  'blocks': [paragraph(body)],
};
Map<String, dynamic> bullets(List<String> items) => {
  'type': 'list',
  'items': items,
};

VirtAct setValue(
  String name,
  dynamic value, {
  String scope = 'user',
  Map<String, dynamic>? only,
}) => templateAction(VirtActType.setVariable, value.toString(), 'set_$name', {
  'variable': name,
  'scope': scope,
  if (only != null) 'when': only,
});
VirtAct check(
  String name,
  String left,
  dynamic right, [
  String op = 'equals',
]) => templateAction(VirtActType.condition, '', name, when(left, right, op));
VirtAct render(
  String name,
  String items,
  String row, {
  String header = '',
  String empty = 'No results yet.',
  String footer = '',
  List<Map<String, dynamic>> buttons = const [],
  List<List<Map<String, dynamic>>> footerButtons = const [],
  Map<String, String>? columns,
  List<Map<String, dynamic>>? rowBlocks,
  bool buttonsInMessage = false,
  String? photoField,
  List<String> photoHosts = const [],
}) => templateAction(VirtActType.renderList, row, name, {
  'items': items,
  'richLayout': {
    if (columns != null) 'columns': columns,
    if (rowBlocks != null) 'rowBlocks': rowBlocks,
    if (buttonsInMessage) 'buttonsInMessage': true,
    if (photoField != null) 'photoField': photoField,
    if (photoHosts.isNotEmpty) 'photoHosts': photoHosts,
  },
  'header': header,
  'emptyText': empty,
  'footer': footer,
  'separator': '\n\n',
  'buttons': jsonEncode(buttons),
  'footerButtons': jsonEncode(footerButtons),
});
VirtAct sendList(
  String name, {
  String output = 'sent',
  Map<String, dynamic>? only,
}) => templateAction(VirtActType.reply, '{{steps.$name.text}}', output, {
  'keyboardOutput': '{{steps.$name.keyboard}}',
  'richBlocks': jsonEncode('{{steps.$name.rich}}'),
  if (only != null) 'when': only,
});
VariableDefinition variable(
  String name,
  dynamic initial, {
  String scope = 'user',
}) => VariableDefinition(
  name,
  scope,
  initial is bool
      ? 'boolean'
      : initial is num
      ? 'number'
      : 'text',
  initial,
);

class TemplateProgram {
  TemplateProgram(this.setup, [List<VariableDefinition> definitions = const []])
    : variables = [
        variable('initialized', false, scope: 'bot'),
        ...definitions,
      ];
  final Acts setup;
  final List<VariableDefinition> variables;
  final events = <VirtEvent>[];
  void on(VirtEventType type, String query, Acts actions, {String? match}) {
    final event = VirtEvent(type: type, query: query)
      ..config = {if (match != null) 'match': match};
    event.acts = [
      say(
        'private_notice',
        'Please open this bot in a private chat to use it.',
        only: when('{{event.chatId}}', '{{event.userId}}', 'notEquals'),
      ),
      check('private_only', '{{event.chatId}}', '{{event.userId}}'),
      for (final action in setup)
        VirtAct(type: action.type, text: action.text)
          ..config = {
            ...action.config,
            'when': when('{{bot.initialized}}', false),
          },
      setValue(
        'initialized',
        true,
        scope: 'bot',
        only: when('{{bot.initialized}}', false),
      ),
      ...actions,
    ];
    if (event.acts.length > 64) {
      throw StateError('Template exceeds the action budget.');
    }
    final names = <String>{};
    for (final action in event.acts) {
      final original = action.config['output'] as String;
      var name = original, suffix = 2;
      while (names.contains(name) && action.type == VirtActType.setVariable) {
        name = '${original}_${suffix++}';
      }
      if (!names.add(name)) {
        throw StateError('Duplicate output names: $query / $name');
      }
      action.config['output'] = name;
    }
    events.add(event);
  }

  void command(String name, Acts actions) =>
      on(VirtEventType.command, name, actions);
  void click(String data, Acts actions, {bool prefix = false}) => on(
    VirtEventType.callbackQuery,
    data,
    actions,
    match: prefix ? 'prefix' : 'exact',
  );
  void text(Acts actions) =>
      on(VirtEventType.text, 'Text input', actions, match: 'any');
  BotTemplateDraft get draft => BotTemplateDraft(events, variables);
}

VirtAct seed(
  String table,
  List<String> columns,
  List<Map<String, dynamic>> rows,
) {
  if (rows.isEmpty || rows.length > 20 || rows.length * columns.length > 240) {
    throw const BuilderFailure(
      'Sample content needs 1–20 rows within 240 fields.',
    );
  }
  return sql(
    'seed_$table',
    'INSERT OR IGNORE INTO $table (${columns.join(',')}) VALUES ${rows.map((_) => '(${List.filled(columns.length, '?').join(',')})').join(',')}',
    [
      for (final row in rows)
        for (final column in columns) row[column],
    ],
  );
}
