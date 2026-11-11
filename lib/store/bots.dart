import 'dart:async';
import 'dart:io';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/storage_snapshot.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/templates/model.dart';

import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/bot_transfer.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/runtime/coordinator.dart';
import 'package:bottogram/runtime/progress_store.dart';
import 'package:bottogram/background/platform.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_preferences.dart';

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
  final BotRunPreferences? _runPreferences;
  final _awaitingRestore = <String>{};
  Set<String> _runningBots = {};
  AppLifecycleListener? _lifecycle;
  bool _restoring = false;
  bool _closing = false;

  BotsCubit(
    BuildContext ctx, {
    PluginRepository? plugins,
    BotRuntime? runtime,
    BotRunPreferences? runPreferences,
  }) : plugins = plugins ?? ctx.read<PluginRepository>(),
       _runPreferences = runPreferences,
       super([]) {
    this.runtime =
        runtime ?? BotRuntime(DesktopBackgroundPlatform(), this.plugins);
    this.runtime.addListener(_runtimeChanged);
    ready = _initBox();
    if (_runPreferences != null) {
      _lifecycle = AppLifecycleListener(onResume: _restoreOnResume);
      _restoreOnResume();
    }
  }
  void _runtimeChanged() {
    if (!isClosed) emit(List<VirtBot>.of(state));
  }

  String _runKey(VirtBot bot) =>
      '${bot.key}:${BotSetup.fingerprint(bot.token)}';

  Future<void> _setRunIntent(VirtBot bot, bool running) async {
    final preferences = _runPreferences;
    if (preferences == null || bot.resumeOnLaunch == running) return;
    final key = _runKey(bot);
    final next = {..._runningBots};
    if (running) {
      next.add(key);
    } else {
      next.remove(key);
    }
    await preferences.write(next);
    _runningBots = next;
    _awaitingRestore.remove(key);
    bot.resumeOnLaunch = running;
  }

  Future<void> _clearRunIntents() async {
    if (_runningBots.isEmpty) return;
    await _runPreferences!.write({});
    _runningBots = {};
    _awaitingRestore.clear();
    for (final bot in state) {
      bot.resumeOnLaunch = false;
    }
  }

  void _restoreOnResume() {
    if (!_restoring && !_closing) unawaited(_restoreForegroundBots());
  }

  // An existing foreground service can keep restoring bots after the activity
  // closes. Only a resumed activity can start a fresh service.
  bool get _canRestore =>
      runtime.activeCount > 0 ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _restoreForegroundBots() async {
    _restoring = true;
    try {
      await ready;
      if (_awaitingRestore.isEmpty) return;
      for (final bot in state) {
        if (_closing || !_canRestore) break;
        await _mutate(() async {
          if (_closing || !_canRestore || !bot.isInBox) return;
          final key = _runKey(bot);
          if (!_awaitingRestore.remove(key) || bot.active) return;
          try {
            await runtime.start(bot);
          } catch (_) {
            if (!_canRestore) {
              _awaitingRestore.add(key);
              return;
            }
            bot.runtimeError =
                'Automatic start failed. Check the bot and try again.';
            emit(List<VirtBot>.of(state));
          }
        });
      }
    } catch (_) {
      if (!_closing) {
        lastError = 'Saved bots could not be restored. Check local storage.';
        emit(List<VirtBot>.of(state));
      }
    } finally {
      _restoring = false;
    }
  }

  Future<void> _startRequested(VirtBot bot) async {
    final wasEnabled = bot.resumeOnLaunch;
    await _setRunIntent(bot, true);
    try {
      await runtime.start(bot);
    } catch (_) {
      if (!wasEnabled && !bot.active) await _setRunIntent(bot, false);
      emit(List<VirtBot>.of(state));
      rethrow;
    }
  }

  Future<void> toggle(VirtBot bot) => _mutate(() async {
    if (!state.contains(bot) || !bot.isInBox) {
      throw const PluginException('This bot is no longer available.');
    }
    if (bot.active || bot.resumeOnLaunch) {
      await _setRunIntent(bot, false);
      await runtime.stop(bot);
      return;
    }
    await _startRequested(bot);
  });

  Future<void> stopAll() => _mutate(() async {
    await _clearRunIntents();
    await runtime.stopAll();
    emit(List<VirtBot>.of(state));
  });

  Future<void> retryBot(VirtBot bot) => _mutate(() async {
    if (!state.contains(bot) || !bot.isInBox) {
      throw const PluginException('This bot is no longer available.');
    }
    await runtime.stop(bot);
    await _startRequested(bot);
  });

  Future<void> upgradePlugin(
    VirtBot bot,
    PluginManifest target,
  ) => _mutate(() async {
    if (!state.contains(bot) || !bot.isInBox) {
      throw const PluginException('This bot is no longer available.');
    }
    await plugins.reviewUpgrade(bot.key, bot.token, target);
    final restart = bot.active;
    try {
      // Drain the old session, including one whose polling has failed,
      // before copying its automation progress and publishing the new pin.
      await runtime.stop(bot);
      bot.setup = await plugins.upgrade(
        bot.key,
        bot.token,
        target,
        copyNamespace: (source, destination) async {
          final progress = runtime.progress;
          if (progress is! NamespaceProgressStore) {
            throw const PluginException(
              'This progress store does not support state-preserving plugin updates.',
            );
          }
          await progress.copyNamespace(source, destination);
        },
      );
    } catch (_) {
      if (restart) {
        try {
          await runtime.start(bot);
        } catch (_) {
          throw const PluginException(
            'The update failed. The previous version is saved, but it could not restart.',
          );
        }
      }
      throw PluginException(
        restart
            ? 'The update failed. The previous version is running again.'
            : 'The update failed. The previous version is still saved.',
      );
    } finally {
      emit(List<VirtBot>.of(state));
    }
    lastError = null;
    if (restart) {
      try {
        await runtime.start(bot);
      } catch (_) {
        throw const PluginException(
          'Plugin update saved. The bot could not restart. Check its connection and start it again.',
        );
      }
    }
  });

  // Initialize Hive box
  Future<void> _initBox() async {
    _box = await Hive.openBox<VirtBot>(boxName);
    await ensureBuilderSnapshot(_box!);
    try {
      await BuilderStore.shared.ready;
    } catch (_) {
      // A local storage failure should not hide the bot list.
    }
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
    final preferences = _runPreferences;
    if (preferences != null) {
      try {
        final saved = await preferences.read();
        for (final bot in bots) {
          final key = _runKey(bot);
          if (saved.contains(key)) {
            _runningBots.add(key);
            _awaitingRestore.add(key);
            bot.resumeOnLaunch = true;
          }
        }
      } catch (_) {
        lastError = 'Automatic start preferences could not be loaded.';
      }
    }
    await _publishBots(bots);
  }

  Future<void> _publishBots(List<VirtBot> bots) async {
    emit(bots);
    try {
      await runtime.setTotalBots(bots.length);
    } catch (_) {
      lastError = 'The running-bot notification could not be updated.';
      emit(List<VirtBot>.of(state));
    }
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _tail.then((_) async {
      await ready;
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<PluginBotTransfer> exportPluginBot(VirtBot bot) => _mutate(() async {
    if (!state.contains(bot) || !bot.isInBox) {
      throw const PluginException('This bot is no longer available.');
    }
    return plugins.exportBot(bot.key, name: bot.name, token: bot.token);
  });

  Future<void> importPluginBot(PluginBotTransfer transfer) async {
    final plugin = await plugins.reviewBotTransfer(transfer);
    await create(
      name: transfer.name,
      token: transfer.token,
      adminIds: transfer.adminIds.join('\n'),
      plugin: plugin,
      parameters: transfer.parameters,
      pluginSettings: transfer.settings,
    );
  }

  Future<void> create({
    required String name,
    required String token,
    required String adminIds,
    PluginManifest? plugin,
    Map<String, String> parameters = const {},
    Map<String, Object?> pluginSettings = const {},
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
      adminIds: adminIds,
      plugin: plugin,
      parameters: parameters,
      settings: pluginSettings,
    );
    final bot = VirtBot(
      name,
      token,
      addSamples: plugin == null && template == null,
    )..setup = setup;
    if (template != null) bot.events = template.events;
    dynamic key;
    var installedParts = false;
    try {
      if (template != null) {
        if (!template.parts.isEmpty) {
          await builder.installParts(template.parts, botName: name);
          installedParts = true;
        }
        for (final definition in template.variables) {
          await builder.addDefinition(builderId, definition);
        }
      }
      key = await _box!.add(bot);
      await plugins.attach(key, setup);
    } catch (_) {
      if (key != null) await _box!.delete(key);
      await plugins.discard(setup);
      if (installedParts) await builder.removeParts(template!.parts);
      if (template != null) await builder.remove(builderId);
      rethrow;
    }
    await _publishBots([...state, bot]);
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

  Future<void> updateAdmins(VirtBot bot, String adminIds) => _mutate(() async {
    if (!state.contains(bot) || !bot.isInBox) {
      throw const PluginException('This bot is no longer available.');
    }
    final restart = bot.active;
    if (restart) await runtime.stop(bot);
    try {
      bot.setup = await plugins.updateAdmins(bot.key, bot.token, adminIds);
    } finally {
      emit(List<VirtBot>.of(state));
    }
    if (restart) {
      try {
        await runtime.start(bot);
      } catch (_) {
        throw const PluginException(
          'Admins saved. The bot could not restart; check its status and start it again.',
        );
      }
    }
  });

  // Add a bot to the list and persist it
  Future<void> updatePluginParameters(
    VirtBot bot, {
    required String adminIds,
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
        adminIds: adminIds,
        parameters: parameters,
      );
    } catch (_) {
      emit(List<VirtBot>.of(state));
      throw const PluginException(
        'Parameters could not be saved. The previous configuration is unchanged; start the bot again if needed.',
      );
    }
    if (previous != null && previous.instanceId != bot.setup!.instanceId) {
      if (!restart) {
        try {
          // A failed session can still be draining after active becomes false.
          // Close it before removing progress and clear its obsolete failure.
          await runtime.stop(bot);
        } catch (_) {
          emit(List<VirtBot>.of(state));
          throw const PluginException(
            'Parameters saved. The previous session could not close; stop the bot before starting it again.',
          );
        }
      }
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
      await _publishBots([...state, bot]);
    });
  }

  // Remove a bot from the list and persist it
  Future<void> remove(VirtBot bot) => _mutate(() async {
    await _setRunIntent(bot, false);
    await runtime.stop(bot);
    final key = bot.key;
    await _box!.delete(key);
    final updatedList = List<VirtBot>.from(state)..remove(bot);
    await _publishBots(updatedList);
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
    await _clearRunIntents();
    for (final bot in state) {
      await runtime.stop(bot);
      final key = bot.key;
      await _box!.delete(key);
      await runtime.forget(bot);
      await plugins.removeSetup(key);
      await BuilderStore.shared.remove(builderBotId(bot.token));
    }
    await _publishBots([]);
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
            'Plugin bots use Share as QR code in their settings. Backup file exports cover manual bots.';
        emit(List<VirtBot>.from(state));
        return null;
      }
      final store = BuilderStore.shared;
      await store.ready;
      final library = store.parts;
      final copies = [
        for (final i in items)
          VirtBot(state[i].name, state[i].token, addSamples: false)
            ..events = [
              for (final event in state[i].events)
                VirtEvent(type: event.type, query: event.query)
                  ..config = event.config
                  ..acts = [
                    for (final action in event.acts)
                      store.resolveAction(action, library: library),
                  ],
            ],
      ];
      final tempBox = await Hive.openBox<VirtBot>(exportBoxName);
      await tempBox.clear();
      await tempBox.addAll(copies);
      await tempBox.flush();
      final dir = await getApplicationDocumentsDirectory();
      final file = XFile('${dir.path}/$exportBoxName.hive');
      final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final subject = 'Bottogram Data - $formattedDate';
      return await SharePlus.instance.share(
        ShareParams(files: [file], subject: subject),
      );
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
        await _publishBots(updatedList);
      });
    } catch (err) {
      lastError = 'The bot configuration could not be imported.';
      emit(List<VirtBot>.from(state));
      return;
    }
  }

  Future<bool> pickAndSaveFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Pick a backup file',
      type: FileType.any,
    );
    if (file == null || file.path == null) {
      debugPrint('❌ No file selected.');
      return false;
    }
    final selectedFile = File(file.path!);
    final appDocDir = await getApplicationDocumentsDirectory();
    final targetFile = File('${appDocDir.path}/$importBoxName.hive');
    await selectedFile.copy(targetFile.path); // create/overwrite
    debugPrint('✅ File copied to: ${targetFile.path}');
    return true;
  }

  @override
  Future<void> close() async {
    _closing = true;
    _lifecycle?.dispose();
    await ready;
    await _tail;
    runtime.removeListener(_runtimeChanged);
    await runtime.close();
    return super.close();
  }
}
