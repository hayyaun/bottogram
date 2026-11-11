import 'package:bottogram/pages/act.dart';
import 'package:bottogram/builder/catalog.dart';
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

  Future<void> _addAction() async {
    if (widget.ev.acts.length >= 64) return;
    final type = await showModalBottomSheet<VirtActType>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: ListView(
            children: [
              const ListTile(
                title: Text('Add action'),
                subtitle: Text('Connect each action using its named output.'),
              ),
              for (final type in VirtActType.values)
                if ((type != VirtActType.callbackAnswer ||
                        widget.ev.type == VirtEventType.callbackQuery) &&
                    (type != VirtActType.inlineAnswer ||
                        widget.ev.type == VirtEventType.inlineQuery))
                  ListTile(
                    title: Text(BuilderCatalog.labels[type.name] ?? type.name),
                    leading: Icon(
                      type == VirtActType.http
                          ? Icons.http
                          : BuilderCatalog.variables.contains(type.name)
                          ? Icons.data_object
                          : Icons.bolt_outlined,
                    ),
                    onTap: () => Navigator.pop(context, type),
                  ),
            ],
          ),
        ),
      ),
    );
    if (type == null || !mounted) return;
    final names = {
      for (final (i, a) in widget.ev.acts.indexed)
        a.config['output'] ?? 'step${i + 1}',
    };
    var i = 1;
    while (names.contains('action$i')) {
      i++;
    }
    final act = VirtAct(text: '', type: type)
      ..config = {'output': 'action$i', 'format': 'MarkdownV2'};
    widget.ev.acts.add(act);
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ActPage(act: act, ev: widget.ev, bot: widget.bot),
      ),
    );
    // ActPage reports a successful save; cancelled drafts never become actions.
    if (saved != true) widget.ev.acts.remove(act);
    if (mounted) setState(() {});
  }

  Future<void> _remove() async {
    final accepted = await confirmRemoval(
      context,
      title: 'Delete event?',
      message: 'Remove this event and all of its actions from the bot?',
      action: 'Delete event',
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
      title: const Text('Event'),
      actions: [
        IconButton(
          tooltip: 'Delete event',
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
              subtitle:
                  'Actions run in the order shown when this event matches.',
            ),
            const SizedBox(height: 28),
            BPanel(
              child: BSection(
                title: 'Trigger',
                description: switch (widget.ev.type) {
                  VirtEventType.command =>
                    'A Telegram command, such as /start.',
                  VirtEventType.text => 'A matching text message.',
                  VirtEventType.callbackQuery =>
                    'A callback from an inline keyboard button.',
                  VirtEventType.inlineQuery => 'A matching inline query.',
                  VirtEventType.polling =>
                    'Runs while this bot is started. Missed ticks are not replayed after an offline interval.',
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
                          decoration: const InputDecoration(labelText: 'Match'),
                          items: [
                            if (_match == 'legacy')
                              const DropdownMenuItem(
                                value: 'legacy',
                                child: Text('Existing inline pattern'),
                              ),
                            const DropdownMenuItem(
                              value: 'exact',
                              child: Text('Exact value'),
                            ),
                            const DropdownMenuItem(
                              value: 'prefix',
                              child: Text('Starts with'),
                            ),
                            if (widget.ev.type == VirtEventType.text)
                              const DropdownMenuItem(
                                value: 'any',
                                child: Text('Any text except commands'),
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
                          decoration: const InputDecoration(
                            labelText: 'Polling interval in seconds (30–86400)',
                          ),
                        ),
                      ),
                    if (_match == 'prefix')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: ctrlSeparator,
                          maxLength: 8,
                          decoration: const InputDecoration(
                            labelText: 'Input separator (optional)',
                            helperText:
                                'Split the matching suffix into {{event.inputParts.0}}, .1, and so on.',
                          ),
                        ),
                      ),
                    TextField(
                      controller: ctrlQuery,
                      decoration: InputDecoration(
                        labelText: 'Query',
                        suffixIcon: IconButton(
                          tooltip: 'Save query',
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
                                  const SnackBar(
                                    content: Text(
                                      'Enter a polling interval from 30 to 86400 seconds.',
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
                              const SnackBar(content: Text('Query saved.')),
                            );
                          },
                        ),
                      ),
                    ),
                    if (_match == 'prefix' || _match == 'any')
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Use {{event.input}} for the remaining input. Put broad text events after specific events.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            BSection(
              title: 'Actions',
              trailing: TextButton.icon(
                onPressed: _addAction,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add action'),
              ),
              child: BlocBuilder<BotsCubit, List<VirtBot>>(
                builder: (context, _) {
                  if (widget.ev.acts.isEmpty) {
                    return const BEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'What should happen next?',
                      message:
                          'Send content, call an API, update a variable or use an earlier action’s result.',
                    );
                  }
                  return Column(
                    children: [
                      for (final (index, act) in widget.ev.acts.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BPanel(
                            padding: EdgeInsets.zero,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<bool>(
                                builder: (_) => ActPage(
                                  act: act,
                                  ev: widget.ev,
                                  bot: widget.bot,
                                ),
                              ),
                            ),
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
                                act.text.isEmpty
                                    ? act.config['url']?.toString() ??
                                          act.config['variable']?.toString() ??
                                          BuilderCatalog.labels[act
                                              .type
                                              .name] ??
                                          act.type.name
                                    : act.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${BuilderCatalog.labels[act.type.name] ?? act.type.name} · ${act.config['output'] ?? 'step${index + 1}'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Move action up',
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
