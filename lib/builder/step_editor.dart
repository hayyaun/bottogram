import 'dart:convert';

import 'package:bottogram/l10n/strings.dart';
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
  late bool _sendToAdmins = widget.initial.config['sendToAdmins'] == true;
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
    final id = await pickBuilderPart(
      context,
      context.strings.listLibrary,
      entries,
    );
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
    final name = await nameBuilderPart(
      context,
      context.strings.saveListToLibrary,
    );
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
            throw BuilderFailure(context.strings.enterRichBlocksAsAnArray);
          }
        }
        if (kind == 'reply' &&
            value('draftId').trim().isNotEmpty &&
            content.isEmpty) {
          throw BuilderFailure(
            context.strings.aDraftRequiresRichMessageContent,
          );
        }
        final data = value('widgetChatData').trim();
        if (data.isNotEmpty) jsonDecode(data);
        final html = value('widgetHtml');
        if (kind == 'reply' &&
            html.isNotEmpty &&
            (utf8.encode(html).length > 32768 || html.codeUnits.contains(0))) {
          throw BuilderFailure(context.strings.widgetHTMLMustFitIn32768);
        }
        if (kind == 'reply' &&
            html.trim().isNotEmpty &&
            value('draftId').trim().isNotEmpty) {
          throw BuilderFailure(context.strings.chooseEitherAWidgetOrA);
        }
        if (kind == 'reply') {
          config['widgetQueries'] = _widgetQueries;
          if (_sendToAdmins) {
            config['sendToAdmins'] = true;
          } else {
            config.remove('sendToAdmins');
          }
        }
      }
      if (kind == 'renderList') {
        final layout = Map.of(_layout);
        if (_groupItemButtons && layout['columns'] != null) {
          throw BuilderFailure(context.strings.buttonsNextToItemsRequireA);
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
          throw BuilderFailure(context.strings.enterButtonArraysOrChooseSaved);
        }
      }
      if (kind == 'sql') {
        final parsed = jsonDecode(
          value('parameters').isEmpty ? '[]' : value('parameters'),
        );
        if (parsed is! List) {
          throw BuilderFailure(context.strings.sqlParametersMustBeAJSON);
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
          throw BuilderFailure(context.strings.headersMustBeAJSONObject);
        }
        final url = Uri.tryParse(
          value('url').replaceAll(BuilderValues.reference, 'binding'),
        );
        if (url == null ||
            !{'http', 'https'}.contains(url.scheme) ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty ||
            url.hasFragment) {
          throw BuilderFailure(context.strings.enterAnHTTPSURLWithout);
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
            throw BuilderFailure(context.strings.chooseAListFromTheLibrary);
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
        setState(() => _error = context.strings.invalidJSONPutReferencesSuchAs);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is BuilderFailure
              ? error.message
              : context.strings.theActionCouldNotBeSaved,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(BuilderCatalog.label(context, kind)),
      actions: [
        if (widget.onAddToLibrary case final add?)
          IconButton(
            tooltip: context.strings.saveToActionLibrary,
            onPressed: _saving ? null : () => save(commit: add),
            icon: const Icon(Icons.library_add_outlined),
          ),
        if (widget.onDelete != null)
          IconButton(
            tooltip: widget.libraryName == null
                ? context.strings.deleteAction
                : context.strings.removeFromEvent,
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
                BNotice(message: context.strings.sharedActionNotice(name)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.strings.outputNameInThisEvent),
                  subtitle: Text(widget.initial.config['output'].toString()),
                  trailing: TextButton(
                    onPressed: _saving ? null : widget.onRenameOutput,
                    child: Text(context.strings.edit),
                  ),
                ),
              ] else
                _input(
                  'output',
                  context.strings.outputName,
                  required: true,
                  help: context.strings.actionOutputReferenceHint(
                    context.leftToRightText(
                      '{{steps.${value('output').isEmpty ? 'name' : value('output')}.${kind == 'http'
                          ? 'body.field'
                          : kind == 'sql'
                          ? 'rows.0.field'
                          : kind == 'renderList'
                          ? 'text'
                          : BuilderCatalog.variables.contains(kind)
                          ? 'value'
                          : kind == 'condition'
                          ? 'matched'
                          : 'messageId'}}}',
                    ),
                  ),
                  validate: (v) => BuilderValues.name.hasMatch(v)
                      ? null
                      : context.strings.useLettersNumbersAndUnderscoresStart,
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
                          context.strings.unavailableList,
                    ),
                    subtitle: Text(
                      context.strings.layoutEditsApplyToEveryLinked,
                    ),
                    trailing: TextButton(
                      onPressed: () => setState(() {
                        _sharedList = null;
                        _newListLabel = null;
                      }),
                      child: Text(context.strings.makeLocalCopy),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _chooseList,
                      child: Text(context.strings.chooseSavedList),
                    ),
                    if (_sharedList == null)
                      TextButton(
                        onPressed: _nameList,
                        child: Text(context.strings.saveListToLibrary),
                      ),
                  ],
                ),
                _input(
                  'items',
                  context.strings.itemsReference,
                  required: true,
                  help: context.strings.exampleStepsQueryRowsOrSteps,
                ),
                _input(
                  'text',
                  context.strings.textForEachItem,
                  lines: 3,
                  help: context.strings.useItemTitleItemPriceAnd,
                ),
                _input('header', context.strings.heading, lines: 2),
                _input(
                  'separator',
                  context.strings.separator,
                  fallback: '\n',
                  lines: 2,
                ),
                _input(
                  'emptyText',
                  context.strings.whenTheListIsEmpty,
                  fallback: 'No results yet.',
                ),
                _input('footer', context.strings.footer, lines: 2),
                _input(
                  'buttons',
                  context.strings.buttonsForEachItemJSONArray,
                  fallback: '[]',
                  lines: 3,
                  help: context.strings.exampleTextItemTitleCallbackData,
                ),
                _listRows('buttons', footer: false),
                _input(
                  'footerButtons',
                  context.strings.footerButtonRowsJSONArray,
                  fallback: '[]',
                  lines: 3,
                  help: context.strings.exampleTextBackCallbackDataHome,
                ),
                _listRows('footerButtons', footer: true),
                _input(
                  'itemData',
                  context.strings.dataForEachItemOptionalJSON,
                  lines: 2,
                  help: context.strings.useBindingsSuchAsItemTitle,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.strings.placeButtonsNextToEachItem),
                  subtitle: Text(context.strings.bindTheRichOutputToThe),
                  value: _groupItemButtons,
                  onChanged: (value) =>
                      setState(() => _groupItemButtons = value),
                ),
                Text(context.strings.bindTextOrRichContentAnd),
              ] else if (kind == 'sql') ...[
                _input(
                  'text',
                  context.strings.sqlStatement,
                  required: true,
                  lines: 6,
                  help: context.strings.oneStatementOnThisBotS,
                ),
                _input(
                  'parameters',
                  context.strings.parametersJSONArray,
                  fallback: '[]',
                  lines: 3,
                  help: context.strings.exampleEventUserIdUserScoreValues,
                ),
                Text(context.strings.createAndQueryYourOwnTables),
              ] else if (kind == 'http') ...[
                _select(context.strings.method, _method, const [
                  'GET',
                  'POST',
                  'PUT',
                  'PATCH',
                  'DELETE',
                ], (v) => setState(() => _method = v)),
                _input(
                  'url',
                  context.strings.apiURL,
                  required: true,
                  help: context.strings.fixedHostBindValuesInThe,
                ),
                _input(
                  'credential',
                  context.strings.savedBearerCredential,
                  help: context.strings.credentialNameFromThisBotS,
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(context.strings.headersAndJSONBody),
                  initiallyExpanded:
                      value('body').isNotEmpty || value('headers').isNotEmpty,
                  children: [
                    _input(
                      'headers',
                      context.strings.headersJSON,
                      fallback: '{}',
                      lines: 3,
                      help: context.strings.doNotPasteAPIKeysHere,
                    ),
                    if (_method != 'GET')
                      _input(
                        'body',
                        context.strings.bodyJSON,
                        lines: 5,
                        help: context.strings.exampleIdEventUserIdAmountSteps,
                      ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(context.strings.callsRunOnThisDevice22),
                ),
              ] else if (BuilderCatalog.variables.contains(kind)) ...[
                _select(context.strings.variableScope, _scope, const [
                  'user',
                  'bot',
                ], (v) => setState(() => _scope = v)),
                _input(
                  'variable',
                  context.strings.variableName,
                  required: true,
                  help: context.strings.createTheVariableInThisBot,
                ),
                _input(
                  'text',
                  kind == 'incrementVariable'
                      ? context.strings.amountToAdd
                      : context.strings.newValue,
                  required: true,
                  help: context.strings.aLiteralValueOrReferenceSuch,
                ),
              ] else if (kind == 'condition')
                ..._conditionFields()
              else if (kind == 'wait')
                _input('text', context.strings.seconds060, required: true)
              else ...[
                if (BuilderCatalog.media.contains(kind))
                  _input(
                    'media',
                    context.strings.mediaHTTPSURLOrTelegram,
                    required: true,
                  ),
                if (kind == 'inlineAnswer')
                  _input(
                    'title',
                    context.strings.resultTitle,
                    required: true,
                    fallback: 'Result',
                  ),
                if (BuilderCatalog.messages.contains(kind)) ...[
                  _select(context.strings.textFormat, _format, const [
                    'plain',
                    'MarkdownV2',
                  ], (v) => setState(() => _format = v)),
                  TelegramTextEditor(
                    controller: field('text'),
                    references: widget.references,
                    markdown: _format == 'MarkdownV2',
                    label: BuilderCatalog.media.contains(kind)
                        ? context.strings.caption
                        : context.strings.message,
                  ),
                ],
                if (kind == 'reply')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.strings.sendToAllAdmins),
                    subtitle: Text(context.strings.useTheAdminListInBot),
                    value: _sendToAdmins,
                    onChanged: (value) => setState(() => _sendToAdmins = value),
                  ),
                if (kind == 'reply' || kind == 'editText')
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(context.strings.richMessage),
                    initiallyExpanded: value('richBlocks').isNotEmpty,
                    children: [
                      _input(
                        'richBlocks',
                        context.strings.richBlocksJSON,
                        lines: 5,
                        help: context.strings.useABlockArrayOrA,
                      ),
                      if (kind == 'reply')
                        _input(
                          'draftId',
                          context.strings.draftID,
                          help: context
                              .strings
                              .privateChatPreviewUseEventUpdateId,
                        ),
                    ],
                  ),
                if (kind == 'reply' || kind == 'editText')
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(context.strings.telegramWidget),
                    initiallyExpanded:
                        value('widgetHtml').isNotEmpty ||
                        value('widgetChatData').isNotEmpty,
                    children: [
                      if (kind == 'reply') ...[
                        _input(
                          'widgetHtml',
                          context.strings.widgetHTML,
                          lines: 6,
                          help: context.strings.selfContainedHTMLForAPrivate,
                        ),
                        _input(
                          'widgetCaption',
                          context.strings.widgetCaption,
                          help: context.strings.shownBelowTheWidgetIncludingIn,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(context.strings.allowWidgetRequests),
                          value: _widgetQueries,
                          onChanged: (value) =>
                              setState(() => _widgetQueries = value),
                        ),
                      ],
                      _input(
                        'widgetChatData',
                        context.strings.widgetChatDataJSON,
                        lines: 3,
                        help: context.strings.upTo1024UTF8Bytes,
                      ),
                    ],
                  ),
                if (kind == 'callbackAnswer') ...[
                  _input(
                    'text',
                    context.strings.notificationText,
                    help: context.strings.upTo200CharactersLeaveBlank,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.strings.showAsAlert),
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
                    context.strings.keyboardOutputReference,
                    help: context.strings.exampleStepsListKeyboardWhenSet,
                  ),
                if (BuilderCatalog.hasChat(kind))
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(context.strings.target),
                    subtitle: Text(
                      context.strings.defaultsToTheConversationAndTriggering,
                    ),
                    initiallyExpanded: BuilderCatalog.targets.contains(kind),
                    children: [
                      _input(
                        'chatId',
                        context.strings.chatIDOrChannelUsername,
                        help: context.strings.blankUsesTheCurrentChatA,
                      ),
                      if (BuilderCatalog.targets.contains(kind))
                        _input(
                          'messageId',
                          context.strings.messageID,
                          help: context
                              .strings
                              .blankUsesTheTriggeringMessageExample,
                        ),
                    ],
                  ),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(context.strings.execution),
                children: [
                  _select(context.strings.onFailure, _onError, const [
                    'stop',
                    'continue',
                  ], (v) => setState(() => _onError = v)),
                  Text(context.strings.continueExposesStepsNameOkFalse),
                  if (kind != 'condition') ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.strings.runOnlyWhenAConditionMatches),
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
                label: Text(
                  _saving ? context.strings.saving : context.strings.saveAction,
                ),
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
      context.strings.leftValue,
      help: context.strings.literalTextOrAReferenceSuch,
    ),
    _select(context.strings.comparison, _operator, const [
      'equals',
      'notEquals',
      'contains',
      'greater',
      'less',
    ], (v) => setState(() => _operator = v)),
    _input('right', context.strings.rightValue),
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
        for (final v in options)
          DropdownMenuItem(
            value: v,
            child: Text(switch (v) {
              'user' => context.strings.perUser,
              'bot' => context.strings.wholeBot,
              'plain' => context.strings.plainTextFormat,
              'stop' => context.strings.stopOnFailure,
              'continue' => context.strings.continueOnFailure,
              'equals' => context.strings.equals,
              'notEquals' => context.strings.notEqualsOperator,
              'contains' => context.strings.contains,
              'greater' => context.strings.greaterThanOperator,
              'less' => context.strings.lessThanOperator,
              _ => v,
            }),
          ),
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
      textDirection: switch (key) {
        'text' when widget.initial.kind == 'sql' => TextDirection.ltr,
        'output' ||
        'items' ||
        'buttons' ||
        'footerButtons' ||
        'itemData' ||
        'parameters' ||
        'url' ||
        'credential' ||
        'headers' ||
        'body' ||
        'variable' ||
        'media' ||
        'richBlocks' ||
        'draftId' ||
        'widgetHtml' ||
        'widgetChatData' ||
        'keyboardOutput' ||
        'chatId' ||
        'messageId' => TextDirection.ltr,
        _ => null,
      },
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
        if (required && text.trim().isEmpty) {
          return context.strings.thisFieldIsRequired;
        }
        if (text.length > 65536) return context.strings.thisFieldExceeds64KiB;
        return validate?.call(text);
      },
    ),
  );
}
