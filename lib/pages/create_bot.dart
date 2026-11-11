import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/plugins_page.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/setup_fields.dart';
import 'package:bottogram/store/bots.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';

class CreateBotPage extends StatefulWidget {
  const CreateBotPage({super.key, required this.bots, required this.plugins});
  final BotsCubit bots;
  final PluginRepository plugins;
  @override
  State<CreateBotPage> createState() => _CreateBotPageState();
}

class _CreateBotPageState extends State<CreateBotPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _token = TextEditingController();
  final _admin = TextEditingController();
  final _parameters = <String, TextEditingController>{};
  PluginManifest? _plugin;
  bool _saving = false;
  String? _error;
  late final Future<void> _ready = widget.plugins.ready;

  @override
  void initState() {
    super.initState();
    widget.plugins.addListener(_catalogChanged);
  }

  void _catalogChanged() {
    if (_plugin != null &&
        !widget.plugins.installed.any(
          (p) => p.storageKey == _plugin!.storageKey,
        )) {
      _select(null);
    }
  }

  @override
  void dispose() {
    widget.plugins.removeListener(_catalogChanged);
    for (final ctrl in [_name, _token, _admin, ..._parameters.values]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _select(String? key) {
    for (final ctrl in _parameters.values) {
      ctrl.dispose();
    }
    _parameters.clear();
    _plugin = key == null
        ? null
        : widget.plugins.installed.firstWhere((p) => p.storageKey == key);
    for (final field in _plugin?.fields ?? <PluginField>[]) {
      _parameters[field.key] = TextEditingController(
        text: field.defaultValue ?? '',
      );
    }
    setState(() => _error = null);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.bots.create(
        name: _name.text.trim(),
        token: _token.text.trim(),
        adminIds: _admin.text.trim(),
        plugin: _plugin,
        parameters: _parameters.map((key, ctrl) => MapEntry(key, ctrl.text)),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PluginException
              ? error.message
              : 'The bot could not be saved. Your draft is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create bot')),
    body: FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const BEmptyState(
            icon: Icons.folder_off_outlined,
            title: 'Settings unavailable',
            message:
                'Bot settings storage could not be opened. Reopen Bottogram to try again.',
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
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
                    const BHeading(
                      title: 'Bot setup',
                      subtitle:
                          'Connect your Telegram bot, then choose how to configure it.',
                    ),
                    const SizedBox(height: 32),
                    BPanel(
                      child: BSection(
                        title: 'Telegram details',
                        description:
                            'These details belong to every bot, with or without a plugin.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _name,
                              maxLength: 100,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Bot name',
                                hintText: 'A name you will recognize',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Enter a bot name.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            SecretFormField(
                              controller: _token,
                              label: 'Telegram bot token',
                              secret: true,
                              helpText:
                                  'Create a bot with BotFather in Telegram to get its token.',
                              validator: (value) =>
                                  RegExp(
                                    r'^[0-9]+:[A-Za-z0-9_-]+$',
                                  ).hasMatch(value?.trim() ?? '')
                                  ? null
                                  : 'Enter the Telegram bot token from BotFather.',
                            ),
                            const SizedBox(height: 24),
                            AdminIdsField(controller: _admin),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    BPanel(
                      child: BSection(
                        title: 'Setup method',
                        description:
                            'Build your own actions or use an installed plugin.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListenableBuilder(
                              listenable: widget.plugins,
                              builder: (context, _) =>
                                  DropdownButtonFormField<String>(
                                    key: ValueKey(
                                      _plugin?.storageKey ?? 'manual',
                                    ),
                                    initialValue:
                                        _plugin?.storageKey ?? 'manual',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Setup method',
                                      prefixIcon: Icon(Icons.tune_rounded),
                                    ),
                                    items: [
                                      const DropdownMenuItem(
                                        value: 'manual',
                                        child: Text('Manual'),
                                      ),
                                      for (final plugin
                                          in widget.plugins.installed)
                                        DropdownMenuItem(
                                          value: plugin.storageKey,
                                          child: Text(
                                            '${plugin.name} · ${plugin.version}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (key) =>
                                        _select(key == 'manual' ? null : key),
                                  ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(
                                  Icons.extension_outlined,
                                  size: 18,
                                ),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => PluginsPage(
                                        repository: widget.plugins,
                                      ),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                                label: const Text('Manage plugins'),
                              ),
                            ),
                            if (_plugin != null) ...[
                              const Divider(),
                              const SizedBox(height: 24),
                              PluginSetupFields(
                                plugin: _plugin!,
                                controllers: _parameters,
                              ),
                              BNotice(
                                icon: Icons.lock_outline_rounded,
                                message: _plugin!.executable
                                    ? 'Credentials are saved securely. Start the bot after creating it to run its automations.'
                                    : 'Settings will be saved securely. This plugin version is setup-only.',
                              ),
                            ] else
                              const Text(
                                'Add events, replies, and keyboards after creating this bot.',
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      BNotice(message: _error!, error: true),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text(_saving ? 'Saving…' : 'Create bot'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
