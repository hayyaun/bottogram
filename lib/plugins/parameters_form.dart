import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';
import 'bot_setup.dart';
import 'manifest.dart';
import 'setup_fields.dart';

class PluginParametersForm extends StatefulWidget {
  const PluginParametersForm({
    super.key,
    required this.plugin,
    required this.setup,
    required this.onSave,
  });
  final PluginManifest plugin;
  final BotSetup setup;
  final Future<void> Function(String adminIds, Map<String, String> values)
  onSave;
  @override
  State<PluginParametersForm> createState() => _PluginParametersFormState();
}

class _PluginParametersFormState extends State<PluginParametersForm> {
  final _form = GlobalKey<FormState>();
  late final _admin = TextEditingController(
    text: widget.setup.adminIds.join('\n'),
  );
  late final _fields = {
    for (final field in widget.plugin.fields)
      field.key: TextEditingController(
        text: widget.setup.values[field.key] ?? '',
      ),
  };
  bool _busy = false;
  String? _error;
  bool _saved = false;

  @override
  void dispose() {
    _admin.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      await widget.onSave(_admin.text.trim(), {
        for (final entry in _fields.entries) entry.key: entry.value.text,
      });
      if (!mounted) return;
      for (final field in widget.plugin.fields) {
        if (field.type == PluginFieldType.secret) _fields[field.key]!.clear();
      }
      setState(() => _saved = true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PluginException
              ? error.message
              : context.strings.parametersCouldNotBeSavedCheck,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        AbsorbPointer(
          absorbing: _busy,
          child: Column(
            children: [
              AdminIdsField(controller: _admin),
              const SizedBox(height: 20),
              for (final field in widget.plugin.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (field.type == PluginFieldType.secret &&
                          widget.setup.secretFields.contains(field.key)) ...[
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: BStatus(
                            label: context.strings.savedSecurely,
                            color: BColors.of(context).success,
                            background: BColors.of(context).successWash,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SecretFormField(
                        controller: _fields[field.key]!,
                        label: field.label,
                        secret: field.type == PluginFieldType.secret,
                        numeric: field.type == PluginFieldType.integer,
                        multiline: field.type == PluginFieldType.telegramChats,
                        helpText:
                            field.type == PluginFieldType.secret &&
                                widget.setup.secretFields.contains(field.key)
                            ? context.strings.leaveBlankToKeepTheSaved
                            : field.helpText,
                        validator: (value) =>
                            field.type == PluginFieldType.secret &&
                                (value ?? '').isEmpty &&
                                widget.setup.secretFields.contains(field.key)
                            ? null
                            : field.validate(value ?? ''),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Text(
          widget.plugin.destinationFields.isEmpty
              ? context.strings.savingChangesRestartsARunningBot
              : context.strings.savingChangesRestartsARunningBot2,
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          BNotice(message: _error!, error: true),
          const SizedBox(height: 16),
        ],
        if (_saved) ...[
          Text(context.strings.parametersSaved),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            _busy ? context.strings.saving : context.strings.saveParameters,
          ),
        ),
      ],
    ),
  );
}
