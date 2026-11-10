import 'dart:async';
import 'dart:io';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/storage_snapshot.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/templates/model.dart';

import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/background/platform.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Cubit for managing state
class BotsCubit extends Cubit<List<VirtBot>> {
  static const String boxName = 'botsbox';
  static const String importBoxName = 'importBox';
  static const String exportBoxName = 'exportBox';
  Box<VirtBot>? _box;
  final PluginRepository plugins;
  late final BotRuntime runtime;
  late final Future<void> ready;
  String? lastError;
  Future<void> _tail = Future.value();

  BotsCubit(BuildContext ctx, {PluginRepository? plugins, BotRuntime? runtime})
    : plugins = plugins ?? ctx.read<PluginRepository>(),
      super([]) {
    this.runtime =
        runtime ?? BotRuntime(DesktopBackgroundPlatform(), this.plugins);
    this.runtime.addListener(_runtimeChanged);
    ready = _initBox();
  }
  void _runtimeChanged() {
    if (!isClosed) emit(List<VirtBot>.of(state));
  }

  Future<void> toggle(VirtBot bot) =>
      bot.active ? runtime.stop(bot) : runtime.start(bot);

  // Initialize Hive box
  Future<void> _initBox() async {
    _box = await Hive.openBox<VirtBot>(boxName);
    await ensureBuilderSnapshot(_box!);
    final data = _box!.values.toList();
    debugPrint('✅ Bots: ${data.length}');
    final bots = data.cast<VirtBot>();
    try {
      await plugins.reconcile({for (final bot in bots) bot.key: bot.token});
      for (final bot in bots) {
        try {
          bot.setup = await plugins.setupFor(bot.key, bot.token);
        } catch (_) {
          bot.setupError =
              'Bot settings or its required plugin could not be loaded.';
        }
      }
    } catch (_) {
      for (final bot in bots) {
        bot.setupError = 'Bot settings storage is unavailable.';
      }
      lastError = 'Bot settings storage could not be loaded.';
    }
    emit(bots);
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _tail.then((_) async {
      await ready;
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> create({
    required String name,
    required String token,
    required String adminId,
    PluginManifest? plugin,
    Map<String, String> parameters = const {},
    BotTemplateDraft? template,
  }) => _mutate(() async {
    if (state.any((bot) => bot.token == token)) {
      throw const PluginException('This bot token is already in your list.');
    }
    final builder = BuilderStore.shared;
    final builderId = builderBotId(token);
    if (template != null) {
      if (plugin != null) {
        throw const BuilderFailure('Choose either a bot template or a plugin.');
      }
      await builder.ready;
      final tables = await builder.data.inspect(builderId, 'tables', {});
      final values = await builder.data.inspect(builderId, 'count', {
        'table': '_bottogram_values',
      });
      if ((tables['tables'] as List).any((t) => t['internal'] != true) ||
          values['count'] != 0 ||
          (await builder.definitions(builderId)).isNotEmpty ||
          (await builder.credentials(builderId)).isNotEmpty) {
        throw const BuilderFailure(
          'Existing builder data was found for this token. It has been preserved; use its original configuration or a different bot token.',
        );
      }
    }
    final setup = await plugins.prepare(
      token: token,
      adminId: adminId,
      plugin: plugin,
      parameters: parameters,
    );
    final bot = VirtBot(
      name,
      token,
      addSamples: plugin == null && template == null,
    )..setup = setup;
    if (template != null) bot.events = template.events;
    dynamic key;
    try {
      if (template != null) {
        for (final definition in template.variables) {
          await builder.addDefinition(builderId, definition);
        }
      }
      key = await _box!.add(bot);
      await plugins.attach(key, setup);
    } catch (_) {
      if (key != null) await _box!.delete(key);
      await plugins.discard(setup);
      if (template != null) await builder.remove(builderId);
      rethrow;
    }
    emit([...state, bot]);
  });

  // Persist plugin preferences independently of initial credentials.
  Future<void> updatePluginSettings(
    VirtBot bot,
    Map<String, Object?> settings,
  ) => _mutate(() async {
    if (!state.contains(bot) || !bot.isInBox) {
      throw const PluginException('This bot is no longer available.');
    }
    final restart = bot.active;
    if (restart) await runtime.stop(bot);
    bot.setup = await plugins.updateSettings(bot.key, bot.token, settings);
    if (restart) await runtime.start(bot);
    emit(List<VirtBot>.from(state));
  });

  // Add a bot to the list and persist it
  Future<void> updatePluginParameters(
    VirtBot bot, {
    required String adminId,
    required Map<String, String> parameters,
  }) => _mutate(() async {
    if (!state.contains(bot) || !bot.isInBox) {
      throw const PluginException('This bot is no longer available.');
    }
    final restart = bot.active;
    final previous = bot.setup;
    if (restart) await runtime.stop(bot);
    try {
      bot.setup = await plugins.updateParameters(
        bot.key,
        bot.token,
        adminId: adminId,
        parameters: parameters,
      );
    } catch (_) {
      emit(List<VirtBot>.of(state));
      throw const PluginException(
        'Parameters could not be saved. The previous configuration is unchanged; start the bot again if needed.',
      );
    }
    if (previous != null && previous.instanceId != bot.setup!.instanceId) {
      try {
        await runtime.progress.removeInstance(previous.instanceId);
      } catch (_) {
        lastError =
            'Parameters saved; old polling progress cleanup needs a retry.';
      }
    }
    emit(List<VirtBot>.of(state));
    if (restart) {
      try {
        await runtime.start(bot);
      } catch (_) {
        throw const PluginException(
          'Parameters saved. The bot could not restart; check the connection and start it again.',
        );
      }
    }
  });

  void add(VirtBot bot) async {
    await _mutate(() async {
      await _box!.add(bot);
      emit([...state, bot]);
    });
  }

  // Remove a bot from the list and persist it
  Future<void> remove(VirtBot bot) => _mutate(() async {
    await runtime.stop(bot);
    final key = bot.key;
    await _box!.delete(key);
    final updatedList = List<VirtBot>.from(state)..remove(bot);
    emit(updatedList);
    try {
      await runtime.forget(bot);
      await plugins.removeSetup(key);
      await BuilderStore.shared.remove(builderBotId(bot.token));
    } catch (_) {
      lastError =
          'The bot was removed, but settings cleanup needs a retry on restart.';
      emit(List<VirtBot>.from(state));
    }
  });

  // Update the list and persist it
  Future<void> saveBot(VirtBot bot) => _mutate(() async {
    if (!state.contains(bot) || !bot.isInBox) {
      throw const PluginException('This bot is no longer available.');
    }
    final restart = bot.active;
    if (restart) await runtime.stop(bot);
    await bot.save();
    lastError = null;
    if (restart) {
      try {
        await runtime.start(bot);
      } catch (_) {
        lastError =
            'Changes saved. The bot could not restart; check the console and start it again.';
      }
    }
    emit(List<VirtBot>.of(state));
  });

  void update() {
    final updatedList = List<VirtBot>.from(state);
    emit(updatedList);
    unawaited(
      _mutate(() async {
        for (final bot in state) {
          if (bot.isInBox) await bot.save();
        }
      }).catchError((Object _) {
        lastError = 'Changes could not be saved. Check local storage.';
        emit(List<VirtBot>.from(state));
      }),
    );
  }

  // Reset the list and persist it
  Future<void> reset() => _mutate(() async {
    for (final bot in state) {
      await runtime.stop(bot);
      final key = bot.key;
      await _box!.delete(key);
      await runtime.forget(bot);
      await plugins.removeSetup(key);
      await BuilderStore.shared.remove(builderBotId(bot.token));
    }
    emit([]);
  });

  // Other methods

  Future<ShareResult?> share(List<int> items) async {
    try {
      if (items.any(
        (i) =>
            state[i].setupError != null ||
            (state[i].setup?.usesPlugin ?? false),
      )) {
        lastError =
            'Plugin bot export is not available yet. Plugin API keys are never included in configuration shares.';
        emit(List<VirtBot>.from(state));
        return null;
      }
      final tempBox = await Hive.openBox<VirtBot>(exportBoxName);
      await tempBox.clear();
      for (final i in items) {
        final original = state[i];
        await tempBox.add(
          VirtBot(original.name, original.token, addSamples: false)
            ..events = original.events,
        );
      }
      await tempBox.flush();
      final dir = await getApplicationDocumentsDirectory();
      final file = XFile('${dir.path}/$exportBoxName.hive');
      final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final subject = 'Bottogram Data - $formattedDate';
      return await Share.shareXFiles([file], subject: subject);
    } catch (err) {
      debugPrint('❌ Share > $err');
      return null;
    }
  }

  Future<void> import() async {
    try {
      await ready;
      if (Hive.isBoxOpen(importBoxName)) {
        await Hive.box<VirtBot>(importBoxName).close();
      }
      if (!await pickAndSaveFile()) return;
      final tempBox = await Hive.openBox<VirtBot>(importBoxName);
      final data = tempBox.values.toList();
      debugPrint('✅ Importing > ${data.length}');
      await _mutate(() async {
        final bots = <VirtBot>[];
        for (final original in data) {
          if (state.any((bot) => bot.token == original.token) ||
              bots.any((bot) => bot.token == original.token)) {
            continue;
          }
          final bot = VirtBot(original.name, original.token, addSamples: false)
            ..events = original.events;
          await _box!.add(bot);
          bots.add(bot);
        }
        final updatedList = List<VirtBot>.from(state)..addAll(bots);
        emit(updatedList);
      });
    } catch (err) {
      lastError = 'The bot configuration could not be imported.';
      emit(List<VirtBot>.from(state));
      return;
    }
  }

  Future<bool> pickAndSaveFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: 'Pick a backup file',
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) {
      debugPrint('❌ No file selected.');
      return false;
    }
    final selectedFile = File(result.files.single.path!);
    final appDocDir = await getApplicationDocumentsDirectory();
    final targetFile = File('${appDocDir.path}/$importBoxName.hive');
    await selectedFile.copy(targetFile.path); // create/overwrite
    debugPrint('✅ File copied to: ${targetFile.path}');
    return true;
  }

  @override
  Future<void> close() async {
    await ready;
    await _tail;
    runtime.removeListener(_runtimeChanged);
    await runtime.close();
    return super.close();
  }
}
