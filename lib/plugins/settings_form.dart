import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';

import 'manifest.dart';
import 'setting.dart';

class PluginSettingsForm extends StatefulWidget {
  const PluginSettingsForm({
    super.key,
    required this.definitions,
    required this.values,
    required this.onSave,
  });
  final List<PluginSetting> definitions;
  final Map<String, Object> values;
  final Future<void> Function(Map<String, Object?>) onSave;

  @override
  State<PluginSettingsForm> createState() => _PluginSettingsFormState();
}

class _PluginSettingsFormState extends State<PluginSettingsForm> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  late final Map<String, Object> _values = Map.of(widget.values);
  bool _saving = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    for (final setting in widget.definitions) {
      if (setting.type != PluginSettingType.boolean &&
          setting.type != PluginSettingType.choice) {
        _controllers[setting.key] = TextEditingController(
          text: _values[setting.key].toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _saved = false;
    });
    try {
      final values = <String, Object?>{};
      for (final setting in widget.definitions) {
        final controller = _controllers[setting.key];
        values[setting.key] = controller == null
            ? _values[setting.key]
            : setting.parseInput(controller.text);
      }
      await widget.onSave(values);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PluginException
              ? error.message
              : context.strings.settingsCouldNotBeSavedYour,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    onChanged: () {
      if (_saved) setState(() => _saved = false);
    },
    child: AbsorbPointer(
      absorbing: _saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.strings.pluginSettings,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final setting in widget.definitions) ...[
            if (setting.type == PluginSettingType.boolean)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(setting.label),
                subtitle: setting.helpText == null
                    ? null
                    : Text(setting.helpText!),
                value: _values[setting.key] as bool,
                onChanged: (value) => setState(() {
                  _values[setting.key] = value;
                  _saved = false;
                }),
              )
            else if (setting.type == PluginSettingType.choice)
              DropdownButtonFormField<String>(
                initialValue: _values[setting.key] as String,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: setting.label,
                  helperText: setting.helpText,
                ),
                items: [
                  for (final option in setting.choices)
                    DropdownMenuItem(
                      value: option.value,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _values[setting.key] = value!;
                  _saved = false;
                }),
                validator: setting.validate,
              )
            else
              TextFormField(
                controller: _controllers[setting.key],
                keyboardType: setting.type == PluginSettingType.string
                    ? TextInputType.text
                    : const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                decoration: InputDecoration(
                  labelText: setting.label,
                  helperText: setting.helpText,
                  helperMaxLines: 4,
                  errorMaxLines: 3,
                ),
                validator: (text) =>
                    setting.validate(setting.parseInput(text ?? '')),
              ),
            const SizedBox(height: 16),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: BNotice(message: _error!, error: true),
            ),
          if (_saved)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: BNotice(
                message: context.strings.settingsSaved,
                icon: Icons.check_circle_outline,
              ),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? context.strings.saving : context.strings.saveSettings,
            ),
          ),
        ],
      ),
    ),
  );
}
