import 'dart:convert';
import 'package:flutter/material.dart';
import '../ui/design.dart';
import '../units/virt_act.dart';
import '../widgets/builder_part_picker.dart';
import 'catalog.dart';
import 'engine.dart';
import 'parts.dart';
import 'store.dart';
import 'text_editor.dart';
import 'values.dart';

/// Edits an isolated draft. The caller commits only the validated result.
class BuilderStepEditor extends StatefulWidget {
  const BuilderStepEditor({
    super.key,
    required this.initial,
    required this.onSave,
    this.references = const [],
    this.keyboard,
    this.onDelete,
    this.onAddToLibrary,
    this.libraryName,
    this.onRenameOutput,
  });
  final BuilderStep initial;
  final Future<void> Function(BuilderStep value) onSave;
  final VoidCallback? onDelete;
  final Future<void> Function(BuilderStep value)? onAddToLibrary;
  final String? libraryName;
  final VoidCallback? onRenameOutput;
  final List<String> references;
  final Widget? keyboard;
  @override
  State<BuilderStepEditor> createState() => _BuilderStepEditorState();
}

class _BuilderStepEditorState extends State<BuilderStepEditor> {
  final _fields = <String, TextEditingController>{};
  final _form = GlobalKey<FormState>();
  late String _format, _method, _scope, _onError, _operator;
  late bool _showAlert, _conditional;
  late Map<String, dynamic> _layout = Map<String, dynamic>.from(
    widget.initial.config['richLayout'] as Map? ?? {},
  );
  late bool _hasRichLayout = widget.initial.config['richLayout'] is Map;
  late bool _groupItemButtons = _layout['groupItemButtons'] == true;
  late String? _sharedList = widget.initial.config['sharedList'] as String?;
  String? _newListLabel;
  late bool _widgetQueries = widget.initial.config['widgetQueries'] == true;
  var _saving = false;
  String? _error;
  String get kind => widget.initial.kind;
  TextEditingController field(String name, [String fallback = '']) =>
      _fields.putIfAbsent(
        name,
        () => TextEditingController(
          text: name == 'text'
              ? widget.initial.text
              : widget.initial.config[name]?.toString() ?? fallback,
        ),
      );
  @override
  void initState() {
    super.initState();
    final config = widget.initial.config;
    _format = config['format']?.toString() ?? 'plain';
    _method = config['method']?.toString() ?? 'GET';
    _scope = config['scope']?.toString() ?? 'user';
    _onError = config['onError']?.toString() ?? 'stop';
    _showAlert = config['showAlert'] == true;
    _conditional = config['when'] is Map;
    final condition = kind == 'condition'
        ? config
        : Map<String, dynamic>.from(config['when'] as Map? ?? {});
    _operator = condition['operator']?.toString() ?? 'equals';
    for (final key in ['left', 'right']) {
      _fields[key] = TextEditingController(
        text: condition[key]?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String value(String name) =>
      _fields[name]?.text ?? widget.initial.config[name]?.toString() ?? '';
  Future<void> _chooseList() async {
    final store = BuilderStore.shared;
    final entries = store.parts.lists;
    final id = await pickBuilderPart(context, 'List library', entries);
    if (id == null || !mounted) return;
    final list = entries[id]!;
    final config = list['config'] as Map;
    setState(() {
      _newListLabel = null;
      _sharedList = id;
      field('text').text = list['text'] as String;
      for (final entry in BuilderParts.listDefaults.entries) {
        field(entry.key).text = config[entry.key]?.toString() ?? entry.value;
      }
      _hasRichLayout = config['richLayout'] is Map;
      _layout = Map<String, dynamic>.from(config['richLayout'] as Map? ?? {});
      _groupItemButtons = _layout['groupItemButtons'] == true;
    });
  }

  Future<void> _nameList() async {
    final name = await nameBuilderPart(context, 'Save list to library');
    if (name == null || !mounted) return;
    setState(() {
      _sharedList = BuilderParts.newId();
      _newListLabel = name;
    });
  }

  Widget _listRows(String fieldName, {required bool footer}) {
    final Object? parsed;
    try {
      final text = value(fieldName).trim();
      parsed = jsonDecode(text.isEmpty ? '[]' : text);
    } on FormatException {
      return const SizedBox.shrink();
    }
    final rows = footer
        ? List<dynamic>.of(parsed is List ? parsed : [])
        : [parsed];
    final local = [
      for (final row in rows)
        if (row is List) row,
    ];
    void update(List<dynamic> values) => setState(() {
      field(fieldName).text = const JsonEncoder.withIndent(
        '  ',
      ).convert(footer ? values : values.firstOrNull ?? []);
    });
    return BuilderRowLibrary(
      kind: BuilderParts.inline,
      allowConditions: true,
      allowItemBindings: !footer,
      localRows: local,
      links: [
        for (final row in rows)
          if (row is Map && row['ref'] is String) row['ref'] as String,
      ],
      onSaveAndLink: (index, id) {
        final raw = [
          for (final (i, row) in rows.indexed)
            if (row is List) i,
        ];
        rows[raw[index]] = {'ref': id};
        update(rows);
      },
      onLink: (id) => update([
        if (footer) ...rows,
        {'ref': id},
      ]),
      onUnlink: (id) {
        final index = rows.indexWhere((row) => row is Map && row['ref'] == id);
        if (index != -1) update(rows..removeAt(index));
      },
    );
  }

  bool _rowRef(Object? value) =>
      value is Map && value.length == 1 && value['ref'] is String;

  Future<void> save({Future<void> Function(BuilderStep)? commit}) async {
    if (!_form.currentState!.validate()) return;
    final config = <String, dynamic>{...widget.initial.config};
    try {
      if (kind == 'reply' || kind == 'editText') {
        final content = value('richBlocks').trim();
        if (content.isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is! List && decoded is! String) {
            throw const BuilderFailure(
              'Enter rich blocks as an array or a quoted output reference.',
            );
          }
        }
        if (kind == 'reply' &&
            value('draftId').trim().isNotEmpty &&
            content.isEmpty) {
          throw const BuilderFailure('A draft requires rich message content.');
        }
        final data = value('widgetChatData').trim();
        if (data.isNotEmpty) jsonDecode(data);
        final html = value('widgetHtml');
        if (kind == 'reply' &&
            html.isNotEmpty &&
            (utf8.encode(html).length > 32768 || html.codeUnits.contains(0))) {
          throw const BuilderFailure(
            'Widget HTML must fit in 32768 UTF-8 bytes.',
          );
        }
        if (kind == 'reply' &&
            html.trim().isNotEmpty &&
            value('draftId').trim().isNotEmpty) {
          throw const BuilderFailure(
            'Choose either a widget or a rich message draft.',
          );
        }
        if (kind == 'reply') {
          config['widgetQueries'] = _widgetQueries;
        }
      }
      if (kind == 'renderList') {
        final layout = Map.of(_layout);
        if (_groupItemButtons && layout['columns'] != null) {
          throw const BuilderFailure(
            'Buttons next to items require a list layout.',
          );
        }
        if (_groupItemButtons) {
          layout['groupItemButtons'] = true;
          config['richLayout'] = layout;
        } else if (_hasRichLayout) {
          config['richLayout'] = layout..remove('groupItemButtons');
        } else {
          config.remove('richLayout');
        }
        final itemData = value('itemData').trim();
        if (itemData.isNotEmpty) jsonDecode(itemData);
        final item = jsonDecode(
          value('buttons').trim().isEmpty ? '[]' : value('buttons'),
        );
        final footer = jsonDecode(
          value('footerButtons').trim().isEmpty ? '[]' : value('footerButtons'),
        );
        if (item is! List && !_rowRef(item) ||
            footer is! List ||
            footer.any((row) => row is! List && !_rowRef(row))) {
          throw const BuilderFailure(
            'Enter button arrays or choose saved rows.',
          );
        }
      }
      if (kind == 'sql') {
        final parsed = jsonDecode(
          value('parameters').isEmpty ? '[]' : value('parameters'),
        );
        if (parsed is! List) {
          throw const BuilderFailure('SQL parameters must be a JSON array.');
        }
      }
      if (kind == 'http') {
        for (final key in ['headers', 'body']) {
          final source = value(key).trim();
          if (source.isNotEmpty) jsonDecode(source);
        }
        final headers = jsonDecode(
          value('headers').trim().isEmpty ? '{}' : value('headers'),
        );
        if (headers is! Map || headers.values.any((v) => v is! String)) {
          throw const BuilderFailure(
            'Headers must be a JSON object of strings.',
          );
        }
        final url = Uri.tryParse(
          value('url').replaceAll(BuilderValues.reference, 'binding'),
        );
        if (url == null ||
            !{'http', 'https'}.contains(url.scheme) ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty ||
            url.hasFragment) {
          throw const BuilderFailure(
            'Enter an HTTP(S) URL without embedded credentials or a fragment.',
          );
        }
        config.addAll({'method': _method});
      }
      for (final entry in _fields.entries) {
        if (!{'text', 'left', 'right'}.contains(entry.key)) {
          config[entry.key] = entry.value.text;
        }
      }
      config.addAll({
        'format': _format,
        'scope': _scope,
        'onError': _onError,
        'showAlert': _showAlert,
      });
      if (kind == 'condition' || _conditional) {
        final original = config['when'];
        final condition = {
          'left': value('left'),
          'operator': _operator,
          'right': value('right'),
        };
        if (kind == 'condition') {
          config.addAll(condition);
        } else if (original is! Map || original['all'] is! List) {
          config['when'] = condition;
        }
      } else {
        config.remove('when');
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      if (kind == 'renderList') {
        if (_sharedList case final id?) {
          final store = BuilderStore.shared;
          final previous = store.parts.lists[id];
          final label = _newListLabel ?? previous?['label'] as String?;
          if (label == null) {
            throw const BuilderFailure('Choose a list from the library.');
          }
          final definition = BuilderParts.list(
            label,
            VirtAct(type: VirtActType.renderList, text: field('text').text)
              ..config = config,
          );
          if (previous == null ||
              !BuilderParts.sameList(previous, definition)) {
            await store.savePart(id, definition, isList: true);
            _newListLabel = null;
          }
          config.removeWhere((key, _) => BuilderParts.listFields.contains(key));
          config['sharedList'] = id;
        } else {
          config.remove('sharedList');
        }
      }
      await (commit ?? widget.onSave)(
        BuilderStep(
          kind,
          _sharedList == null ? field('text').text : '',
          config,
        ),
      );
    } on FormatException {
      if (mounted) {
        setState(
          () => _error =
              'Invalid JSON. Put references such as {{steps.lookup.body.id}} inside JSON strings.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is BuilderFailure
              ? error.message
              : 'The action could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(BuilderCatalog.labels[kind] ?? kind),
      actions: [
        if (widget.onAddToLibrary case final add?)
          IconButton(
            tooltip: 'Save to action library',
            onPressed: _saving ? null : () => save(commit: add),
            icon: const Icon(Icons.library_add_outlined),
          ),
        if (widget.onDelete != null)
          IconButton(
            tooltip: widget.libraryName == null
                ? 'Delete action'
                : 'Remove from event',
            onPressed: _saving ? null : widget.onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: BContent(
        maxWidth: 840,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.libraryName case final String name) ...[
                BNotice(
                  message:
                      'Shared action: $name. Saving updates every event using it.',
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Output name in this event'),
                  subtitle: Text(widget.initial.config['output'].toString()),
                  trailing: TextButton(
                    onPressed: _saving ? null : widget.onRenameOutput,
                    child: const Text('Edit'),
                  ),
                ),
              ] else
                _input(
                  'output',
                  'Output name',
                  required: true,
                  help:
                      'Later actions can use {{steps.${value('output').isEmpty ? 'name' : value('output')}.${kind == 'http'
                          ? 'body.field'
                          : kind == 'sql'
                          ? 'rows.0.field'
                          : kind == 'renderList'
                          ? 'text'
                          : BuilderCatalog.variables.contains(kind)
                          ? 'value'
                          : kind == 'condition'
                          ? 'matched'
                          : 'messageId'}}}.',
                  validate: (v) => BuilderValues.name.hasMatch(v)
                      ? null
                      : 'Use letters, numbers and underscores; start with a letter or underscore.',
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: BNotice(message: _error!, error: true),
                ),
              const SizedBox(height: 16),
              if (kind == 'renderList') ...[
                if (_sharedList case final id?)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link),
                    title: Text(
                      _newListLabel ??
                          BuilderStore.shared.parts.lists[id]?['label']
                              as String? ??
                          'Unavailable list',
                    ),
                    subtitle: const Text(
                      'Layout edits apply to every linked list.',
                    ),
                    trailing: TextButton(
                      onPressed: () => setState(() {
                        _sharedList = null;
                        _newListLabel = null;
                      }),
                      child: const Text('Make local copy'),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _chooseList,
                      child: const Text('Choose saved list'),
                    ),
                    if (_sharedList == null)
                      TextButton(
                        onPressed: _nameList,
                        child: const Text('Save list to library'),
                      ),
                  ],
                ),
                _input(
                  'items',
                  'Items reference',
                  required: true,
                  help:
                      'Example: {{steps.query.rows}} or {{steps.lookup.body}}. At most 50 items.',
                ),
                _input(
                  'text',
                  'Text for each item',
                  lines: 3,
                  help:
                      'Use {{item.title}}, {{item.price}} and {{index}} (starting at 1).',
                ),
                _input('header', 'Heading', lines: 2),
                _input('separator', 'Separator', fallback: '\n', lines: 2),
                _input(
                  'emptyText',
                  'When the list is empty',
                  fallback: 'No results yet.',
                ),
                _input('footer', 'Footer', lines: 2),
                _input(
                  'buttons',
                  'Buttons for each item (JSON array)',
                  fallback: '[]',
                  lines: 3,
                  help:
                      'Example: [{"text":"{{item.title}}","callback_data":"open:{{item.id}}"}]',
                ),
                _listRows('buttons', footer: false),
                _input(
                  'footerButtons',
                  'Footer button rows (JSON array)',
                  fallback: '[]',
                  lines: 3,
                  help: 'Example: [[{"text":"Back","callback_data":"home"}]]',
                ),
                _listRows('footerButtons', footer: true),
                _input(
                  'itemData',
                  'Data for each item (optional JSON)',
                  lines: 2,
                  help:
                      'Use bindings such as {{item.title}}. Read the array from this action’s items output.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Place buttons next to each item'),
                  subtitle: const Text(
                    'Bind the rich output to the next message. Footer buttons stay below the message.',
                  ),
                  value: _groupItemButtons,
                  onChanged: (value) =>
                      setState(() => _groupItemButtons = value),
                ),
                const Text(
                  'Bind text or rich content and the keyboard output to the next message action.',
                ),
              ] else if (kind == 'sql') ...[
                _input(
                  'text',
                  'SQL statement',
                  required: true,
                  lines: 6,
                  help:
                      'One statement on this bot’s database. Use ? for values; bind them below.',
                ),
                _input(
                  'parameters',
                  'Parameters (JSON array)',
                  fallback: '[]',
                  lines: 3,
                  help:
                      'Example: ["{{event.userId}}", "{{user.score}}"]. Values are bound, never inserted into SQL text.',
                ),
                const Text(
                  'Create and query your own tables. File access, attachments, extensions and Bottogram’s reserved table are blocked. Limit results to 500 rows; each statement has a 2-second budget.',
                ),
              ] else if (kind == 'http') ...[
                _select('Method', _method, const [
                  'GET',
                  'POST',
                  'PUT',
                  'PATCH',
                  'DELETE',
                ], (v) => setState(() => _method = v)),
                _input(
                  'url',
                  'API URL',
                  required: true,
                  help:
                      'Fixed host; bind values in the path or query, e.g. /users/{{event.userId}}.',
                ),
                _input(
                  'credential',
                  'Saved bearer credential',
                  help:
                      'Credential name from this bot’s credentials. Leave blank for no bearer token.',
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Headers and JSON body'),
                  initiallyExpanded:
                      value('body').isNotEmpty || value('headers').isNotEmpty,
                  children: [
                    _input(
                      'headers',
                      'Headers (JSON)',
                      fallback: '{}',
                      lines: 3,
                      help:
                          'Do not paste API keys here. Use a saved credential for bearer authentication.',
                    ),
                    if (_method != 'GET')
                      _input(
                        'body',
                        'Body (JSON)',
                        lines: 5,
                        help:
                            'Example: {"id":"{{event.userId}}","amount":"{{steps.lookup.body.price}}"}',
                      ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Calls run on this device. 22 s timeout · 1 MiB response limit · no automatic write retries.',
                  ),
                ),
              ] else if (BuilderCatalog.variables.contains(kind)) ...[
                _select('Variable scope', _scope, const [
                  'user',
                  'bot',
                ], (v) => setState(() => _scope = v)),
                _input(
                  'variable',
                  'Variable name',
                  required: true,
                  help:
                      'Create the variable in this bot’s Variables page first.',
                ),
                _input(
                  'text',
                  kind == 'incrementVariable' ? 'Amount to add' : 'New value',
                  required: true,
                  help:
                      'A literal value or reference such as {{steps.lookup.body.points}}.',
                ),
              ] else if (kind == 'condition')
                ..._conditionFields()
              else if (kind == 'wait')
                _input('text', 'Seconds (0–60)', required: true)
              else ...[
                if (BuilderCatalog.media.contains(kind))
                  _input(
                    'media',
                    'Media HTTP(S) URL or Telegram file ID',
                    required: true,
                  ),
                if (kind == 'inlineAnswer')
                  _input(
                    'title',
                    'Result title',
                    required: true,
                    fallback: 'Result',
                  ),
                if (BuilderCatalog.messages.contains(kind)) ...[
                  _select('Text format', _format, const [
                    'plain',
                    'MarkdownV2',
                  ], (v) => setState(() => _format = v)),
                  TelegramTextEditor(
                    controller: field('text'),
                    references: widget.references,
                    markdown: _format == 'MarkdownV2',
                    label: BuilderCatalog.media.contains(kind)
                        ? 'Caption'
                        : 'Message',
                  ),
                ],
                if (kind == 'reply' || kind == 'editText')
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Rich message'),
                    initiallyExpanded: value('richBlocks').isNotEmpty,
                    children: [
                      _input(
                        'richBlocks',
                        'Rich blocks (JSON)',
                        lines: 5,
                        help:
                            'Use a block array or a quoted reference such as "{{steps.list.rich}}". Leave blank to send the text above.',
                      ),
                      if (kind == 'reply')
                        _input(
                          'draftId',
                          'Draft ID',
                          help:
                              'Private chat preview. Use {{event.updateId}}, then send the finished message in a later action.',
                        ),
                    ],
                  ),
                if (kind == 'reply' || kind == 'editText')
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Telegram widget'),
                    initiallyExpanded:
                        value('widgetHtml').isNotEmpty ||
                        value('widgetChatData').isNotEmpty,
                    children: [
                      if (kind == 'reply') ...[
                        _input(
                          'widgetHtml',
                          'Widget HTML',
                          lines: 6,
                          help:
                              'Self-contained HTML for a private chat widget. Leave blank to send a normal message.',
                        ),
                        _input(
                          'widgetCaption',
                          'Widget caption',
                          help:
                              'Shown below the widget, including in clients that cannot display it.',
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Allow widget requests'),
                          value: _widgetQueries,
                          onChanged: (value) =>
                              setState(() => _widgetQueries = value),
                        ),
                      ],
                      _input(
                        'widgetChatData',
                        'Widget chat data (JSON)',
                        lines: 3,
                        help:
                            'Up to 1024 UTF-8 bytes. The widget reads it from TelegramWidget.chatData.',
                      ),
                    ],
                  ),
                if (kind == 'callbackAnswer') ...[
                  _input(
                    'text',
                    'Notification text',
                    help:
                        'Up to 200 characters. Leave blank to acknowledge the click.',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show as alert'),
                    value: _showAlert,
                    onChanged: (v) => setState(() => _showAlert = v),
                  ),
                ],
                if (widget.keyboard != null &&
                    (BuilderCatalog.messages.contains(kind) ||
                        kind == 'editKeyboard'))
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: widget.keyboard,
                  ),
                if (BuilderCatalog.messages.contains(kind) ||
                    kind == 'editKeyboard')
                  _input(
                    'keyboardOutput',
                    'Keyboard output reference',
                    help:
                        'Example: {{steps.list.keyboard}}. When set, replaces the static keyboard.',
                  ),
                if (BuilderCatalog.hasChat(kind))
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Target'),
                    subtitle: const Text(
                      'Defaults to the conversation and triggering message',
                    ),
                    initiallyExpanded: BuilderCatalog.targets.contains(kind),
                    children: [
                      _input(
                        'chatId',
                        'Chat ID or channel username',
                        help:
                            'Blank uses the current chat. A reference can use an earlier step’s chatId.',
                      ),
                      if (BuilderCatalog.targets.contains(kind))
                        _input(
                          'messageId',
                          'Message ID',
                          help:
                              'Blank uses the triggering message. Example: {{steps.sent.messageId}}.',
                        ),
                    ],
                  ),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Execution'),
                children: [
                  _select('On failure', _onError, const [
                    'stop',
                    'continue',
                  ], (v) => setState(() => _onError = v)),
                  const Text(
                    'Continue exposes steps.<name>.ok = false and steps.<name>.error to later actions.',
                  ),
                  if (kind != 'condition') ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Run only when a condition matches'),
                      value: _conditional,
                      onChanged: (v) => setState(() => _conditional = v),
                    ),
                    if (_conditional) ..._conditionFields(),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : save,
                icon: const Icon(Icons.check),
                label: Text(_saving ? 'Saving…' : 'Save action'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
  List<Widget> _conditionFields() => [
    _input(
      'left',
      'Left value',
      help: 'Literal text or a reference such as {{user.score}}.',
    ),
    _select('Comparison', _operator, const [
      'equals',
      'notEquals',
      'contains',
      'greater',
      'less',
    ], (v) => setState(() => _operator = v)),
    _input('right', 'Right value'),
  ];
  Widget _select(
    String label,
    String selected,
    List<String> options,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      initialValue: options.contains(selected) ? selected : options.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in options) DropdownMenuItem(value: v, child: Text(v)),
      ],
      onChanged: (v) {
        if (v != null) change(v);
      },
    ),
  );
  Widget _input(
    String key,
    String label, {
    String fallback = '',
    bool required = false,
    String? help,
    int lines = 1,
    String? Function(String)? validate,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: field(key, fallback),
      onChanged: {'buttons', 'footerButtons'}.contains(key)
          ? (_) => setState(() {})
          : null,
      minLines: lines,
      maxLines: lines == 1 ? 1 : 10,
      decoration: InputDecoration(
        labelText: label,
        helperText: help,
        helperMaxLines: 4,
        alignLabelWithHint: lines > 1,
      ),
      validator: (v) {
        final text = v ?? '';
        if (required && text.trim().isEmpty) return 'This field is required.';
        if (text.length > 65536) return 'This field exceeds 64 KiB.';
        return validate?.call(text);
      },
    ),
  );
}
