import 'dart:async';

import '../plugins/bot_setup.dart';
import '../plugins/manifest.dart';
import 'automation_runner.dart';
import 'failure_presentation.dart';
import 'ports.dart';
import 'telegram_destinations.dart';
import 'telegram_interaction.dart';
import 'telegram_port.dart';

/// The plugin part of one bot session, shared by the app and the server runner.
class PluginExecution {
  PluginExecution({
    required this.manifest,
    required this.setup,
    required this.telegram,
    required this.http,
    required this.progress,
    required this.secret,
    required this.onStatus,
    this.onFailure,
  });

  final PluginManifest manifest;
  final BotSetup setup;
  final BotTelegramPort telegram;
  final JsonTransport http;
  final ProgressStore progress;
  final Future<String?> Function(String field) secret;
  final void Function(String key, String? message) onStatus;
  final void Function(String key, FailurePresentation? failure)? onFailure;
  final _runners = <AutomationRunner>[];
  Future<void>? _telegramSync;
  Future<void>? _draining;
  bool _stopping = false;

  /// Registers all Telegram handlers before the host starts polling.
  bool start() {
    final settings = manifest.settingValues(setup.settings);
    final context = RuntimeContext(
      http: http,
      telegram: telegram,
      secret: secret,
      fields: setup.values,
      adminIds: setup.adminIds,
      settings: settings,
      destinationChatTypes: {
        for (final field in manifest.fields)
          if (field.chatTypes.isNotEmpty) field.key: field.chatTypes,
      },
    );
    var acceptsWidgets = false;
    for (final definition in manifest.automations) {
      if (definition.enabledBySetting != null &&
          settings[definition.enabledBySetting] != true) {
        continue;
      }
      final field = definition.destinationField;
      final destinations = field == null
          ? const <String?>[null]
          : parseTelegramDestinations(setup.values[field] ?? '') ?? const [];
      if (definition.trigger.type == interactionTrigger &&
          interactionRoutes(
            definition.trigger.config,
          ).any((route) => route['kind'] == 'widget')) {
        acceptsWidgets = true;
      }
      final namespace =
          '${setup.instanceId}:${manifest.digest}:${definition.id}';
      for (final destination in destinations) {
        final key = destination == null
            ? definition.id
            : '${definition.id}:$destination';
        final runner = AutomationRunner(
          definition: definition,
          context: context,
          store: progress,
          key: destination == null
              ? namespace
              : '$namespace:channel:$destination',
          channelId: destination,
          errorMessages: manifest.errorMessages,
          onFailure: (failure) {
            if (!_stopping) onFailure?.call(key, failure);
          },
          onStatus: (message) => _report(key, message),
        );
        _runners.add(runner);
        unawaited(runner.start());
      }
    }
    return acceptsWidgets;
  }

  /// Optional Telegram declarations never block polling or other automations.
  void synchronizeTelegram() {
    final declaration = manifest.telegram;
    if (declaration == null) return;
    _telegramSync = Future.wait<void>([
      if (declaration['menuButton'] != null) _synchronizeMenu(declaration),
      if (declaration['commands'] != null) _synchronizeCommands(declaration),
    ]).then((_) {});
  }

  Future<void> _synchronizeMenu(Json declaration) async {
    final success = await telegram.synchronizeMenu(declaration, setup.values);
    _report(
      '@telegram.menu',
      success
          ? null
          : 'The Telegram menu could not be updated. Command replies and other automations remain available.',
    );
  }

  Future<void> _synchronizeCommands(Json declaration) async {
    final scopeKey = '@telegram:${setup.tokenFingerprint}:commands';
    final targets = declaration['adminCommands'] == null
        ? const <String>{}
        : setup.adminIds.toSet();
    var success = false;
    try {
      final state = await progress.read(scopeKey);
      final managed = (state['admins'] as List? ?? const [])
          .cast<String>()
          .toSet();
      if (!managed.containsAll(targets)) {
        managed.addAll(targets);
        // Journal the attempted scope so a lost reply still permits cleanup.
        await progress.write(scopeKey, {'admins': managed.toList()});
      }
      final obsolete = managed.where((id) => !targets.contains(id)).toList();
      final published = await telegram.synchronizeCommands(
        declaration,
        adminIds: targets,
      );
      for (final id in obsolete) {
        if (await telegram.clearAdminCommands(id)) managed.remove(id);
      }
      if (obsolete.isNotEmpty) {
        await progress.write(scopeKey, {'admins': managed.toList()});
      }
      success = published && managed.every(targets.contains);
    } catch (_) {
      // Exceptions can contain authenticated URLs or storage data.
    }
    _report(
      '@telegram.commands',
      success
          ? null
          : 'The Telegram command list could not be updated. Command replies and other automations remain available.',
    );
  }

  void _report(String key, String? message) {
    if (!_stopping) onStatus(key, message);
  }

  /// Begin draining before closing the host's Telegram connection.
  Future<void> stop() => _draining ??= _stop();

  Future<void> _stop() async {
    _stopping = true;
    http.close();
    await Future.wait<void>([
      for (final runner in _runners) runner.stop(),
      if (_telegramSync case final sync?) sync,
    ]);
  }
}
