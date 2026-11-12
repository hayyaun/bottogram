import 'dart:typed_data';

import 'package:bottogram/l10n/strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/utils/context.dart';
import 'package:url_launcher/url_launcher.dart';

import 'manifest.dart';
import 'repository.dart';
import 'capability_review.dart';

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

  Future<void> _openAuthoringGuide() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(
          'https://github.com/hayyaun/bottogram/blob/main/docs/PLUGIN_AUTHORING.md',
        ),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Platform diagnostics are not useful as user-facing browser guidance.
    }
    if (!opened && mounted) {
      context.showSnackBar(context.strings.thePluginGuideCouldNotBe);
    }
  }

  Future<void> _install() async {
    final strings = context.strings;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final length = file.lengthSync() ?? await file.length();
      if (length != null && length > maxPluginBytes) {
        throw PluginException(strings.chooseAReadableJSONPluginFile);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (builder.length + chunk.length > maxPluginBytes) {
          throw PluginException(strings.thePluginFileExceeds256KiB);
        }
        builder.add(chunk);
      }
      final plugin = PluginManifest.parse(builder.takeBytes());
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.strings.installPluginConfirmation(plugin.name)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.strings.pluginNameAndVersion(
                    plugin.id,
                    plugin.version,
                  ),
                ),
                const SizedBox(height: 16),
                if (plugin.description != null) Text(plugin.description!),
                const SizedBox(height: 16),
                Text(
                  plugin.executable
                      ? context.strings.thisPluginCanMakeTheRequests
                      : context.strings.setupOnlyThisPackageAddsConfiguration,
                ),
                if (plugin.executable) PluginCapabilityReview(plugin: plugin),
                const SizedBox(height: 12),
                Text(
                  context.strings.additionalPluginFields(
                    plugin.fields.map((f) => f.label).join(', '),
                  ),
                ),
                if (plugin.settings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.strings.editablePluginSettings(
                      plugin.settings.map((s) => s.label).join(', '),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.strings.install),
            ),
          ],
        ),
      );
      if (accepted == true) await widget.repository.install(plugin);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PluginException
              ? error.message
              : context.strings.thePluginCouldNotBeInstalled,
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
          () => _error = error is PluginException
              ? error.message
              : context.strings.thePluginCouldNotBeRemoved,
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
          return BEmptyState(
            icon: Icons.extension_off_outlined,
            title: context.strings.pluginsUnavailable,
            message: context.strings.pluginStorageCouldNotBeOpened,
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
                      title: context.strings.plugins,
                      subtitle: context.strings.addASetupForTheWay,
                      actions: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _install,
                          icon: const Icon(Icons.file_open_outlined),
                          label: Text(
                            _busy
                                ? context.strings.readingPackage
                                : context.strings.installFromFile,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _openAuthoringGuide,
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text(
                          'آموزش ساخت پلاگین',
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    BNotice(
                      message: context.strings.livePluginsRunWhileTheirBots,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: BNotice(message: _error!, error: true),
                      ),
                    const SizedBox(height: 20),
                    if (plugins.isEmpty)
                      BEmptyState(
                        icon: Icons.extension_outlined,
                        title: context.strings.yourNextIntegration,
                        message:
                            context.strings.installABottogramPluginJsonFile,
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
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                        Text(
                                          context.strings
                                              .pluginVersionAndStatus(
                                                plugin.version,
                                                plugin.executable
                                                    ? context
                                                          .strings
                                                          .liveAutomations
                                                    : context.strings.setupOnly,
                                              ),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: context.strings.uninstallPlugin(
                                      plugin.name,
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _uninstall(plugin),
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
                                    context.strings.pluginDependents(
                                      widget.repository.dependents(
                                        plugin.storageKey,
                                      ),
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  Text(
                                    context.strings.pluginFieldCounts(
                                      plugin.fields.length,
                                      plugin.settings.length,
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
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
        : Scaffold(
            appBar: AppBar(title: Text(context.strings.plugins)),
            body: content,
          );
  }
}
