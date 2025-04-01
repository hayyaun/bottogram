import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.ev});

  final VirtEvent ev;

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  @override
  void initState() {
    super.initState();
  }

  void _addAction() {
    final ctrlAction = TextEditingController();
    var type = VirtActType.reply;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add an Action'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButton<String>(
                value: type.name, // Initial value
                items:
                    VirtActType.values.map((type) {
                      return DropdownMenuItem<String>(
                        value: type.name,
                        child: Text(type.name.toUpperCase()),
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    type = VirtActType.values.firstWhere(
                      (v) => v.name == newValue!,
                    );
                  });
                },
              ),
              TextField(
                controller: ctrlAction,
                decoration: InputDecoration(hintText: 'Action'),
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
                final action = ctrlAction.text;
                if (action.isEmpty) return;
                widget.ev.acts.add(VirtAct(text: action, type: type));
                context.read<BotsCubit>().update();
                Navigator.of(context).pop(); // Close the dialog
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.ev.query),
        centerTitle: true,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // list of bots
          BlocBuilder<BotsCubit, List<VirtBot>>(
            builder: (context, bots) {
              final acts = widget.ev.acts;
              if (acts.isEmpty) {
                return Center(child: Text('List empty! create a action'));
              }
              return Expanded(
                child: ListView.builder(
                  itemCount: acts.length,
                  itemBuilder: (context, index) {
                    final act = acts[index];
                    return ListTile(
                      title: Text('${act.type.name}/${act.text}'),
                      trailing: IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () {
                          widget.ev.acts.remove(act);
                          context.read<BotsCubit>().update();
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAction,
        tooltip: 'Add an Action',
        child: const Icon(Icons.add),
      ),
    );
  }
}
