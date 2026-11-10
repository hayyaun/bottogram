import 'package:flutter/material.dart';

class BEntry<T> {
  const BEntry(this.text, this.type);
  final String text;
  final T type;
}

Future<BEntry<T>?> showBEntryDialog<T>(
  BuildContext context, {
  required String title,
  required String fieldLabel,
  required T initialType,
  Map<T, String> types = const {},
  String initialText = '',
  String action = 'Add',
  String? Function(String)? validate,
}) => showDialog<BEntry<T>>(
  context: context,
  builder: (_) => _EntryDialog<T>(
    title: title,
    fieldLabel: fieldLabel,
    initialType: initialType,
    types: types,
    initialText: initialText,
    action: action,
    validate: validate,
  ),
);

class _EntryDialog<T> extends StatefulWidget {
  const _EntryDialog({
    required this.title,
    required this.fieldLabel,
    required this.initialType,
    required this.types,
    required this.initialText,
    required this.action,
    this.validate,
  });
  final String title, fieldLabel, initialText, action;
  final T initialType;
  final Map<T, String> types;
  final String? Function(String)? validate;
  @override
  State<_EntryDialog<T>> createState() => _EntryDialogState<T>();
}

class _EntryDialogState<T> extends State<_EntryDialog<T>> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialText);
  late T _type = widget.initialType;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, BEntry(_controller.text, _type));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.types.isNotEmpty) ...[
                DropdownButtonFormField<T>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final entry in widget.types.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 24),
              ],
              TextFormField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: InputDecoration(labelText: widget.fieldLabel),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a value.'
                    : widget.validate?.call(value),
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
      FilledButton(onPressed: _save, child: Text(widget.action)),
    ],
  );
}

Future<bool> confirmRemoval(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
