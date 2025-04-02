import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/utils/list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KeyboardEditor extends StatefulWidget {
  const KeyboardEditor({super.key, required this.rmu});

  final VirtRMUKeyboard rmu;

  @override
  State<KeyboardEditor> createState() => _KeyboardState();
}

class _KeyboardState extends State<KeyboardEditor> {
  final ctrlKBtn = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final items = widget.rmu.items;
    final matrix = splitListByNull(items);
    return Column(
      spacing: 8,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Keyboard'),
        buildKeyboardItemAdd(),
        SizedBox(height: 12),
        for (final row in matrix)
          Row(
            spacing: 8,
            children: [
              for (final btn in row)
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      items.remove(btn);
                      context.read<BotsCubit>().update();
                      setState(() {});
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStatePropertyAll(
                        Colors.blue.shade100,
                      ),
                    ),
                    child: Text(btn),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget buildKeyboardItemAdd() {
    final primary = Theme.of(context).primaryColor;
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: TextField(
            controller: ctrlKBtn,
            decoration: InputDecoration(
              hintText: 'Button Text',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            keyboardType: TextInputType.text,
          ),
        ),
        TextButton(
          onPressed: () {
            if (ctrlKBtn.text.isEmpty) return;
            widget.rmu.items.add(ctrlKBtn.text);
            context.read<BotsCubit>().update();
            setState(() {});
          },
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(primary.withAlpha(60)),
          ),
          child: Icon(Icons.add),
        ),
        TextButton(
          onPressed: () {
            if (widget.rmu.items.isEmpty) return;
            widget.rmu.items.add(null);
            context.read<BotsCubit>().update();
            setState(() {});
          },
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(Colors.green.shade100),
          ),
          child: Icon(Icons.keyboard_return),
        ),
      ],
    );
  }
}
