import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/settings_form.dart';
import 'package:bottogram/plugins/parameters_page.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/pages/event.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/utils/context.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BotPage extends StatefulWidget {
  const BotPage({super.key, required this.bot});
  final VirtBot bot;
  @override
  State<BotPage> createState() => _BotPageState();
}

class _BotPageState extends State<BotPage> {
  late final ctrlName = TextEditingController(text: widget.bot.name);
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
      },
      validate:
          (query) =>
              widget.bot.events.any((event) => event.query == query)
                  ? 'An event with this query already exists.'
                  : null,
      action: 'Add event',
    );
    if (result == null || !mounted) return;
    widget.bot.addEvent(VirtEvent(query: result.text, type: result.type));
    context.read<BotsCubit>().update();
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

  @override
  Widget build(BuildContext context) {
    context.watch<BotsCubit>();
    final setup = widget.bot.setup;
    final plugin = setup?.usesPlugin ?? false;
    final manifest = context.read<PluginRepository>().manifestFor(setup);
    final live = manifest?.executable == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bot.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Users and inbox',
            onPressed:
                () => Navigator.push(
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
                subtitle:
                    plugin
                        ? 'Your integration and its saved settings.'
                        : 'Choose what happens when someone messages your bot.',
              ),
              const SizedBox(height: 28),
              if (widget.bot.setupError != null) ...[
                BNotice(message: widget.bot.setupError!, error: true),
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
                          label:
                              live
                                  ? (widget.bot.active ? 'Active' : 'Stopped')
                                  : 'Setup only',
                          color: BColors.warning,
                          background: BColors.warningWash,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Edit parameters',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed:
                              manifest == null
                                  ? null
                                  : () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder:
                                          (_) => PluginParametersPage(
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
                        const SizedBox(height: 24),
                        _detail(
                          Icons.person_outline,
                          'Admin Telegram ID',
                          setup.adminTelegramUserId,
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
                  message:
                      live
                          ? 'This plugin runs on this device while the bot is started.'
                          : 'Setup only. Your settings are saved; this installed version does not execute automations.',
                ),
                const SizedBox(height: 20),
                if (widget.bot.runtimeError != null) ...[
                  BNotice(message: widget.bot.runtimeError!, error: true),
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
                            child: Text(
                              automation.trigger.type == 'telegram.command.v1'
                                  ? '/${automation.trigger.config['command']} · available to everyone'
                                  : '${automation.id} · ${automation.trigger.type}',
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          icon: Icon(
                            widget.bot.active ? Icons.stop : Icons.play_arrow,
                          ),
                          label: Text(
                            widget.bot.active ? 'Stop bot' : 'Start bot',
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
                        if (setup != null) ...[
                          const SizedBox(height: 20),
                          _detail(
                            Icons.person_outline,
                            'Admin Telegram ID',
                            setup.adminTelegramUserId.toString(),
                          ),
                        ],
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
                                onTap:
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder:
                                            (_) => EventPage(
                                              ev: event,
                                              bot: widget.bot,
                                            ),
                                      ),
                                    ),
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
        Icon(icon, size: 20, color: BColors.muted),
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
  };
  int _countEventBindings(VirtEvent target) => widget.bot.events.fold(
    0,
    (count, event) =>
        count +
        event.acts.fold<int>(
          0,
          (count, act) => count + (act.rmu?.callsEvent(target) ?? 0),
        ),
  );

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
