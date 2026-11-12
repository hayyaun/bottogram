import 'package:bottogram/l10n/strings.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/utils/list.dart';
import 'package:bottogram/widgets/keyboard_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class InlineKeyboardEditor extends StatefulWidget {
  const InlineKeyboardEditor({super.key, required this.rmu});
  final VirtRMUInlineKeyboard rmu;
  @override
  State<InlineKeyboardEditor> createState() => _KeyboardState();
}

class _KeyboardState extends State<InlineKeyboardEditor> {
  final _label = TextEditingController();
  final _value = TextEditingController();
  @override
  void dispose() {
    _label.dispose();
    _value.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    setState(change);
    context.read<BotsCubit>().update();
  }

  void _add() {
    if (_label.text.isEmpty || _value.text.isEmpty) return;
    _update(() => widget.rmu.items.add(KeyValue(_label.text, _value.text)));
    _label.clear();
    _value.clear();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _label,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(labelText: context.strings.buttonText),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _value,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _add(),
        decoration: InputDecoration(
          labelText: context.strings.buttonQueryOrURL,
          helperText: context.strings.aURLOpensALinkOther,
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
            label: Text(context.strings.addButton),
          ),
          TextButton.icon(
            onPressed: widget.rmu.items.isEmpty
                ? null
                : () => _update(() => widget.rmu.items.add(null)),
            icon: const Icon(Icons.keyboard_return_rounded, size: 18),
            label: Text(context.strings.newRow),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (widget.rmu.items.isNotEmpty)
        KeyboardPreview(
          rows: [
            for (final row in splitListByNull(widget.rmu.items))
              [
                for (final button in row)
                  KeyboardPreviewKey(
                    label: button.key,
                    detail: button.value,
                    onRemove: () =>
                        _update(() => widget.rmu.items.remove(button)),
                  ),
              ],
          ],
        )
      else
        Text(
          context.strings.addAButtonToPreviewYour,
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
}
