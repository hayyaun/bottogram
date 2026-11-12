import 'dart:async';
import 'dart:io';

import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/runtime/progress_store.dart';
import 'package:bottogram/server/config.dart';
import 'package:bottogram/server/worker.dart';
import 'package:hive/hive.dart';

const usage = '''Usage:
  bottogram validate --config <bot.json>
  bottogram run --config <bot.json> --data-dir <directory>''';

Future<void> main(List<String> args) async {
  if (args.isEmpty ||
      (args.length == 1 && {'-h', '--help'}.contains(args.single))) {
    stdout.writeln(usage);
    return;
  }

  final command = args.first;
  final options = <String, String>{};
  for (var i = 1; i + 1 < args.length; i += 2) {
    final key = args[i];
    final value = args[i + 1];
    if (!{'--config', '--data-dir'}.contains(key) ||
        options.containsKey(key) ||
        value.isEmpty ||
        value.startsWith('--')) {
      break;
    }
    options[key] = value;
  }
  final configPath = options['--config'];
  final dataPath = options['--data-dir'];
  if (args.length != options.length * 2 + 1 ||
      configPath == null ||
      (command == 'validate'
          ? dataPath != null
          : command != 'run' || dataPath == null)) {
    stderr.writeln(usage);
    exitCode = 64;
    return;
  }

  try {
    final config = await ServerBotConfig.load(File(configPath));
    if (command == 'validate') {
      stdout.writeln('Valid configuration for ${config.manifest.storageKey}.');
      return;
    }
    await _run(config, Directory(dataPath!));
  } on ServerConfigException catch (error) {
    stderr.writeln(error.message);
    exitCode = 78;
  } on PluginException catch (error) {
    stderr.writeln(error.message);
    exitCode = 78;
  } on ServerWorkerException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } catch (_) {
    stderr.writeln('Bottogram could not start or stop cleanly.');
    exitCode = 1;
  }
}

Future<void> _run(ServerBotConfig config, Directory directory) async {
  final stop = Completer<void>();
  final subscriptions = [
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
      signal.watch().listen((_) {
        if (!stop.isCompleted) stop.complete();
      }),
  ];
  try {
    final progress = HiveProgressStore();
    try {
      await directory.create(recursive: true);
      Hive.init(directory.absolute.path);
      // Take the progress box lock before contacting Telegram.
      await progress.open();
    } catch (_) {
      throw const ServerWorkerException(
        'Could not open the data directory. Check permissions and whether another worker is using it.',
      );
    }
    if (stop.isCompleted) return;
    await runServerBot(
      config,
      progress: progress,
      stopRequested: stop.future,
      log: stdout.writeln,
    );
  } finally {
    await Future.wait([for (final sub in subscriptions) sub.cancel()]);
    await Hive.close();
  }
}
