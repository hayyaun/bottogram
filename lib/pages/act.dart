import 'package:bottogram/decorations/input.dart';
import 'package:bottogram/pages/templates.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/widgets/inline_keyboard_editor.dart';
import 'package:bottogram/widgets/keyboard_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ActPage extends StatefulWidget {
  const ActPage({super.key, required this.act, required this.ev});

  final VirtAct act;
  final VirtEvent ev;

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

  void _save() {
    widget.act.text = ctrlText.text;
    context.read<BotsCubit>().update();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.act.text),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              widget.ev.acts.remove(widget.act);
              context.read<BotsCubit>().update();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _save,
        tooltip: 'Save',
        child: const Icon(Icons.check),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              Text('Reply Message'),
              TextField(
                controller: ctrlText,
                keyboardType: TextInputType.multiline,
                maxLines: 8,
                decoration: inputDecorationCommon(context),
              ),
              SizedBox(height: 32),
              buildRMUEditor(),
              SizedBox(height: 72),
            ],
          ),
        ),
      ),
    );
  }

  /// TODO move everything below to rmu_editor

  void _saveTemplate() {
    final ctx = context.read<RMUsCubit>();
    final ctrlName = TextEditingController(text: 'RMU-${ctx.state.length}');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add to Templates'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrlName,
                decoration: InputDecoration(hintText: 'Markup Name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final rmuName = ctrlName.text;
                if (rmuName.isEmpty) return;
                final rmu = widget.act.rmu;
                if (rmu == null) return;
                ctx.add(rmu.copy(rmuName));
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Widget buildRMUEditor() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(child: Text('Reply Markup:')),
            TextButton(
              onPressed: () async {
                final selectedRMU = await Navigator.of(context).push<VirtRMU>(
                  MaterialPageRoute(
                    builder: (context) => TemplatesPage(selectMode: true),
                  ),
                );
                if (selectedRMU == null) return;
                widget.act.rmu = selectedRMU.copy(selectedRMU.name!);
                setState(() {});
              },
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.inversePrimary,
                ),
              ),
              child: Text("SELECT"),
            ),
          ],
        ),
        _buildRMUOptions(), // Select an Option
        if (widget.act.rmu.runtimeType == VirtRMUKeyboard)
          KeyboardEditor(rmu: widget.act.rmu as VirtRMUKeyboard)
        else if (widget.act.rmu.runtimeType == VirtRMUInlineKeyboard)
          InlineKeyboardEditor(rmu: widget.act.rmu as VirtRMUInlineKeyboard),
        TextButton(
          onPressed: _saveTemplate,
          style: ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.onSurface.withAlpha(150),
            ),
          ),
          child: Text('+ Add to Templates'),
        ),
      ],
    );
  }

  void selectOption(VirtRMUType option) {
    // Replace RMU with new one
    switch (option) {
      case VirtRMUType.none:
        widget.act.rmu = null;
        break;
      case VirtRMUType.keyboard:
        widget.act.rmu = VirtRMUKeyboard();
        break;
      case VirtRMUType.inlineKeyboard:
        widget.act.rmu = VirtRMUInlineKeyboard();
        break;
    }
    setState(() {});
  }

  Widget _buildRMUOptions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Wrap(
        spacing: 8,
        children:
            VirtRMUType.values.map((option) {
              final selected =
                  (widget.act.rmu?.type ?? VirtRMUType.none) == option;
              return ChoiceChip(
                label: Text(option.name.toUpperCase()),
                selected: selected,
                onSelected: (_) => selectOption(option),
                checkmarkColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withAlpha(18),
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                side: BorderSide.none,
              );
            }).toList(),
      ),
    );
  }
}
