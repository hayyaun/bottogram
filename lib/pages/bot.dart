import 'package:bottogram/decorations/input.dart';
import 'package:bottogram/pages/event.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/utils/context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BotPage extends StatefulWidget {
  const BotPage({super.key, required this.bot});

  final VirtBot bot;

  @override
  State<BotPage> createState() => _BotPageState();
}

class _BotPageState extends State<BotPage> {
  final ctrlName = TextEditingController();

  @override
  void initState() {
    ctrlName.text = widget.bot.name;
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
                if (events.any((ev) => ev.query == query)) {
                  context.showSnackBar('Duplicate Item!');
                  return;
                }
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
                    controller: ctrlName,
                    decoration: inputDecorationCommon(context).copyWith(
                      hintText: 'Bot Name',
                      suffixIcon: IconButton(
                        onPressed: () {
                          // update query
                          if (ctrlName.text.isEmpty) return;
                          widget.bot.name = ctrlName.text;
                          context.read<BotsCubit>().update();
                          setState(() {});
                        },
                        icon: Icon(Icons.check),
                        color: Colors.greenAccent,
                        style: ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll(
                            Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(25),
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
              final events = widget.bot.events;
              if (events.isEmpty) {
                return Expanded(
                  child: Center(child: Text('List empty! create an event')),
                );
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text('${_countEventBindings(ev)} bindings')],
                      ),
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

  int _countEventBindings(VirtEvent evToCount) {
    int count = 0;
    for (final ev in widget.bot.events) {
      for (final act in ev.acts) {
        count += act.rmu?.callsEvent(evToCount) ?? 0;
      }
    }
    return count;
  }
}
