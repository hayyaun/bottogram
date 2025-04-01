import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive and open the box
  Hive.init(null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [BlocProvider<BotsCubit>(create: (context) => BotsCubit())],
      child: MaterialApp(
        title: 'Bottogram',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const MyHomePage(title: 'Bottogram'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
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
                context.read<BotsCubit>().addBot(VirtBot(name, token));
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
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // list of bots
          BlocBuilder<BotsCubit, List<VirtBot>>(
            builder: (context, bots) {
              if (bots.isEmpty) {
                return Center(child: Text('List empty! create a bot'));
              }
              return Expanded(
                child: ListView.builder(
                  itemCount: bots.length,
                  itemBuilder: (context, index) {
                    final bot = bots[index];
                    return ListTile(
                      title: Text(
                        '${bot.name} (${bot.active ? 'active' : 'offline'})',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          IconButton(
                            icon: Icon(Icons.play_arrow),
                            onPressed: () {
                              bot.start();
                              context.read<BotsCubit>().update();
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () {
                              context.read<BotsCubit>().removeBot(bot);
                            },
                          ),
                        ],
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
        onPressed: _addBot,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
