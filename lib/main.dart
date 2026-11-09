import 'package:bottogram/pages/home.dart';
import 'package:bottogram/inbox/diagnostics.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/ui/design.dart';
import 'background/platform.dart';
import 'background/controller.dart';
import 'background/guide.dart';
import 'runtime/coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

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

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final navigatorKey = GlobalKey<NavigatorState>();

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PluginRepository()),
        Provider<BackgroundPlatform>(
          create: (_) => BackgroundPlatform.create(),
        ),
        ChangeNotifierProvider(
          create:
              (context) =>
                  BackgroundController(context.read<BackgroundPlatform>()),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => RMUsCubit()),
          BlocProvider(
            create: (context) {
              final platform = context.read<BackgroundPlatform>();
              final runtime = BotRuntime(
                platform,
                context.read<PluginRepository>(),
              );
              platform.onStopRequested = runtime.stopAll;
              return BotsCubit(context, runtime: runtime);
            },
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          builder:
              (context, child) => BackgroundSetupHost(
                controller: context.watch<BackgroundController>(),
                navigatorKey: navigatorKey,
                child: ValueListenableBuilder<String?>(
                  valueListenable: InboxDiagnostics.notice,
                  builder:
                      (context, error, _) => Column(
                        children: [
                          if (error != null)
                            Material(
                              color:
                                  Theme.of(context).colorScheme.errorContainer,
                              child: SafeArea(
                                bottom: false,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(error)),
                                      TextButton(
                                        onPressed:
                                            () =>
                                                InboxDiagnostics.notice.value =
                                                    null,
                                        child: const Text('Dismiss'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Expanded(child: child ?? const SizedBox.shrink()),
                        ],
                      ),
                ),
              ),
          title: 'Bottogram',
          theme: BottogramDesign.theme,
          debugShowCheckedModeBanner: false,
          home: const HomePage(title: 'Bottogram'),
        ),
      ),
    );
  }
}
