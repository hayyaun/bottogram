import 'package:bottogram/decorations/input.dart';
import 'package:bottogram/pages/act.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/utils/string.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.ev, required this.bot});

  final VirtEvent ev;
  final VirtBot bot;

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  final ctrlQuery = TextEditingController();

  @override
  void initState() {
    ctrlQuery.text = widget.ev.query;
    super.initState();
  }

  void _addAction() {
    final ctrlAction = TextEditingController();
    final selectedType = ValueNotifier(VirtActType.reply);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add an Action'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder(
                valueListenable: selectedType,
                builder:
                    (ctx, v, _) => DropdownButton<VirtActType>(
                      value: v, // Initial value
                      items:
                          VirtActType.values.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type.name.toUpperCase()),
                            );
                          }).toList(),
                      onChanged: (newValue) {
                        selectedType.value = newValue!;
                      },
                    ),
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
                widget.ev.acts.add(
                  VirtAct(text: action, type: selectedType.value),
                );
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
        title: Text(widget.ev.query),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              widget.bot.events.remove(widget.ev);
              context.read<BotsCubit>().update();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAction,
        tooltip: 'Add an Action',
        child: const Icon(Icons.add),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: <Widget>[
          SizedBox(height: 24),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrlQuery,
                    decoration: inputDecorationCommon(context).copyWith(
                      hintText: 'Query',
                      suffixIcon: IconButton(
                        onPressed: () {
                          // update query
                          if (ctrlQuery.text.isEmpty) return;
                          widget.ev.query = ctrlQuery.text;
                          context.read<BotsCubit>().update();
                          setState(() {});
                        },
                        icon: Icon(Icons.check),
                        color: Colors.black,
                        style: ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll(
                            Colors.greenAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // list of bots
          BlocBuilder<BotsCubit, List<VirtBot>>(
            builder: (context, bots) {
              final acts = widget.ev.acts;
              if (acts.isEmpty) {
                return Center(child: Text('List empty! create an action'));
              }
              return Expanded(
                child: ListView.builder(
                  itemCount: acts.length,
                  itemBuilder: (context, index) {
                    final act = acts[index];
                    return ListTile(
                      title: Text('${act.type.name}/${act.text.ellipsize(20)}'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => ActPage(act: act, ev: widget.ev),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
