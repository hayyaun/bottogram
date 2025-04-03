import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/utils/list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class InlineKeyboardEditor extends StatefulWidget {
  const InlineKeyboardEditor({super.key, required this.rmu});

  final VirtRMUInlineKeyboard rmu;

  @override
  State<InlineKeyboardEditor> createState() => _KeyboardState();
}

class _KeyboardState extends State<InlineKeyboardEditor> {
  final _ctrlKBtnKey = TextEditingController();
  final _ctrlKBtnValue = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final items = widget.rmu.items;
    final matrix = splitListByNull(items);
    return Column(
      spacing: 8,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('InlineKeyboard'),
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
                      backgroundColor: WidgetStatePropertyAll(Colors.blue),
                    ),
                    child: Text(btn.key, style: TextStyle(color: Colors.white)),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget buildKeyboardItemAdd() {
    final primary = Theme.of(context).colorScheme.primaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrlKBtnKey,
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
                if (_ctrlKBtnKey.text.isEmpty) return;
                if (_ctrlKBtnValue.text.isEmpty) return;
                widget.rmu.items.add(
                  MapEntry(_ctrlKBtnKey.text, _ctrlKBtnValue.text),
                );
                context.read<BotsCubit>().update();
                setState(() {});
              },
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(primary),
              ),
              child: Icon(Icons.add, color: Colors.white),
            ),
            TextButton(
              onPressed: () {
                if (widget.rmu.items.isEmpty) return;
                widget.rmu.items.add(null);
                context.read<BotsCubit>().update();
                setState(() {});
              },
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(Colors.green),
              ),
              child: Icon(Icons.keyboard_return, color: Colors.white),
            ),
          ],
        ),
        TextField(
          controller: _ctrlKBtnValue,
          decoration: InputDecoration(
            hintText: 'Button Query',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
          ),
          keyboardType: TextInputType.text,
        ),
      ],
    );
  }
}
