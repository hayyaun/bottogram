import 'dart:convert';

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
        if (entries.isEmpty) const ListTile(title: Text('Nothing saved yet.')),
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
    fieldLabel: 'Library name',
    initialType: true,
    initialText: initial ?? '',
    action: 'Save',
    validate: (value) =>
        value.trim().length > 80 ? 'Use up to 80 characters.' : null,
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
    final label = await nameBuilderPart(context, 'Save button row');
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
    ], title: 'Create button row');
    if (buttons == null || !context.mounted) return;
    final label = await nameBuilderPart(context, 'Save button row');
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
                : 'The button row could not be saved.',
          ),
        ),
      );

  Future<void> _edit(BuildContext context, String id, Map definition) async {
    final row = (definition['buttons'] as List).cast<Map>();
    final edited = await _editButtons(
      context,
      row,
      title: 'Edit shared row',
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
                        ? 'Save row to library'
                        : 'Save row ${index + 1} to library',
                  ),
                ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('New shared row'),
              onPressed: () => _newRow(context),
            ),
            TextButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Choose saved row'),
              onPressed: () async {
                final id =
                    await pickBuilderPart(context, 'Button row library', {
                      for (final entry in rows.entries)
                        if (_canLink(entry.value)) entry.key: entry.value,
                    });
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
                tooltip: 'Edit local row',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final edited = await _editButtons(
                    context,
                    localRows[index].cast<Map>(),
                    title: 'Edit local row',
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
            title: Text(rows[id]?['label'] as String? ?? 'Unavailable row'),
            subtitle: Text(
              (rows[id]?['buttons'] as List? ?? [])
                  .map((b) => b['text'])
                  .join(' · '),
            ),
            trailing: Wrap(
              children: [
                if (rows[id] case final row?)
                  IconButton(
                    tooltip: 'Edit shared row',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, id, row),
                  ),
                IconButton(
                  tooltip: 'Remove row link',
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
                const Text('Saving updates every action linked to this row.'),
              for (final (index, button) in _buttons.indexed)
                Column(
                  key: ValueKey(_keys[index]),
                  children: [
                    TextFormField(
                      initialValue: button['text'] as String?,
                      decoration: const InputDecoration(
                        labelText: 'Button text',
                      ),
                      onChanged: (value) => button['text'] = value,
                      validator: _required,
                    ),
                    if (inline)
                      TextFormField(
                        initialValue:
                            (button['url'] ?? button['callback_data'])
                                as String?,
                        decoration: const InputDecoration(
                          labelText: 'Callback or URL',
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
                        child: const Text('Remove button'),
                      ),
                  ],
                ),
              if (_buttons.length < 8)
                TextButton(
                  onPressed: () => setState(() {
                    _buttons.add({'text': '', if (inline) 'callback_data': ''});
                    _keys.add(_next++);
                  }),
                  child: const Text('Add button'),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) Navigator.pop(context, _buttons);
        },
        child: const Text('Save changes'),
      ),
    ],
  );

  String? _required(String? text) =>
      text?.trim().isNotEmpty == true ? null : 'Enter a value.';
}
