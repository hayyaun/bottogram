import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/widgets/keyboard_editor.dart';
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
              _buildRMUOptions(), // Select an Option
              if (widget.act.rmu.runtimeType == VirtRMUKeyboard)
                KeyboardEditor(rmu: widget.act.rmu as VirtRMUKeyboard),
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
              final selected = widget.act.rmu?.type == option;
              return ChoiceChip(
                label: Text(option.name.toUpperCase()),
                selected: selected,
                onSelected: (_) => selectOption(option),
                selectedColor: Colors.blue,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black,
                ),
              );
            }).toList(),
      ),
    );
  }
}
