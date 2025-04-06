// ignore_for_file: use_build_context_synchronously

import 'package:bottogram/dialogs/share_dialog.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/utils/context.dart';
import 'package:bottogram/widgets/bot_card.dart';
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
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Add a Bot'),
              IconButton(
                onPressed: () async {
                  await context.read<BotsCubit>().import();
                  Navigator.of(context).pop(); // Close the dialog
                },
                icon: Icon(Icons.upload_file),
              ),
            ],
          ),
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
                if (bots.state.any((bot) => bot.token == token)) {
                  context.showSnackBar('Duplicate Item!');
                  return;
                }
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

  void _showShareDialog() async {
    showDialog(context: context, builder: (context) => ShareDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          IconButton(icon: Icon(Icons.share), onPressed: _showShareDialog),
        ],
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
          return Center(child: Text('List empty! create a bot'));
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
          itemBuilder: (context, index) => BotCard(bot: bots[index]),
        );
      },
    );
  }
}
