import 'package:flutter/material.dart';

import 'manifest.dart';

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
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String? helpText;
  final bool secret;
  final bool numeric;
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
    keyboardType:
        widget.numeric
            ? const TextInputType.numberWithOptions(signed: true)
            : TextInputType.text,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helpText,
      helperMaxLines: 3,
      suffixIcon:
          widget.secret
              ? IconButton(
                tooltip:
                    _visible ? 'Hide ${widget.label}' : 'Show ${widget.label}',
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
