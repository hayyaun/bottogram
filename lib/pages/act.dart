import 'package:bottogram/decorations/input.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/widgets/rmu_editor.dart';
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
        title: Text(widget.act.text),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              widget.act.ev.acts.remove(widget.act);
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
              RMUEditor(act: widget.act),
              SizedBox(height: 72),
            ],
          ),
        ),
      ),
    );
  }
}
