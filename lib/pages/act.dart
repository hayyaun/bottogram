// ignore_for_file: use_build_context_synchronously

import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/dialogs.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/utils/context.dart';
import 'package:bottogram/utils/list.dart';
import 'package:bottogram/widgets/rmu_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ActPage extends StatefulWidget {
  const ActPage({
    super.key,
    required this.act,
    required this.ev,
    required this.bot,
  });

  final VirtAct act;
  final VirtEvent ev;
  final VirtBot bot;

  @override
  State<ActPage> createState() => _ActPageState();
}

class _ActPageState extends State<ActPage> {
  final ctrlText = TextEditingController();

  @override
  void initState() {
    ctrlText.text = widget.act.text;
    super.initState();
  }

  @override
  void dispose() {
    ctrlText.dispose();
    super.dispose();
  }

  Future<void> _autoAddEventsOfRMU() async {
    final rmu = widget.act.rmu;
    if (rmu == null) return;
    final bot = widget.bot;
    final newEvs = <VirtEvent>[];
    switch (rmu.type) {
      case VirtRMUType.none:
        break;
      case VirtRMUType.keyboard:
        for (final btn in (rmu as VirtRMUKeyboard).items) {
          if (btn == null) continue;
          final duplicate = bot.events.any(
            (ev) => ev.type == VirtEventType.text && ev.query == btn,
          );
          if (duplicate) continue;
          final newEv = VirtEvent(type: VirtEventType.text, query: btn);
          bot.events.add(newEv);
          newEvs.add(newEv);
        }
        break;
      case VirtRMUType.inlineKeyboard:
        for (final btn in (rmu as VirtRMUInlineKeyboard).items) {
          if (btn == null) continue;
          final duplicate = bot.events.any(
            (ev) =>
                ev.type == VirtEventType.callbackQuery && ev.query == btn.value,
          );
          if (duplicate) continue;
          final newEv = VirtEvent(
            type: VirtEventType.callbackQuery,
            query: btn.value,
          );
          bot.events.add(newEv);
          newEvs.add(newEv);
        }
        break;
    }

    if (newEvs.isNotEmpty && mounted) {
      final evNames = newEvs.mapToList((ev) => '${ev.type.name}/${ev.query}');
      context.showSnackBar('Added new event: ${evNames.join(', ')}');
    }
  }

  Future<void> _save() async {
    widget.act.text = ctrlText.text;
    await _autoAddEventsOfRMU();
    if (!mounted) return;
    context.read<BotsCubit>().update();
    Navigator.pop(context);
  }

  Future<void> _remove() async {
    final accepted = await confirmRemoval(
      context,
      title: 'Delete action?',
      message: 'Remove this action from the event?',
      action: 'Delete action',
    );
    if (!accepted || !mounted) return;
    widget.ev.acts.remove(widget.act);
    context.read<BotsCubit>().update();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Action editor'),
      actions: [
        IconButton(
          tooltip: 'Delete action',
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
              title:
                  widget.act.type == VirtActType.reply
                      ? 'Reply message'
                      : 'Dice action',
              subtitle: 'For the “${widget.ev.query}” event.',
            ),
            const SizedBox(height: 28),
            BPanel(
              child: BSection(
                title: 'Message',
                description:
                    widget.act.type == VirtActType.dice
                        ? 'This action sends a dice animation. Its text is used as a label in Bottogram.'
                        : 'Write the message your bot will send.',
                child: TextField(
                  controller: ctrlText,
                  keyboardType: TextInputType.multiline,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Action text',
                    alignLabelWithHint: true,
                    hintText: 'Write your reply…',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            BPanel(child: RMUEditor(act: widget.act)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save action'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}
