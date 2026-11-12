import 'dart:async';

import 'package:bottogram/l10n/strings.dart';
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
import 'package:bottogram/runtime/telegram_connection.dart';
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
  bool _retryingTelegram = false;
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
      title: context.strings.addEvent,
      fieldLabel: context.strings.query,
      initialType: VirtEventType.command,
      types: {
        VirtEventType.command: context.strings.command,
        VirtEventType.text: context.strings.textMessage,
        VirtEventType.callbackQuery: context.strings.callbackQuery,
        VirtEventType.inlineQuery: context.strings.inlineQuery,
        VirtEventType.polling: context.strings.pollingTimer,
      },
      validate: (query) =>
          widget.bot.events.any((event) => event.query == query)
          ? context.strings.anEventWithThisQueryAlready
          : null,
      action: context.strings.addEvent,
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
      if (mounted) {
        context.showSnackBar(context.strings.theEventCouldNotBeSaved);
      }
    }
  }

  Future<void> _remove() async {
    final accepted = await confirmRemoval(
      context,
      title: context.strings.deleteBot,
      message: context.strings.deleteBotConfirmation(widget.bot.name),
      action: context.strings.deleteBotAction,
    );
    if (!accepted || !mounted) return;
    try {
      await context.read<BotsCubit>().remove(widget.bot);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        context.showSnackBar(context.strings.theBotCouldNotBeRemoved);
      }
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

  Future<void> _retryTelegram() async {
    if (_retryingTelegram) return;
    setState(() => _retryingTelegram = true);
    try {
      await context.read<BotsCubit>().retryBot(widget.bot);
    } catch (_) {
      if (mounted && widget.bot.telegramConnectionIssue == null) {
        context.showSnackBar(context.strings.thisBotCouldNotRestartCheck);
      }
    } finally {
      if (mounted) setState(() => _retryingTelegram = false);
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
        context.showSnackBar(context.strings.theDatabaseBrowserCouldNotBe);
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
    final connectionIssue = widget.bot.telegramConnectionIssue;
    final failures = widget.bot.runtimeError == null
        ? const <FailurePresentation>[]
        : context.read<BotsCubit>().runtime.failuresFor(widget.bot);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bot.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: context.strings.botDatabase,
            icon: const Icon(Icons.storage_outlined),
            onPressed: _openDatabase,
          ),
          IconButton(
            tooltip: context.strings.executionConsole,
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
            tooltip: context.strings.usersAndInbox,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => InboxUsersPage(bot: widget.bot),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: context.strings.deleteBotAction,
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
                title: plugin
                    ? context.strings.pluginConfiguration
                    : context.strings.botConfiguration,
                subtitle: plugin
                    ? context.strings.yourIntegrationAndItsSavedSettings
                    : context.strings.chooseWhatHappensWhenSomeoneMessages,
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
              if (connectionIssue != null) ...[
                Semantics(
                  key: widget.bot.setupError == null ? _errorAnchor : null,
                  liveRegion: true,
                  child: BNotice(
                    icon: Icons.cloud_off_outlined,
                    error: true,
                    message:
                        connectionIssue == TelegramConnectionIssue.reconnecting
                        ? context.strings.telegramReconnecting
                        : context.strings.telegramConnectionRetry,
                    trailing:
                        connectionIssue == TelegramConnectionIssue.unavailable
                        ? IconButton(
                            tooltip: context.strings.retryBot,
                            onPressed: _retryingTelegram
                                ? null
                                : _retryTelegram,
                            icon: const Icon(Icons.refresh_rounded),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (!plugin && widget.bot.runtimeError != null) ...[
                BNotice(
                  key: widget.bot.setupError == null && connectionIssue == null
                      ? _errorAnchor
                      : null,
                  message: widget.bot.runtimeError!,
                  error: true,
                ),
                const SizedBox(height: 20),
              ],
              if (plugin) ...[
                BPanel(
                  child: BSection(
                    title: setup!.pluginName ?? context.strings.plugin,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BStatus(
                          label: live
                              ? (widget.bot.active
                                    ? context.strings.active
                                    : context.strings.stopped)
                              : context.strings.setupOnly,
                          color: BColors.of(context).warning,
                          background: BColors.of(context).warningWash,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: context.strings.editParameters,
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
                          context.strings.versionLabel(
                            setup.pluginKey!.split('@').last,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (manifest != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: OutlinedButton.icon(
                              onPressed: _sharingQr ? null : _shareQr,
                              icon: const Icon(Icons.qr_code_2),
                              label: Text(context.strings.shareAsQRCode),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _detail(
                          Icons.person_outline,
                          context.strings.admins,
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
                                      ? context.strings.savedSecurely
                                      : context.strings.notSet)
                                : setup.values[field.key] ??
                                      context.strings.notSet,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                BNotice(
                  message: live
                      ? context.strings.thisPluginRunsOnThisDevice
                      : context.strings.setupOnlyYourSettingsAreSaved,
                ),
                const SizedBox(height: 20),
                if (widget.bot.runtimeError != null) ...[
                  if (failures.isNotEmpty)
                    for (final (index, failure) in failures.indexed)
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
                        child: PluginFailureNotice(
                          key:
                              widget.bot.setupError == null &&
                                  connectionIssue == null &&
                                  index == 0
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
                                  context.strings.thisBotCouldNotRestartCheck,
                                );
                              }
                            }
                          },
                        ),
                      )
                  else
                    BNotice(
                      key:
                          widget.bot.setupError == null &&
                              connectionIssue == null
                          ? _errorAnchor
                          : null,
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
                          context.strings.automations,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final automation in manifest!.automations)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(automationSummary(context, automation)),
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
                                ? context.strings.stopBot
                                : widget.bot.resumeOnLaunch
                                ? context.strings.turnOffAutoStart
                                : context.strings.startBot,
                          ),
                          onPressed: () async {
                            try {
                              await context.read<BotsCubit>().toggle(
                                widget.bot,
                              );
                            } catch (_) {
                              if (context.mounted) {
                                context.showSnackBar(
                                  context.strings.theBotCouldNotBeStarted,
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
                    title: context.strings.details,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: ctrlName,
                          decoration: InputDecoration(
                            labelText: context.strings.botName,
                            suffixIcon: IconButton(
                              tooltip: context.strings.saveBotName,
                              onPressed: () {
                                if (ctrlName.text.trim().isEmpty) return;
                                widget.bot.name = ctrlName.text;
                                context.read<BotsCubit>().update();
                                setState(() {});
                                context.showSnackBar(
                                  context.strings.botNameSaved,
                                );
                              },
                              icon: const Icon(Icons.check_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _detail(
                          Icons.person_outline,
                          context.strings.admins,
                          setup?.adminIds.join(', ') ??
                              context.strings.noneAdded,
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: _editAdmins,
                            child: Text(context.strings.editAdmins),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                BSection(
                  title: context.strings.events,
                  trailing: TextButton.icon(
                    onPressed: _addEvent,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.strings.addEvent),
                  ),
                  child: BlocBuilder<BotsCubit, List<VirtBot>>(
                    builder: (context, _) {
                      if (widget.bot.events.isEmpty) {
                        return BEmptyState(
                          icon: Icons.bolt_outlined,
                          title: context.strings.giveYourBotSomethingToDo,
                          message: context.strings.addACommandTextMessageOr,
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
                                    context.strings.eventSummary(
                                      _eventLabel(event.type),
                                      '${event.acts.length}',
                                      '${_countEventBindings(event)}',
                                    ),
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
                  label: Text(context.strings.variablesAndAPICredentials),
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
    VirtEventType.command => context.strings.command,
    VirtEventType.text => context.strings.textMessage,
    VirtEventType.callbackQuery => context.strings.callbackQuery,
    VirtEventType.inlineQuery => context.strings.inlineQuery,
    VirtEventType.polling => context.strings.pollingTimer,
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
        return Text(context.strings.thisPluginHasNoEditableSettings);
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
        return BNotice(
          message: context.strings.pluginSettingsCouldNotBeLoaded,
          error: true,
        );
      }
    }
    return BNotice(
      message: context.strings.theRequiredPluginVersionIsUnavailable,
      error: true,
    );
  }
}
