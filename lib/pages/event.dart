import 'package:bottogram/l10n/strings.dart';
import 'package:bottogram/pages/act.dart';
import 'package:bottogram/builder/catalog.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.ev, required this.bot});
  final VirtEvent ev;
  final VirtBot bot;
  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  late String _match =
      widget.ev.config['match']?.toString() ??
      (widget.ev.type == VirtEventType.inlineQuery ? 'legacy' : 'exact');
  late final ctrlQuery = TextEditingController(text: widget.ev.query);
  late final ctrlInterval = TextEditingController(
    text: (widget.ev.config['intervalSeconds'] ?? 60).toString(),
  );
  late bool _widgetQueries = widget.ev.config['widgetQueries'] == true;
  late final ctrlSeparator = TextEditingController(
    text: widget.ev.config['inputSeparator']?.toString() ?? '',
  );

  @override
  void dispose() {
    ctrlSeparator.dispose();
    ctrlQuery.dispose();
    ctrlInterval.dispose();
    super.dispose();
  }

  bool _supports(VirtActType type) =>
      (type != VirtActType.callbackAnswer ||
          widget.ev.type == VirtEventType.callbackQuery) &&
      (type != VirtActType.inlineAnswer ||
          widget.ev.type == VirtEventType.inlineQuery);

  String _nextOutput([String? preferred]) {
    final names = {
      for (final (index, action) in widget.ev.acts.indexed)
        action.config['output'] ?? 'step${index + 1}',
    };
    if (preferred != null &&
        BuilderValues.name.hasMatch(preferred) &&
        !names.contains(preferred)) {
      return preferred;
    }
    var index = 1;
    while (names.contains('action$index')) {
      index++;
    }
    return 'action$index';
  }

  Future<void> _addAction() async {
    if (widget.ev.acts.length >= 64) return;
    final store = BuilderStore.shared;
    final entries =
        store.actionLibrary.entries
            .where((entry) => _supports(entry.value.type))
            .toList()
          ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final selected = await showModalBottomSheet<(VirtActType, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: ListView(
            children: [
              ListTile(
                title: Text(context.strings.addAction),
                subtitle: Text(context.strings.connectEachActionUsingItsNamed),
              ),
              if (entries.isNotEmpty) ...[
                ListTile(title: Text(context.strings.actionLibrary)),
                for (final entry in entries)
                  ListTile(
                    title: Text(entry.key),
                    subtitle: Text(
                      BuilderCatalog.label(context, entry.value.type.name),
                    ),
                    leading: const Icon(Icons.link),
                    onTap: () =>
                        Navigator.pop(context, (entry.value.type, entry.key)),
                  ),
                const Divider(),
                ListTile(title: Text(context.strings.newAction)),
              ],
              for (final type in VirtActType.values.where(_supports))
                ListTile(
                  title: Text(BuilderCatalog.label(context, type.name)),
                  leading: Icon(
                    type == VirtActType.http
                        ? Icons.http
                        : BuilderCatalog.variables.contains(type.name)
                        ? Icons.data_object
                        : Icons.bolt_outlined,
                  ),
                  onTap: () => Navigator.pop(context, (type, null)),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted || widget.ev.acts.length >= 64) return;
    final (type, name) = selected;
    if (name != null) {
      final definition = store.libraryAction(name);
      if (definition == null) return;
      final act = VirtAct.libraryReference(
        type: type,
        name: name,
        output: _nextOutput(definition.config['output'] as String?),
      );
      var added = <VirtEvent>[];
      try {
        final resolved = store.resolveAction(act);
        widget.ev.acts.add(act);
        added = widget.bot.bindKeyboardEvents(
          resolved.rmu,
          markup: resolved.config['keyboard'] is Map
              ? resolved.config['keyboard'] as Map
              : null,
        );
        await context.read<BotsCubit>().saveBot(widget.bot);
      } catch (_) {
        widget.ev.acts.remove(act);
        widget.bot.events.removeWhere(added.contains);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.strings.theSharedActionCouldNotBe)),
          );
        }
      }
      if (mounted) setState(() {});
      return;
    }
    final act = VirtAct(text: '', type: type)
      ..config = {'output': _nextOutput(), 'format': 'MarkdownV2'};
    widget.ev.acts.add(act);
    final saved = await _openAction(act);
    // ActPage reports a successful save; cancelled drafts never become actions.
    if (saved != true) widget.ev.acts.remove(act);
    if (mounted) setState(() {});
  }

  Future<bool?> _openAction(VirtAct action) => Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => ActPage(act: action, ev: widget.ev, bot: widget.bot),
    ),
  );

  Future<void> _remove() async {
    final accepted = await confirmRemoval(
      context,
      title: context.strings.deleteEvent,
      message: context.strings.removeThisEventAndAllOf,
      action: context.strings.deleteEventAction,
    );
    if (!accepted || !mounted) return;
    final index = widget.bot.events.indexOf(widget.ev);
    widget.bot.events.remove(widget.ev);
    try {
      await context.read<BotsCubit>().saveBot(widget.bot);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      widget.bot.events.insert(index, widget.ev);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.strings.event),
      actions: [
        IconButton(
          tooltip: context.strings.deleteEventAction,
          icon: const Icon(Icons.delete_outline),
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
              title: widget.ev.query,
              subtitle: context.strings.actionsRunInTheOrderShown,
            ),
            const SizedBox(height: 28),
            BPanel(
              child: BSection(
                title: context.strings.trigger,
                description: switch (widget.ev.type) {
                  VirtEventType.command =>
                    context.strings.aTelegramCommandSuchAsStart,
                  VirtEventType.text => context.strings.aMatchingTextMessage,
                  VirtEventType.callbackQuery =>
                    context.strings.aCallbackFromAnInlineKeyboard,
                  VirtEventType.inlineQuery =>
                    context.strings.aMatchingInlineQuery,
                  VirtEventType.polling =>
                    context.strings.runsWhileThisBotIsStarted,
                },
                child: Column(
                  children: [
                    if ({
                      VirtEventType.text,
                      VirtEventType.callbackQuery,
                      VirtEventType.inlineQuery,
                    }.contains(widget.ev.type))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DropdownButtonFormField<String>(
                          initialValue: _match,
                          decoration: InputDecoration(
                            labelText: context.strings.match,
                          ),
                          items: [
                            if (_match == 'legacy')
                              DropdownMenuItem(
                                value: 'legacy',
                                child: Text(
                                  context.strings.existingInlinePattern,
                                ),
                              ),
                            DropdownMenuItem(
                              value: 'exact',
                              child: Text(context.strings.exactValue),
                            ),
                            DropdownMenuItem(
                              value: 'prefix',
                              child: Text(context.strings.startsWith),
                            ),
                            if (widget.ev.type == VirtEventType.text)
                              DropdownMenuItem(
                                value: 'any',
                                child: Text(
                                  context.strings.anyTextExceptCommands,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _match = value);
                          },
                        ),
                      ),
                    if (widget.ev.type == VirtEventType.polling)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: ctrlInterval,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText:
                                context.strings.pollingIntervalInSeconds3086400,
                          ),
                        ),
                      ),
                    if (widget.ev.type == VirtEventType.callbackQuery)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.strings.acceptWidgetRequests),
                        subtitle: Text(
                          context.strings.runTheseActionsForMatchingWidget,
                        ),
                        value: _widgetQueries,
                        onChanged: (value) =>
                            setState(() => _widgetQueries = value),
                      ),
                    if (_match == 'prefix')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: ctrlSeparator,
                          maxLength: 8,
                          decoration: InputDecoration(
                            labelText: context.strings.inputSeparatorOptional,
                            helperText:
                                context.strings.splitTheMatchingSuffixIntoEvent,
                          ),
                        ),
                      ),
                    TextField(
                      controller: ctrlQuery,
                      decoration: InputDecoration(
                        labelText: context.strings.query,
                        suffixIcon: IconButton(
                          tooltip: context.strings.saveQuery,
                          icon: const Icon(Icons.check_rounded),
                          onPressed: () async {
                            if (ctrlQuery.text.isEmpty && _match != 'any') {
                              return;
                            }
                            if ({
                              VirtEventType.text,
                              VirtEventType.callbackQuery,
                              VirtEventType.inlineQuery,
                            }.contains(widget.ev.type)) {
                              if (_match == 'legacy') {
                                widget.ev.config.remove('match');
                              } else {
                                widget.ev.config['match'] = _match;
                              }
                            }
                            if (widget.ev.type == VirtEventType.polling) {
                              final seconds = int.tryParse(ctrlInterval.text);
                              if (seconds == null ||
                                  seconds < 30 ||
                                  seconds > 86400) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      context
                                          .strings
                                          .enterAPollingIntervalFrom30,
                                    ),
                                  ),
                                );
                                return;
                              }
                              widget.ev.config['intervalSeconds'] = seconds;
                            }
                            if (_match == 'prefix' &&
                                ctrlSeparator.text.isNotEmpty) {
                              widget.ev.config['inputSeparator'] =
                                  ctrlSeparator.text;
                            } else {
                              widget.ev.config.remove('inputSeparator');
                            }
                            if (_widgetQueries &&
                                widget.ev.type == VirtEventType.callbackQuery) {
                              widget.ev.config['widgetQueries'] = true;
                            } else {
                              widget.ev.config.remove('widgetQueries');
                            }
                            widget.ev.query = ctrlQuery.text;
                            try {
                              await context.read<BotsCubit>().saveBot(
                                widget.bot,
                              );
                            } catch (_) {
                              return;
                            }
                            if (!context.mounted) return;
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.strings.querySaved),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (_match == 'prefix' || _match == 'any')
                      Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          context.strings.useEventInputForTheRemaining,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            BSection(
              title: context.strings.actions,
              trailing: TextButton.icon(
                onPressed: _addAction,
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.strings.addAction),
              ),
              child: BlocBuilder<BotsCubit, List<VirtBot>>(
                builder: (context, _) {
                  if (widget.ev.acts.isEmpty) {
                    return BEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: context.strings.whatShouldHappenNext,
                      message: context.strings.sendContentCallAnAPIUpdate,
                    );
                  }
                  return Column(
                    children: [
                      for (final (index, act) in widget.ev.acts.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BPanel(
                            padding: EdgeInsets.zero,
                            onTap: () async {
                              await _openAction(act);
                              if (mounted) setState(() {});
                            },
                            child: ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: BColors.of(context).subtle,
                                  borderRadius: BottogramDesign.controlRadius,
                                ),
                                child: Text('${index + 1}'),
                              ),
                              title: Text(
                                act.libraryName ??
                                    (act.text.isEmpty
                                        ? act.config['url']?.toString() ??
                                              act.config['variable']
                                                  ?.toString() ??
                                              BuilderCatalog.label(
                                                context,
                                                act.type.name,
                                              )
                                        : act.text),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${act.libraryName == null ? '' : context.strings.sharedActionPrefix}${BuilderCatalog.label(context, act.type.name)} · ${act.config['output'] ?? 'step${index + 1}'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: context.strings.moveActionUp,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: index == 0
                                        ? null
                                        : () async {
                                            setState(() {
                                              // Stabilize legacy implicit names before changing order.
                                              for (final (i, item)
                                                  in widget.ev.acts.indexed) {
                                                item.config.putIfAbsent(
                                                  'output',
                                                  () => 'step${i + 1}',
                                                );
                                              }
                                              widget.ev.acts.removeAt(index);
                                              widget.ev.acts.insert(
                                                index - 1,
                                                act,
                                              );
                                            });
                                            await context
                                                .read<BotsCubit>()
                                                .saveBot(widget.bot);
                                          },
                                    icon: const Icon(
                                      Icons.arrow_upward,
                                      size: 18,
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  );
}
