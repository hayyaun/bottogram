import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ActPage extends StatefulWidget {
  const ActPage({super.key, required this.act});

  final VirtAct act;

  @override
  State<ActPage> createState() => _ActPageState();
}

class _ActPageState extends State<ActPage> {
  final ctrlText = TextEditingController();
  final ctrlKBtn = TextEditingController();

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
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.act.text),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              Text('Reply Text'),
              TextField(
                controller: ctrlText,
                keyboardType: TextInputType.multiline,
                maxLines: 8,
              ),
              SizedBox(height: 32),
              buildKeyboard(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _save,
        tooltip: 'Save',
        child: const Icon(Icons.check),
      ),
    );
  }

  Widget buildKeyboard() {
    final items = widget.act.rmu?.items;
    final List<List<String>> matrix =
        items == null ? [] : splitListByNull(items);
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
                      items?.remove(btn);
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
            if (widget.act.rmu == null) widget.act.rmu = VirtRmu();
            widget.act.rmu!.items.add(ctrlKBtn.text);
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
            if (widget.act.rmu == null) return;
            if (widget.act.rmu!.items.isEmpty) return;
            widget.act.rmu!.items.add(null);
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

List<List<String>> splitListByNull(List<String?> input) {
  List<List<String>> output = [];
  List<String> temp = [];

  for (var item in input) {
    if (item == null) {
      if (temp.isNotEmpty) {
        output.add(List.from(temp));
        temp.clear();
      }
    } else {
      temp.add(item);
    }
  }

  if (temp.isNotEmpty) {
    output.add(temp);
  }

  return output;
}
