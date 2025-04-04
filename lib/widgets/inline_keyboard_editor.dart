import 'package:bottogram/decorations/input.dart';
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
                decoration: inputDecorationCommon(context).copyWith(
                  hintText: 'Button Text',
                  suffixIcon: IconButton(
                    onPressed: () {
                      if (_ctrlKBtnKey.text.isEmpty) return;
                      if (_ctrlKBtnValue.text.isEmpty) return;
                      widget.rmu.items.add(
                        KeyValue(_ctrlKBtnKey.text, _ctrlKBtnValue.text),
                      );
                      context.read<BotsCubit>().update();
                      setState(() {});
                    },
                    color: Colors.greenAccent,
                    style: ButtonStyle(
                      backgroundColor: WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.onSurface.withAlpha(25),
                      ),
                    ),
                    icon: Icon(Icons.add),
                  ),
                ),
                keyboardType: TextInputType.text,
              ),
            ),
            IconButton(
              padding: EdgeInsets.all(12),
              onPressed: () {
                if (widget.rmu.items.isEmpty) return;
                widget.rmu.items.add(null);
                context.read<BotsCubit>().update();
                setState(() {});
              },
              icon: Icon(Icons.keyboard_return),
            ),
          ],
        ),
        TextField(
          controller: _ctrlKBtnValue,
          decoration: inputDecorationCommon(
            context,
          ).copyWith(hintText: 'Button Query'),
          keyboardType: TextInputType.text,
        ),
      ],
    );
  }
}
