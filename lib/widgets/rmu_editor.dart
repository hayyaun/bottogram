import 'package:bottogram/pages/templates.dart';
import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/dialogs.dart';
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
  VirtRMUType current = VirtRMUType.none;
  VirtRMU? get rmu => buffer[current];

  void loadRMUIntoBuffer(VirtRMU value) {
    current = value.type;
    buffer[current] = value;
  }

  @override
  void initState() {
    super.initState();
    if (widget.act.rmu != null) loadRMUIntoBuffer(widget.act.rmu!);
  }

  Future<void> _saveTemplate() async {
    final store = context.read<RMUsCubit>();
    final result = await showBEntryDialog<String>(
      context,
      title: 'Save keyboard template',
      fieldLabel: 'Template name',
      initialType: '',
      initialText: 'Keyboard ${store.state.length + 1}',
      action: 'Save template',
    );
    if (result == null || !mounted || rmu == null) return;
    try {
      await store.add(rmu!.copy(result.text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Template saved.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The template could not be saved. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _chooseTemplate() async {
    final selected = await Navigator.push<VirtRMU>(
      context,
      MaterialPageRoute(builder: (_) => const TemplatesPage(selectMode: true)),
    );
    if (selected == null || !mounted) return;
    final copy = selected.copy(selected.name ?? 'Keyboard');
    setState(() {
      loadRMUIntoBuffer(copy);
      widget.act.rmu = copy;
    });
  }

  void selectOption(VirtRMUType option) {
    setState(() {
      switch (option) {
        case VirtRMUType.none:
          current = option;
        case VirtRMUType.keyboard:
          loadRMUIntoBuffer(buffer[option] ?? VirtRMUKeyboard());
        case VirtRMUType.inlineKeyboard:
          loadRMUIntoBuffer(buffer[option] ?? VirtRMUInlineKeyboard());
      }
      widget.act.rmu = option == VirtRMUType.none ? null : buffer[option];
    });
  }

  @override
  Widget build(BuildContext context) => BSection(
    title: 'Keyboard',
    description: 'Add buttons below your reply or alongside the message.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in VirtRMUType.values)
              ChoiceChip(
                label: Text(switch (option) {
                  VirtRMUType.none => 'None',
                  VirtRMUType.keyboard => 'Reply keyboard',
                  VirtRMUType.inlineKeyboard => 'Inline keyboard',
                }),
                selected: current == option,
                onSelected: (_) => selectOption(option),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _chooseTemplate,
            icon: const Icon(Icons.bookmarks_outlined, size: 18),
            label: const Text('Choose template'),
          ),
        ),
        const SizedBox(height: 12),
        switch (current) {
          VirtRMUType.none => const BNotice(
            icon: Icons.keyboard_hide_outlined,
            message: 'This action has no keyboard.',
          ),
          VirtRMUType.keyboard => KeyboardEditor(
            key: ObjectKey(rmu),
            rmu: rmu as VirtRMUKeyboard,
          ),
          VirtRMUType.inlineKeyboard => InlineKeyboardEditor(
            key: ObjectKey(rmu),
            rmu: rmu as VirtRMUInlineKeyboard,
          ),
        },
        if (rmu != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saveTemplate,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Save as template'),
            ),
          ),
        ],
      ],
    ),
  );
}
