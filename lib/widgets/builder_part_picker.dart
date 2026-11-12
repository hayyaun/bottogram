import 'dart:convert';

import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../builder/parts.dart';
import '../builder/store.dart';
import '../builder/values.dart';
import '../ui/dialogs.dart';

Future<String?> pickBuilderPart(
  BuildContext context,
  String title,
  Map<String, Map<String, dynamic>> entries,
) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        ListTile(title: Text(title)),
        if (entries.isEmpty)
          ListTile(title: Text(context.strings.nothingSavedYet)),
        for (final entry in entries.entries)
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(entry.value['label'] as String),
            onTap: () => Navigator.pop(context, entry.key),
          ),
      ],
    ),
  ),
);

Future<String?> nameBuilderPart(
  BuildContext context,
  String title, {
  String? initial,
}) async {
  final result = await showBEntryDialog<bool>(
    context,
    title: title,
    fieldLabel: context.strings.libraryName,
    initialType: true,
    initialText: initial ?? '',
    action: context.strings.save,
    validate: (value) =>
        value.trim().length > 80 ? context.strings.useUpTo80Characters : null,
  );
  return result?.text.trim();
}

class BuilderRowLibrary extends StatefulWidget {
  const BuilderRowLibrary({
    super.key,
    required this.kind,
    required this.localRows,
    required this.links,
    required this.onSaveAndLink,
    required this.onLink,
    required this.onUnlink,
    this.onEditLocal,
    this.firstEditableRow = 0,
    this.allowConditions = false,
    this.allowItemBindings = false,
  });

  final String kind;
  final List<List> localRows;
  final List<String> links;
  final void Function(int index, String id) onSaveAndLink;
  final ValueChanged<String> onLink;
  final ValueChanged<String> onUnlink;
  final void Function(int index, List<Map> buttons)? onEditLocal;
  final int firstEditableRow;
  final bool allowConditions, allowItemBindings;

  @override
  State<BuilderRowLibrary> createState() => _BuilderRowLibraryState();
}

class _BuilderRowLibraryState extends State<BuilderRowLibrary> {
  String get kind => widget.kind;
  List<List> get localRows => widget.localRows;

  Future<void> _save(BuildContext context, int index) async {
    final label = await nameBuilderPart(context, context.strings.saveButtonRow);
    if (label == null || !context.mounted) return;
    try {
      final id = BuilderParts.newId();
      await BuilderStore.shared.savePart(
        id,
        BuilderParts.row(label, kind, localRows[index]),
        isList: false,
      );
      if (context.mounted) widget.onSaveAndLink(index, id);
    } catch (error) {
      if (context.mounted) _report(context, error);
    }
  }

  Future<void> _newRow(BuildContext context) async {
    final buttons = await _editButtons(context, [
      {'text': '', if (kind == BuilderParts.inline) 'callback_data': ''},
    ], title: context.strings.createButtonRow);
    if (buttons == null || !context.mounted) return;
    final label = await nameBuilderPart(context, context.strings.saveButtonRow);
    if (label == null || !context.mounted) return;
    try {
      final id = BuilderParts.newId();
      await BuilderStore.shared.savePart(
        id,
        BuilderParts.row(label, kind, buttons),
        isList: false,
      );
      if (context.mounted) widget.onLink(id);
    } catch (error) {
      if (context.mounted) _report(context, error);
    }
  }

  Future<List<Map>?> _editButtons(
    BuildContext context,
    List<Map> buttons, {
    required String title,
    bool shared = false,
  }) => showDialog<List<Map>>(
    context: context,
    builder: (_) =>
        _EditRow(row: buttons, kind: kind, title: title, shared: shared),
  );

  void _report(BuildContext context, Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BuilderFailure
                ? error.message
                : context.strings.theButtonRowCouldNotBe,
          ),
        ),
      );

  Future<void> _edit(BuildContext context, String id, Map definition) async {
    final row = (definition['buttons'] as List).cast<Map>();
    final edited = await _editButtons(
      context,
      row,
      title: context.strings.editSharedRow,
      shared: true,
    );
    if (edited == null || !context.mounted) return;
    try {
      await BuilderStore.shared.savePart(
        id,
        BuilderParts.row(definition['label'] as String, kind, edited),
        isList: false,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (context.mounted) _report(context, error);
    }
  }

  bool _canLink(Map<String, dynamic> entry) {
    if (entry['kind'] != kind) return false;
    final buttons = entry['buttons'] as List;
    if (!widget.allowConditions &&
        buttons.any((button) => button['when'] != null)) {
      return false;
    }
    return widget.allowItemBindings ||
        !RegExp(
          r'\{\{\s*(?:item(?:\.|\s*\}\})|index\s*\}\})',
        ).hasMatch(jsonEncode(buttons));
  }

  @override
  Widget build(BuildContext context) {
    final rows = BuilderStore.shared.parts.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final (index, row) in localRows.indexed)
              if (row.isNotEmpty)
                TextButton(
                  onPressed: () => _save(context, index),
                  child: Text(
                    localRows.length == 1
                        ? context.strings.saveRowToLibrary
                        : context.strings.saveNumberedRow('${index + 1}'),
                  ),
                ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(context.strings.newSharedRow),
              onPressed: () => _newRow(context),
            ),
            TextButton.icon(
              icon: const Icon(Icons.link),
              label: Text(context.strings.chooseSavedRow),
              onPressed: () async {
                final id = await pickBuilderPart(
                  context,
                  context.strings.buttonRowLibrary,
                  {
                    for (final entry in rows.entries)
                      if (_canLink(entry.value)) entry.key: entry.value,
                  },
                );
                if (id != null && context.mounted) widget.onLink(id);
              },
            ),
          ],
        ),
        if (widget.onEditLocal case final edit?)
          for (
            var index = widget.firstEditableRow;
            index < localRows.length;
            index++
          )
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                localRows[index].map((button) => button['text']).join(' · '),
              ),
              trailing: IconButton(
                tooltip: context.strings.editLocalRow,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final edited = await _editButtons(
                    context,
                    localRows[index].cast<Map>(),
                    title: context.strings.editLocalRow,
                  );
                  if (edited != null && context.mounted) edit(index, edited);
                },
              ),
            ),
        for (final id in widget.links)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: Text(
              rows[id]?['label'] as String? ?? context.strings.unavailableRow,
            ),
            subtitle: Text(
              (rows[id]?['buttons'] as List? ?? [])
                  .map((b) => b['text'])
                  .join(' · '),
            ),
            trailing: Wrap(
              children: [
                if (rows[id] case final row?)
                  IconButton(
                    tooltip: context.strings.editSharedRow,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, id, row),
                  ),
                IconButton(
                  tooltip: context.strings.removeRowLink,
                  icon: const Icon(Icons.link_off),
                  onPressed: () => widget.onUnlink(id),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EditRow extends StatefulWidget {
  const _EditRow({
    required this.row,
    required this.kind,
    required this.title,
    this.shared = false,
  });
  final List<Map> row;
  final String kind, title;
  final bool shared;
  @override
  State<_EditRow> createState() => _EditRowState();
}

class _EditRowState extends State<_EditRow> {
  late final _buttons = [for (final button in widget.row) Map.of(button)];
  final _form = GlobalKey<FormState>();
  int _next = 0;
  late final _keys = [for (final _ in _buttons) _next++];
  bool get inline => widget.kind == BuilderParts.inline;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.shared)
                Text(context.strings.savingUpdatesEveryActionLinkedTo),
              for (final (index, button) in _buttons.indexed)
                Column(
                  key: ValueKey(_keys[index]),
                  children: [
                    TextFormField(
                      initialValue: button['text'] as String?,
                      decoration: InputDecoration(
                        labelText: context.strings.buttonText,
                      ),
                      onChanged: (value) => button['text'] = value,
                      validator: _required,
                    ),
                    if (inline)
                      TextFormField(
                        initialValue:
                            (button['url'] ?? button['callback_data'])
                                as String?,
                        decoration: InputDecoration(
                          labelText: context.strings.callbackOrURL,
                        ),
                        onChanged: (value) {
                          final previousUrl = button.remove('url');
                          button.remove('callback_data');
                          final uri = Uri.tryParse(value);
                          button[{'http', 'https'}.contains(uri?.scheme) ||
                                      previousUrl != null &&
                                          value.startsWith('{{')
                                  ? 'url'
                                  : 'callback_data'] =
                              value;
                        },
                        validator: _required,
                      ),
                    if (_buttons.length > 1)
                      TextButton(
                        onPressed: () => setState(() {
                          _buttons.removeAt(index);
                          _keys.removeAt(index);
                        }),
                        child: Text(context.strings.removeButton),
                      ),
                  ],
                ),
              if (_buttons.length < 8)
                TextButton(
                  onPressed: () => setState(() {
                    _buttons.add({'text': '', if (inline) 'callback_data': ''});
                    _keys.add(_next++);
                  }),
                  child: Text(context.strings.addButton),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.strings.cancel),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) Navigator.pop(context, _buttons);
        },
        child: Text(context.strings.saveChanges),
      ),
    ],
  );

  String? _required(String? text) =>
      text?.trim().isNotEmpty == true ? null : context.strings.enterAValue;
}
