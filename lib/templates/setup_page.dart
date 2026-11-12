import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../builder/values.dart';
import '../plugins/setup_fields.dart';
import '../plugins/manifest.dart';
import '../store/bots.dart';
import '../ui/design.dart';
import 'catalog.dart';
import 'model.dart';

class TemplateSetupPage extends StatefulWidget {
  const TemplateSetupPage({super.key, required this.template, this.onCreate});
  final BotTemplate template;
  final Future<void> Function(
    String name,
    String token,
    String adminIds,
    BotTemplateDraft draft,
  )?
  onCreate;
  @override
  State<TemplateSetupPage> createState() => _TemplateSetupPageState();
}

class _TemplateSetupPageState extends State<TemplateSetupPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.template.name);
  final _token = TextEditingController(), _admin = TextEditingController();
  late final _settings = {
    for (final f in widget.template.fields)
      f.key: TextEditingController(text: f.initial),
  };
  late final _rows = widget.template.sampleRows();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _token, _admin, ..._settings.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _editRow([int? index]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TemplateRowDialog(
        dataset: widget.template.dataset!,
        initial: index == null ? null : _rows[index],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          _rows.add(result);
        } else {
          _rows[index] = result;
        }
      });
    }
  }

  Future<void> _create() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = BotTemplates.create(
        widget.template,
        {for (final e in _settings.entries) e.key: e.value.text.trim()},
        _rows,
        _admin.text.trim(),
      );
      if (widget.onCreate != null) {
        await widget.onCreate!(
          _name.text.trim(),
          _token.text.trim(),
          _admin.text.trim(),
          draft,
        );
      } else {
        await context.read<BotsCubit>().create(
          name: _name.text.trim(),
          token: _token.text.trim(),
          adminIds: _admin.text.trim(),
          template: draft,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is BuilderFailure
              ? error.message
              : error is PluginException
              ? error.message
              : context.strings.theBotCouldNotBeCreated,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.template.name)),
    body: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: BContent(
        maxWidth: 760,
        child: Form(
          key: _form,
          child: AbsorbPointer(
            absorbing: _saving,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BHeading(
                  title: widget.template.name,
                  subtitle: widget.template.summary,
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(context.strings.howItWorks),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(widget.template.description),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                BNotice(message: context.strings.createsANewBotWithEditable),
                const SizedBox(height: 20),
                BPanel(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _name,
                        maxLength: 100,
                        decoration: InputDecoration(
                          labelText: context.strings.botName,
                        ),
                        validator: (v) => (v?.trim().isEmpty ?? true)
                            ? context.strings.enterABotName
                            : null,
                      ),
                      const SizedBox(height: 16),
                      SecretFormField(
                        controller: _token,
                        label: context.strings.telegramBotToken,
                        secret: true,
                        helpText: context.strings.getTheTokenFromBotFatherA,
                        validator: (v) =>
                            RegExp(
                              r'^[0-9]+:[A-Za-z0-9_-]+$',
                            ).hasMatch(v?.trim() ?? '')
                            ? null
                            : context.strings.enterAValidTelegramBotToken,
                      ),
                      const SizedBox(height: 16),
                      AdminIdsField(controller: _admin),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                BPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.strings.templateSettings,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      for (final f in widget.template.fields)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextFormField(
                            controller: _settings[f.key],
                            decoration: InputDecoration(labelText: f.label),
                            keyboardType: f.number
                                ? TextInputType.number
                                : TextInputType.text,
                            maxLength: 500,
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? context.strings.completeThisField
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.template.dataset != null) ...[
                  const SizedBox(height: 24),
                  BSection(
                    title: widget.template.dataset!.label,
                    description: context.strings.editTheSamplesOrAddYour,
                    trailing: TextButton.icon(
                      onPressed: _rows.length >= 20 ? null : () => _editRow(),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(context.strings.add),
                    ),
                    child: Column(
                      children: [
                        for (final (i, row) in _rows.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: BPanel(
                              padding: EdgeInsets.zero,
                              child: ListTile(
                                title: Text(
                                  (row['question'] ??
                                          row['title'] ??
                                          row['prompt'] ??
                                          'Item')
                                      .toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  (row['topic'] ??
                                          row['category'] ??
                                          row['kind'] ??
                                          context.strings.sampleCapacity(
                                            '${row['capacity']}',
                                          ))
                                      .toString(),
                                ),
                                onTap: () => _editRow(i),
                                trailing: IconButton(
                                  tooltip: context.strings.removeSample,
                                  onPressed: () =>
                                      setState(() => _rows.removeAt(i)),
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: BNotice(message: _error!, error: true),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _create,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(
                    _saving
                        ? context.strings.creating
                        : context.strings.createBotFromTemplate,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TemplateRowDialog extends StatefulWidget {
  const _TemplateRowDialog({required this.dataset, this.initial});
  final TemplateDataset dataset;
  final Map<String, dynamic>? initial;
  @override
  State<_TemplateRowDialog> createState() => _TemplateRowDialogState();
}

class _TemplateRowDialogState extends State<_TemplateRowDialog> {
  final _form = GlobalKey<FormState>();
  late final _controllers = {
    for (final key in widget.dataset.columns.keys)
      key: TextEditingController(text: widget.initial?[key]?.toString() ?? ''),
  };
  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null
          ? context.strings.addSampleContent
          : context.strings.editSampleContent,
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in widget.dataset.columns.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _controllers[entry.key],
                    decoration: InputDecoration(labelText: entry.value),
                    minLines:
                        {
                          'question',
                          'description',
                          'details',
                          'prompt',
                          'explanation',
                        }.contains(entry.key)
                        ? 2
                        : 1,
                    maxLines: 4,
                    keyboardType: entry.key == 'capacity'
                        ? TextInputType.number
                        : TextInputType.multiline,
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? context.strings.completeThisField
                        : null,
                  ),
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
          if (_form.currentState!.validate()) {
            Navigator.pop(context, {
              for (final e in _controllers.entries) e.key: e.value.text.trim(),
            });
          }
        },
        child: Text(context.strings.save),
      ),
    ],
  );
}
