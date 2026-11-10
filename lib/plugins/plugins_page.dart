import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';

import 'manifest.dart';
import 'repository.dart';
import '../runtime/registry.dart';

class PluginsPage extends StatefulWidget {
  const PluginsPage({
    super.key,
    required this.repository,
    this.embedded = false,
    this.scrollHeader,
  });
  final PluginRepository repository;
  final bool embedded;
  final Widget? scrollHeader;
  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  bool _busy = false;
  String? _error;
  late final Future<void> _ready = widget.repository.ready;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withReadStream: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final stream =
          file.readStream ??
          (file.path == null ? null : File(file.path!).openRead());
      if (file.size > maxPluginBytes || stream == null) {
        throw const PluginException(
          'Choose a readable JSON plugin file up to 256 KiB.',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (builder.length + chunk.length > maxPluginBytes) {
          throw const PluginException('The plugin file exceeds 256 KiB.');
        }
        builder.add(chunk);
      }
      final plugin = PluginManifest.parse(builder.takeBytes());
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text('Install ${plugin.name}?'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${plugin.id}\nVersion ${plugin.version}'),
                    const SizedBox(height: 16),
                    if (plugin.description != null) Text(plugin.description!),
                    const SizedBox(height: 16),
                    Text(
                      plugin.executable
                          ? 'This plugin can make the requests below while its bots are started. Install packages only from an author you trust with their API credentials.'
                          : 'Setup only. This package adds configuration fields without executing automations.',
                    ),
                    if (plugin.executable) ...[
                      for (final automation in plugin.automations) ...[
                        const SizedBox(height: 12),
                        Text(
                          automation.trigger.type == 'telegram.command.v1'
                              ? '/${automation.trigger.config['command']} · everyone'
                              : '${automation.trigger.type} · ${automation.trigger.config['intervalSeconds']} seconds',
                        ),
                        for (final c in [
                          automation.trigger,
                          ...automation.actions,
                        ])
                          for (final request in AutomationRegistry.standard
                              .requestsFor(c))
                            Text('GET ${request['url']}'),
                      ],
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Additional fields: ${plugin.fields.map((f) => f.label).join(', ')}',
                    ),
                    if (plugin.settings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Editable settings: ${plugin.settings.map((s) => s.label).join(', ')}',
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Install'),
                ),
              ],
            ),
      );
      if (accepted == true) await widget.repository.install(plugin);
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error =
                  error is PluginException
                      ? error.message
                      : 'The plugin could not be installed. No settings were changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uninstall(PluginManifest plugin) async {
    try {
      await widget.repository.uninstall(plugin.storageKey);
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error =
                  error is PluginException
                      ? error.message
                      : 'The plugin could not be removed.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const BEmptyState(
            icon: Icons.extension_off_outlined,
            title: 'Plugins unavailable',
            message:
                'Plugin storage could not be opened. Reopen Bottogram to try again.',
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListenableBuilder(
          listenable: widget.repository,
          builder: (context, _) {
            final plugins = widget.repository.installed;
            return SingleChildScrollView(
              child: BContent(
                padding: EdgeInsets.fromLTRB(
                  24,
                  widget.scrollHeader == null ? 24 : 16,
                  24,
                  24 +
                      (widget.embedded
                          ? MediaQuery.paddingOf(context).bottom
                          : 0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.scrollHeader != null) widget.scrollHeader!,
                    BHeading(
                      title: 'Plugins',
                      subtitle: 'Add a setup for the way your bot works.',
                      actions: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _install,
                          icon: const Icon(Icons.file_open_outlined),
                          label: Text(
                            _busy ? 'Reading package…' : 'Install from file',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const BNotice(
                      message:
                          'Plugins add setup fields and settings. API requests and plugin execution are not enabled in this release.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: BNotice(message: _error!, error: true),
                      ),
                    const SizedBox(height: 20),
                    if (plugins.isEmpty)
                      const BEmptyState(
                        icon: Icons.extension_outlined,
                        title: 'Your next integration',
                        message:
                            'Install a .bottogram-plugin.json file, then choose it when creating a bot.',
                      ),
                    for (final plugin in plugins)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: BPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: BColors.of(context).subtle,
                                      borderRadius:
                                          BottogramDesign.controlRadius,
                                    ),
                                    child: const Icon(Icons.extension_outlined),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          plugin.name,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                        ),
                                        Text(
                                          'Version ${plugin.version} · ${plugin.executable ? 'Live automations' : 'Setup only'}',
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Uninstall ${plugin.name}',
                                    onPressed:
                                        _busy ? null : () => _uninstall(plugin),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              if (plugin.description != null) ...[
                                const SizedBox(height: 16),
                                Text(plugin.description!),
                              ],
                              const SizedBox(height: 20),
                              const Divider(),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 24,
                                runSpacing: 8,
                                children: [
                                  Text(
                                    '${widget.repository.dependents(plugin.storageKey)} ${widget.repository.dependents(plugin.storageKey) == 1 ? 'bot' : 'bots'} using this version',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    '${plugin.fields.length} setup ${plugin.fields.length == 1 ? 'field' : 'fields'} · ${plugin.settings.length} ${plugin.settings.length == 1 ? 'setting' : 'settings'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return widget.embedded
        ? content
        : Scaffold(appBar: AppBar(title: const Text('Plugins')), body: content);
  }
}
