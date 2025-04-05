import 'package:bottogram/pages/templates.dart';
import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/widgets/inline_keyboard_editor.dart';
import 'package:bottogram/widgets/keyboard_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RMUEditor extends StatefulWidget {
  const RMUEditor({super.key, required this.act});

  final VirtAct act;

  @override
  State<RMUEditor> createState() => _RmuEditorState();
}

class _RmuEditorState extends State<RMUEditor> {
  final Map<VirtRMUType, VirtRMU?> buffer = {};
  late VirtRMUType current;

  VirtRMU? get rmu => buffer[current];

  void loadRMUIntoBuffer(VirtRMU newRMU) {
    current = newRMU.type;
    buffer[current] = newRMU;
  }

  @override
  void initState() {
    // load current rmu into buffer
    final defaultRMU = widget.act.rmu;
    if (defaultRMU != null) loadRMUIntoBuffer(defaultRMU);
    super.initState();
  }

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
                if (rmu == null) return;
                ctx.add(rmu!.copy(rmuName));
                Navigator.of(context).pop();
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                final newRMU = selectedRMU.copy(selectedRMU.name!);
                loadRMUIntoBuffer(newRMU);
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
        _buildEditor(),

        if (rmu != null)
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

  Widget _buildEditor() {
    switch (current) {
      case VirtRMUType.none:
        return SizedBox();
      case VirtRMUType.keyboard:
        return KeyboardEditor(rmu: rmu as VirtRMUKeyboard);
      case VirtRMUType.inlineKeyboard:
        return InlineKeyboardEditor(rmu: rmu as VirtRMUInlineKeyboard);
    }
  }

  void selectOption(VirtRMUType option) {
    switch (option) {
      case VirtRMUType.none:
        current = VirtRMUType.none;
        break;
      case VirtRMUType.keyboard:
        loadRMUIntoBuffer(buffer[option] ?? VirtRMUKeyboard());
        break;
      case VirtRMUType.inlineKeyboard:
        loadRMUIntoBuffer(buffer[option] ?? VirtRMUInlineKeyboard());
        break;
    }
    // update act.rmu to selected rmu
    widget.act.rmu = buffer[option];
    setState(() {});
  }

  Widget _buildRMUOptions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Wrap(
        spacing: 8,
        children:
            VirtRMUType.values.map((option) {
              final selected = current == option;
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
