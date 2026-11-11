import 'package:flutter/material.dart';

import 'manifest.dart';
import 'admin_ids.dart';

class PluginSetupFields extends StatelessWidget {
  const PluginSetupFields({
    super.key,
    required this.plugin,
    required this.controllers,
  });
  final PluginManifest plugin;
  final Map<String, TextEditingController> controllers;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final field in plugin.fields)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: SecretFormField(
            key: ValueKey('${plugin.storageKey}:${field.key}'),
            controller: controllers[field.key]!,
            label: field.label,
            helpText: field.helpText,
            secret: field.type == PluginFieldType.secret,
            numeric: field.type == PluginFieldType.integer,
            multiline: field.type == PluginFieldType.telegramChats,
            validator: (v) => field.validate(v ?? ''),
          ),
        ),
    ],
  );
}

class SecretFormField extends StatefulWidget {
  const SecretFormField({
    super.key,
    required this.controller,
    required this.label,
    this.helpText,
    this.secret = false,
    this.numeric = false,
    this.multiline = false,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String? helpText;
  final bool secret;
  final bool numeric;
  final bool multiline;
  final String? Function(String?)? validator;
  @override
  State<SecretFormField> createState() => _SecretFormFieldState();
}

class _SecretFormFieldState extends State<SecretFormField> {
  bool _visible = false;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    validator: widget.validator,
    obscureText: widget.secret && !_visible,
    enableSuggestions: !widget.secret,
    autocorrect: !widget.secret,
    minLines: widget.multiline ? 2 : 1,
    maxLines: widget.multiline ? 4 : 1,
    keyboardType: widget.numeric
        ? const TextInputType.numberWithOptions(signed: true)
        : widget.multiline
        ? TextInputType.multiline
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helpText,
      helperMaxLines: 3,
      suffixIcon: widget.secret
          ? IconButton(
              tooltip: _visible
                  ? 'Hide ${widget.label}'
                  : 'Show ${widget.label}',
              onPressed: () => setState(() => _visible = !_visible),
              icon: Icon(
                _visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            )
          : null,
    ),
  );
}

class AdminIdsField extends StatelessWidget {
  const AdminIdsField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => SecretFormField(
    controller: controller,
    label: 'Admins',
    multiline: true,
    helpText: 'Enter Telegram user IDs separated by commas or line breaks.',
    validator: validateAdminIds,
  );
}

class EditAdminsDialog extends StatefulWidget {
  const EditAdminsDialog({super.key, required this.ids, required this.onSave});
  final List<String> ids;
  final Future<void> Function(String ids) onSave;

  @override
  State<EditAdminsDialog> createState() => _EditAdminsDialogState();
}

class _EditAdminsDialogState extends State<EditAdminsDialog> {
  final _form = GlobalKey<FormState>();
  late final _ids = TextEditingController(text: widget.ids.join('\n'));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ids.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_ids.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is PluginException
              ? error.message
              : 'Could not save the admins. Check the bot settings and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit admins'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AbsorbPointer(
                absorbing: _saving,
                child: AdminIdsField(controller: _ids),
              ),
              if (_error != null) Text(_error!),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save admins'),
      ),
    ],
  );
}
