import 'package:bottogram/pages/bot.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
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
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: <Widget>[buildBots(), SizedBox(height: 48)],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBot,
        tooltip: 'Add a Bot',
        child: const Icon(Icons.add),
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
        return ListView.builder(
          shrinkWrap: true,
          itemCount: bots.length,
          itemBuilder: (context, index) {
            final bot = bots[index];
            return ListTile(
              title: Text('${bot.name} (${bot.active ? 'active' : 'offline'})'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => BotPage(bot: bot)),
                );
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  IconButton(
                    icon: Icon(bot.active ? Icons.pause : Icons.play_arrow),
                    onPressed: () async {
                      await bot.toggle();
                      // ignore: use_build_context_synchronously
                      context.read<BotsCubit>().update();
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () {
                      context.read<BotsCubit>().remove(bot);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
