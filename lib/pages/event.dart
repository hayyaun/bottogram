import 'package:bottogram/pages/act.dart';
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
  late final ctrlQuery = TextEditingController(text: widget.ev.query);
  @override
  void dispose() {
    ctrlQuery.dispose();
    super.dispose();
  }

  Future<void> _addAction() async {
    final result = await showBEntryDialog<VirtActType>(
      context,
      title: 'Add action',
      fieldLabel: 'Action text',
      initialType: VirtActType.reply,
      types: const {
        VirtActType.reply: 'Reply message',
        VirtActType.dice: 'Send dice',
      },
      action: 'Add action',
    );
    if (result == null || !mounted) return;
    widget.ev.acts.add(VirtAct(text: result.text, type: result.type));
    context.read<BotsCubit>().update();
  }

  Future<void> _remove() async {
    final accepted = await confirmRemoval(
      context,
      title: 'Delete event?',
      message: 'Remove this event and all of its actions from the bot?',
      action: 'Delete event',
    );
    if (!accepted || !mounted) return;
    widget.bot.events.remove(widget.ev);
    context.read<BotsCubit>().update();
    Navigator.pop(context);
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
                },
                child: TextField(
                  controller: ctrlQuery,
                  decoration: InputDecoration(
                    labelText: 'Query',
                    suffixIcon: IconButton(
                      tooltip: 'Save query',
                      icon: const Icon(Icons.check_rounded),
                      onPressed: () {
                        if (ctrlQuery.text.isEmpty) return;
                        widget.ev.query = ctrlQuery.text;
                        context.read<BotsCubit>().update();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Query saved.')),
                        );
                      },
                    ),
                  ),
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
                      message: 'Add a reply message or send a dice animation.',
                    );
                  }
                  return Column(
                    children: [
                      for (final (index, act) in widget.ev.acts.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BPanel(
                            padding: EdgeInsets.zero,
                            onTap:
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder:
                                        (_) => ActPage(
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
                                decoration: const BoxDecoration(
                                  color: BColors.subtle,
                                  borderRadius: BottogramDesign.controlRadius,
                                ),
                                child: Text('${index + 1}'),
                              ),
                              title: Text(
                                act.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                act.type == VirtActType.reply
                                    ? 'Reply message'
                                    : 'Send dice',
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
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
