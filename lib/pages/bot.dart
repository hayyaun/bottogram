import 'package:bottogram/pages/event.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BotPage extends StatefulWidget {
  const BotPage({super.key, required this.bot});

  final VirtBot bot;

  @override
  State<BotPage> createState() => _BotPageState();
}

class _BotPageState extends State<BotPage> {
  @override
  void initState() {
    super.initState();
  }

  void _addEvent() {
    final ctrlQuery = TextEditingController();
    var type = VirtEventType.command;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add an Event'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButton<String>(
                value: type.name, // Initial value
                items:
                    VirtEventType.values.map((type) {
                      return DropdownMenuItem<String>(
                        value: type.name,
                        child: Text(type.name),
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    type = VirtEventType.values.firstWhere(
                      (v) => v.name == newValue!,
                    );
                  });
                },
              ),
              TextField(
                controller: ctrlQuery,
                decoration: InputDecoration(hintText: 'Query'),
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
                final query = ctrlQuery.text;
                if (query.isEmpty) return;
                final events = widget.bot.events;
                // TODO error msg duplicate
                if (events.any((ev) => ev.query == query)) return;
                final ev = VirtEvent(query: query, type: type);
                widget.bot.addEvent(ev);
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
        title: Text(widget.bot.name),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              context.read<BotsCubit>().remove(widget.bot);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        tooltip: 'Add an Event',
        child: const Icon(Icons.add),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // list of bots
          BlocBuilder<BotsCubit, List<VirtBot>>(
            builder: (context, bots) {
              final events = widget.bot.events;
              if (events.isEmpty) {
                return Center(child: Text('List empty! create an event'));
              }
              return Expanded(
                child: ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final ev = events[index];
                    return ListTile(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (context) => EventPage(ev: ev, bot: widget.bot),
                          ),
                        );
                      },
                      title: Text('${ev.type.name}/${ev.query}'),
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
