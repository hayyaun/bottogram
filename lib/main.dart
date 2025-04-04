import 'package:bottogram/pages/home.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive and open the box
  await Hive.initFlutter();

  // Register adapters
  Hive.registerAdapter(VirtBotAdapter());
  Hive.registerAdapter(VirtEventAdapter());
  Hive.registerAdapter(VirtEventTypeAdapter());
  Hive.registerAdapter(VirtActAdapter());
  Hive.registerAdapter(VirtActTypeAdapter());
  Hive.registerAdapter(VirtRMUKeyboardAdapter());
  Hive.registerAdapter(VirtRMUInlineKeyboardAdapter());
  Hive.registerAdapter(KeyValueAdapter());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => RMUsCubit()),
        BlocProvider(create: (context) => BotsCubit(context)),
      ],
      child: MaterialApp(
        title: 'Bottogram',
        darkTheme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(
            primary: Colors.deepPurpleAccent,
            onPrimary: Colors.white,
          ),
          primaryColorDark: Colors.deepPurpleAccent,
          scaffoldBackgroundColor: Colors.black,
        ),
        home: const HomePage(title: 'Bottogram'),
      ),
    );
  }
}
