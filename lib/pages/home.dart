import 'package:bottogram/pages/bot.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/utils/list.dart';
import 'package:bottogram/utils/string.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
  }

  void _addBot() {
    final ctrlName = TextEditingController();
    final ctrlToken = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add a Bot'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrlName,
                decoration: InputDecoration(hintText: 'Name'),
              ),
              TextField(
                controller: ctrlToken,
                decoration: InputDecoration(hintText: 'Token'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = ctrlName.text;
                final token = ctrlToken.text;
                if (name.isEmpty || token.isEmpty) return;
                final bots = context.read<BotsCubit>();
                // TODO error msg duplicate
                if (bots.state.any((bot) => bot.token == token)) return;
                context.read<BotsCubit>().add(VirtBot(name, token));
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
        backgroundColor: Colors.transparent,
        title: Text(widget.title),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBot,
        tooltip: 'Add a Bot',
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[Expanded(child: buildBots()), SizedBox(height: 48)],
      ),
    );
  }

  Widget buildBots() {
    return BlocBuilder<BotsCubit, List<VirtBot>>(
      builder: (context, bots) {
        if (bots.isEmpty) {
          return Container(
            padding: EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Text('List empty! create a bot'),
          );
        }
        return GridView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.15,
          ),
          itemCount: bots.length,
          itemBuilder: (context, index) {
            final bot = bots[index];
            final acts = bot.events.map((ev) => ev.acts.length).sum();
            final color =
                bot.active ? Colors.greenAccent : Colors.white.withAlpha(150);
            final borderRadius = BorderRadius.circular(12);
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: borderRadius),
              margin: EdgeInsets.all(0),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => BotPage(bot: bot)),
                  );
                },
                child: Column(
                  children: [
                    Container(color: color, height: 8),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              bot.name.ellipsize(8),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w200,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              bot.active ? 'ACTIVE' : 'INACTIVE',
                            ), // TODO active hours
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text('${bot.events.length} events'),
                                      Text('$acts actions'),
                                    ],
                                  ),
                                ),
                                IconButton.filled(
                                  style: ButtonStyle(
                                    backgroundColor: WidgetStatePropertyAll(
                                      bot.active
                                          ? Colors.greenAccent
                                          : Colors.black,
                                    ),
                                  ),
                                  color:
                                      bot.active ? Colors.black : Colors.white,
                                  icon: Icon(
                                    bot.active ? Icons.pause : Icons.play_arrow,
                                  ),
                                  onPressed: () async {
                                    await bot.toggle();
                                    // ignore: use_build_context_synchronously
                                    context.read<BotsCubit>().update();
                                  },
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
