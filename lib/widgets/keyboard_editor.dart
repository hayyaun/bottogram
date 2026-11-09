import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/utils/list.dart';
import 'package:bottogram/widgets/keyboard_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KeyboardEditor extends StatefulWidget {
  const KeyboardEditor({super.key, required this.rmu});
  final VirtRMUKeyboard rmu;
  @override
  State<KeyboardEditor> createState() => _KeyboardState();
}

class _KeyboardState extends State<KeyboardEditor> {
  final _label = TextEditingController();
  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    setState(change);
    context.read<BotsCubit>().update();
  }

  void _add() {
    if (_label.text.isEmpty) return;
    _update(() => widget.rmu.items.add(_label.text));
    _label.clear();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _label,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _add(),
        decoration: const InputDecoration(
          labelText: 'Button text',
          hintText: 'A message to send when tapped',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add button'),
          ),
          TextButton.icon(
            onPressed:
                widget.rmu.items.isEmpty
                    ? null
                    : () => _update(() => widget.rmu.items.add(null)),
            icon: const Icon(Icons.keyboard_return_rounded, size: 18),
            label: const Text('New row'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (widget.rmu.items.isNotEmpty)
        KeyboardPreview(
          rows: [
            for (final row in splitListByNull(widget.rmu.items))
              [
                for (final label in row)
                  KeyboardPreviewKey(
                    label: label,
                    onRemove:
                        () => _update(() => widget.rmu.items.remove(label)),
                  ),
              ],
          ],
        )
      else
        Text(
          'Add a button to preview your keyboard.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
}
