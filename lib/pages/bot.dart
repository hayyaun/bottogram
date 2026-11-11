import 'dart:async';

import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/builder/console_page.dart';
import 'package:bottogram/builder/state_page.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/database_browser_page.dart';
import 'package:bottogram/builder/database_browser_adapter.dart';
import 'package:bottogram/plugins/bot_qr.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/settings_form.dart';
import 'package:bottogram/plugins/setup_fields.dart';
import 'package:bottogram/plugins/parameters_page.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/capability_review.dart';
import 'package:bottogram/plugins/update_section.dart';
import 'package:bottogram/plugins/failure_notice.dart';
import 'package:bottogram/pages/event.dart';
import 'package:bottogram/runtime/failure_presentation.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/utils/context.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BotPage extends StatefulWidget {
  const BotPage({
    super.key,
    required this.bot,
    this.focusError = false,
    this.focusPluginUpdate = false,
  });
  final VirtBot bot;
  final bool focusError;
  final bool focusPluginUpdate;
  @override
  State<BotPage> createState() => _BotPageState();
}

class _BotPageState extends State<BotPage> {
  late final ctrlName = TextEditingController(text: widget.bot.name);
  final _errorAnchor = GlobalKey();
  bool _sharingQr = false;
  late final _pluginUpdateAnchor = GlobalKey();

  @override
  void initState() {
    super.initState();
    final anchor = widget.focusError
        ? _errorAnchor
        : widget.focusPluginUpdate
        ? _pluginUpdateAnchor
        : null;
    if (anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = anchor.currentContext;
        if (target == null) return;
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    ctrlName.dispose();
    super.dispose();
  }

  Future<void> _addEvent() async {
    final result = await showBEntryDialog<VirtEventType>(
      context,
      title: 'Add event',
      fieldLabel: 'Query',
      initialType: VirtEventType.command,
      types: const {
        VirtEventType.command: 'Command',
        VirtEventType.text: 'Text message',
        VirtEventType.callbackQuery: 'Callback query',
        VirtEventType.inlineQuery: 'Inline query',
        VirtEventType.polling: 'Polling timer',
      },
      validate: (query) =>
          widget.bot.events.any((event) => event.query == query)
          ? 'An event with this query already exists.'
          : null,
      action: 'Add event',
    );
    if (result == null || !mounted) return;
    final event = VirtEvent(query: result.text, type: result.type);
    if (result.type == VirtEventType.polling) {
      event.config['intervalSeconds'] = 60;
    }
    widget.bot.events.add(event);
    try {
      await context.read<BotsCubit>().saveBot(widget.bot);
    } catch (_) {
      widget.bot.events.remove(event);
      if (mounted) context.showSnackBar('The event could not be saved.');
    }
  }

  Future<void> _remove() async {
    final accepted = await confirmRemoval(
      context,
      title: 'Delete bot?',
      message:
          'Remove ${widget.bot.name} and its local configuration from this device?',
      action: 'Delete bot',
    );
    if (!accepted || !mounted) return;
    try {
      await context.read<BotsCubit>().remove(widget.bot);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) context.showSnackBar('The bot could not be removed.');
    }
  }

  Future<void> _shareQr() async {
    setState(() => _sharingQr = true);
    try {
      await showPluginBotQr(context, widget.bot);
    } finally {
      if (mounted) setState(() => _sharingQr = false);
    }
  }

  Future<void> _openDatabase() async {
    try {
      await BuilderStore.shared.ready;
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DatabaseBrowserPage(
            botName: widget.bot.name,
            source: BotDatabaseBrowserSource(
              botId: builderBotId(widget.bot.token),
              inspect: BuilderStore.shared.data.inspect,
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        context.showSnackBar('The database browser could not be opened.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<BotsCubit>();
    final setup = widget.bot.setup;
    final plugin = setup?.usesPlugin ?? false;
    final manifest = context.watch<PluginRepository>().manifestFor(setup);
    final live = manifest?.executable == true;
    final failures = widget.bot.runtimeError == null
        ? const <FailurePresentation>[]
        : context.read<BotsCubit>().runtime.failuresFor(widget.bot);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bot.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Bot database',
            icon: const Icon(Icons.storage_outlined),
            onPressed: _openDatabase,
          ),
          IconButton(
            tooltip: 'Execution console',
            icon: const Icon(Icons.terminal),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => BuilderConsolePage(
                  botId: builderBotId(widget.bot.token),
                  botName: widget.bot.name,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Users and inbox',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => InboxUsersPage(bot: widget.bot),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete bot',
            onPressed: _remove,
          ),
        ],
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: BContent(
          maxWidth: 840,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BHeading(
                title: plugin ? 'Plugin configuration' : 'Bot configuration',
                subtitle: plugin
                    ? 'Your integration and its saved settings.'
                    : 'Choose what happens when someone messages your bot.',
              ),
              const SizedBox(height: 28),
              if (widget.bot.setupError != null) ...[
                BNotice(
                  key: _errorAnchor,
                  message: widget.bot.setupError!,
                  error: true,
                ),
                const SizedBox(height: 20),
              ],
              if (!plugin && widget.bot.runtimeError != null) ...[
                BNotice(
                  key: widget.bot.setupError == null ? _errorAnchor : null,
                  message: widget.bot.runtimeError!,
                  error: true,
                ),
                const SizedBox(height: 20),
              ],
              if (plugin) ...[
                BPanel(
                  child: BSection(
                    title: setup!.pluginName ?? 'Plugin',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BStatus(
                          label: live
                              ? (widget.bot.active ? 'Active' : 'Stopped')
                              : 'Setup only',
                          color: BColors.of(context).warning,
                          background: BColors.of(context).warningWash,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Edit parameters',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: manifest == null
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => PluginParametersPage(
                                      bot: widget.bot,
                                      plugin: manifest,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Version ${setup.pluginKey!.split('@').last}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (manifest != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: OutlinedButton.icon(
                              onPressed: _sharingQr ? null : _shareQr,
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('Share as QR code'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _detail(
                          Icons.person_outline,
                          'Admins',
                          setup.adminIds.join(', '),
                        ),
                        for (final field in manifest?.fields ?? <PluginField>[])
                          _detail(
                            field.type == PluginFieldType.secret
                                ? Icons.lock_outline
                                : Icons.tune_rounded,
                            field.label,
                            field.type == PluginFieldType.secret
                                ? (setup.secretFields.contains(field.key)
                                      ? 'Saved securely'
                                      : 'Not set')
                                : setup.values[field.key] ?? 'Not set',
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                BNotice(
                  message: live
                      ? 'This plugin runs on this device while the bot is started.'
                      : 'Setup only. Your settings are saved; this installed version does not execute automations.',
                ),
                const SizedBox(height: 20),
                if (widget.bot.runtimeError != null) ...[
                  if (failures.isNotEmpty)
                    for (final (index, failure) in failures.indexed)
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
                        child: PluginFailureNotice(
                          key: widget.bot.setupError == null && index == 0
                              ? _errorAnchor
                              : null,
                          failure: failure,
                          onEditParameters: manifest == null
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => PluginParametersPage(
                                      bot: widget.bot,
                                      plugin: manifest,
                                    ),
                                  ),
                                ),
                          onRetry: () async {
                            try {
                              await context.read<BotsCubit>().retryBot(
                                widget.bot,
                              );
                            } catch (_) {
                              if (context.mounted) {
                                context.showSnackBar(
                                  'This bot could not restart. Check its configuration and connection.',
                                );
                              }
                            }
                          },
                        ),
                      )
                  else
                    BNotice(
                      key: widget.bot.setupError == null ? _errorAnchor : null,
                      message: widget.bot.runtimeError!,
                      error: true,
                    ),
                  const SizedBox(height: 20),
                ],
                if (live) ...[
                  BPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Automations',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final automation in manifest!.automations)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(automationSummary(automation)),
                          ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          icon: Icon(
                            widget.bot.active || widget.bot.resumeOnLaunch
                                ? Icons.stop
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            widget.bot.active
                                ? 'Stop bot'
                                : widget.bot.resumeOnLaunch
                                ? 'Turn off auto-start'
                                : 'Start bot',
                          ),
                          onPressed: () async {
                            try {
                              await context.read<BotsCubit>().toggle(
                                widget.bot,
                              );
                            } catch (_) {
                              if (context.mounted) {
                                context.showSnackBar(
                                  'The bot could not be started or stopped. Check background settings and try again.',
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                BPanel(child: _pluginSettings()),
                if (manifest != null)
                  PluginUpdateSection(
                    key: _pluginUpdateAnchor,
                    bot: widget.bot,
                    plugin: manifest,
                  ),
              ] else ...[
                BPanel(
                  child: BSection(
                    title: 'Details',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: ctrlName,
                          decoration: InputDecoration(
                            labelText: 'Bot name',
                            suffixIcon: IconButton(
                              tooltip: 'Save bot name',
                              onPressed: () {
                                if (ctrlName.text.trim().isEmpty) return;
                                widget.bot.name = ctrlName.text;
                                context.read<BotsCubit>().update();
                                setState(() {});
                                context.showSnackBar('Bot name saved.');
                              },
                              icon: const Icon(Icons.check_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _detail(
                          Icons.person_outline,
                          'Admins',
                          setup?.adminIds.join(', ') ?? 'None added',
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: _editAdmins,
                            child: const Text('Edit admins'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                BSection(
                  title: 'Events',
                  trailing: TextButton.icon(
                    onPressed: _addEvent,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add event'),
                  ),
                  child: BlocBuilder<BotsCubit, List<VirtBot>>(
                    builder: (context, _) {
                      if (widget.bot.events.isEmpty) {
                        return const BEmptyState(
                          icon: Icons.bolt_outlined,
                          title: 'Give your bot something to do',
                          message:
                              'Add a command, text message, or callback query, then attach an action.',
                        );
                      }
                      return Column(
                        children: [
                          for (final event in widget.bot.events)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: BPanel(
                                padding: EdgeInsets.zero,
                                onTap: () async {
                                  await Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EventPage(ev: event, bot: widget.bot),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                                child: ListTile(
                                  leading: const Icon(Icons.bolt_outlined),
                                  title: Text(
                                    event.query,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${_eventLabel(event.type)} · ${event.acts.length} actions · ${_countEventBindings(event)} bindings',
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.data_object),
                  label: const Text('Variables and API credentials'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => BuilderStatePage(
                        botId: builderBotId(widget.bot.token),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: BColors.of(context).muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              SelectableText(value),
            ],
          ),
        ),
      ],
    ),
  );
  String _eventLabel(VirtEventType type) => switch (type) {
    VirtEventType.command => 'Command',
    VirtEventType.text => 'Text message',
    VirtEventType.callbackQuery => 'Callback query',
    VirtEventType.inlineQuery => 'Inline query',
    VirtEventType.polling => 'Polling timer',
  };
  int _countEventBindings(VirtEvent target) => widget.bot.events.fold(
    0,
    (count, event) =>
        count +
        event.acts.fold<int>(0, (count, act) {
          final definition = BuilderStore.shared.libraryAction(act.libraryName);
          return count + ((definition ?? act).rmu?.callsEvent(target) ?? 0);
        }),
  );

  Future<void> _editAdmins() async {
    final bots = context.read<BotsCubit>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EditAdminsDialog(
        ids: widget.bot.setup?.adminIds ?? const [],
        onSave: (ids) => bots.updateAdmins(widget.bot, ids),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Widget _pluginSettings() {
    final setup = widget.bot.setup!;
    for (final plugin in context.read<PluginRepository>().installed) {
      if (plugin.storageKey != setup.pluginKey) continue;
      if (plugin.settings.isEmpty) {
        return const Text('This plugin has no editable settings.');
      }
      try {
        return PluginSettingsForm(
          key: ValueKey(setup.instanceId),
          definitions: plugin.settings,
          values: plugin.settingValues(setup.settings),
          onSave: (values) async {
            await context.read<BotsCubit>().updatePluginSettings(
              widget.bot,
              values,
            );
            if (mounted) setState(() {});
          },
        );
      } catch (_) {
        return const BNotice(
          message: 'Plugin settings could not be loaded.',
          error: true,
        );
      }
    }
    return const BNotice(
      message: 'The required plugin version is unavailable.',
      error: true,
    );
  }
}
