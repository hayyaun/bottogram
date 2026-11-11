import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import '../plugins/secret_vault.dart';
import '../units/virt_act.dart';
import 'engine.dart';
import 'parts.dart';
import 'values.dart';
import 'database.dart';

String builderBotId(String token) =>
    sha256.convert(utf8.encode(token)).toString();

class VariableDefinition {
  const VariableDefinition(this.name, this.scope, this.type, this.initial);
  final String name, scope, type;
  final dynamic initial;
  Map<String, dynamic> toJson() => {
    'name': name,
    'scope': scope,
    'type': type,
    'default': initial,
  };
  factory VariableDefinition.fromJson(Map value) => VariableDefinition(
    value['name'] as String,
    value['scope'] as String,
    value['type'] as String,
    value['default'],
  );
  dynamic convert(dynamic value) {
    final dynamic result;
    switch (type) {
      case 'number':
        result = value is num ? value : num.tryParse(value.toString());
        if (result == null || !(result as num).isFinite) {
          throw BuilderFailure('$scope.$name requires a finite number.');
        }
      case 'boolean':
        result = value is bool
            ? value
            : value == 'true'
            ? true
            : value == 'false'
            ? false
            : null;
        if (result == null) {
          throw BuilderFailure('$scope.$name requires true or false.');
        }
      case 'text':
        result = BuilderValues.scalar(value);
      default:
        throw const BuilderFailure('Unknown variable type.');
    }
    if (result is String && utf8.encode(result).length > 4096) {
      throw const BuilderFailure('A variable value may contain at most 4 KiB.');
    }
    return result;
  }

  void validate() {
    if (!BuilderValues.name.hasMatch(name) ||
        !{'bot', 'user'}.contains(scope) ||
        !{'text', 'number', 'boolean'}.contains(type)) {
      throw const BuilderFailure('Invalid variable definition.');
    }
    convert(initial);
  }
}

/// Definition counts are small; per-user values are read on demand. No histories,
/// response bodies or repeated default values are stored in these boxes.
class BuilderStore {
  BuilderStore({SecretVault? vault, BotDatabases? data})
    : vault = vault ?? PlatformSecretVault(),
      _data = data;
  static final shared = BuilderStore();
  // Bot definition keys are SHA-256 hashes.
  static const _actionLibraryKey = 'action-library';
  static const _partsLibraryKey = 'parts-library';
  final SecretVault vault;
  BotDatabases? _data;
  BotDatabases get data => _data ??= BotDatabases(
    root: p.join(p.dirname(_definitions!.path!), 'bot_data'),
  );
  Box<dynamic>? _definitions;
  Future<void>? _opening;
  Future<void> _tail = Future.value();
  Future<void> get ready async {
    if (_definitions != null && !_definitions!.isOpen) {
      await _data?.close();
      _data = null;
      _definitions = null;
      _opening = null;
    }
    try {
      await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<void> _open() async {
    _definitions = await Hive.openBox<dynamic>('builder_definitions_v1');
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) async {
      await ready;
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Map get _savedActions => _definitions?.isOpen == true
      ? _definitions!.get(_actionLibraryKey) as Map? ?? const {}
      : const {};

  Map<String, VirtAct> get actionLibrary =>
      Map<String, VirtAct>.from(_savedActions);

  VirtAct? libraryAction(String? name) => _savedActions[name] as VirtAct?;

  BuilderParts get parts => BuilderParts(
    _definitions?.isOpen == true
        ? _definitions!.get(_partsLibraryKey) as Map?
        : null,
  );

  Future<void> installParts(BuilderParts definitions, {String? botName}) =>
      _serialize(() async {
        final updated = parts;
        if (definitions.lists.keys.any(updated.lists.containsKey) ||
            definitions.rows.keys.any(updated.rows.containsKey)) {
          throw const BuilderFailure(
            'These library entries are already installed.',
          );
        }
        void add(
          Map<String, Map<String, dynamic>> source,
          Map<String, Map<String, dynamic>> destination,
        ) {
          final names = destination.values
              .map((part) => (part['label'] as String).toLowerCase())
              .toSet();
          final prefix = botName == null
              ? ''
              : '${String.fromCharCodes(botName.runes.take(16))} · ';
          for (final entry in source.entries) {
            final base = '$prefix${entry.value['label']}';
            var label = base;
            var suffix = 2;
            while (!names.add(label.toLowerCase())) {
              label = '$base (${suffix++})';
            }
            destination[entry.key] = {...entry.value, 'label': label};
          }
        }

        add(definitions.lists, updated.lists);
        add(definitions.rows, updated.rows);
        await _writeParts(updated);
      });

  Future<void> removeParts(BuilderParts definitions) => _serialize(() async {
    final updated = parts;
    definitions.lists.keys.forEach(updated.lists.remove);
    definitions.rows.keys.forEach(updated.rows.remove);
    await _writeParts(updated);
  });

  Future<void> savePart(
    String id,
    Map<String, dynamic> definition, {
    required bool isList,
  }) => _serialize(() async {
    final label = definition['label'] as String;
    if (label.trim().isEmpty || label.length > 80) {
      throw const BuilderFailure(
        'Enter a library name of up to 80 characters.',
      );
    }
    final updated = parts;
    final entries = isList ? updated.lists : updated.rows;
    if (entries.entries.any(
      (entry) =>
          entry.key != id &&
          (entry.value['label'] as String).toLowerCase() == label.toLowerCase(),
    )) {
      throw const BuilderFailure(
        'This library already has an entry with that name.',
      );
    }
    entries[id] = definition;
    await _writeParts(updated);
  });

  Future<void> _writeParts(BuilderParts updated) => _definitions!.put(
    _partsLibraryKey,
    jsonDecode(jsonEncode(updated.toJson())),
  );

  VirtAct resolveAction(VirtAct placement, {BuilderParts? library}) =>
      (library ?? parts).resolve(actionDefinition(placement));

  VirtAct actionDefinition(VirtAct placement) {
    final name = placement.libraryName;
    if (name == null) return placement;
    final definition = libraryAction(name);
    if (definition == null || definition.type != placement.type) {
      throw BuilderFailure('The shared action "$name" could not be loaded.');
    }
    return VirtAct(type: definition.type, text: definition.text)
      ..config = {...definition.config, 'output': placement.config['output']}
      ..rmu = definition.rmu;
  }

  Future<void> saveLibraryAction(
    String name,
    VirtAct action, {
    bool replace = false,
  }) => _serialize(() async {
    if (name.trim().isEmpty || name != name.trim() || name.length > 80) {
      throw const BuilderFailure(
        'Enter an action name of up to 80 characters.',
      );
    }
    if (action.libraryName != null) {
      throw const BuilderFailure('Save an action definition, not a link.');
    }
    final entries = actionLibrary;
    if (replace) {
      if (entries[name]?.type != action.type) {
        throw const BuilderFailure('The shared action could not be loaded.');
      }
    } else if (entries.keys.any(
      (key) => key.toLowerCase() == name.toLowerCase(),
    )) {
      throw const BuilderFailure('An action with that name already exists.');
    }
    entries[name] = VirtAct(type: action.type, text: action.text)
      ..config = jsonDecode(jsonEncode(action.config)) as BuilderJson
      ..rmu = action.rmu?.copy(action.rmu?.name ?? '');
    await _definitions!.put(_actionLibraryKey, entries);
  });

  Map<String, dynamic> _record(String bot) =>
      Map<String, dynamic>.from(_definitions!.get(bot) as Map? ?? {});
  Future<List<VariableDefinition>> definitions(String bot) async {
    await ready;
    return (_record(bot)['variables'] as List? ?? [])
        .map((v) => VariableDefinition.fromJson(v as Map))
        .toList();
  }

  Future<void> addDefinition(String bot, VariableDefinition definition) =>
      _serialize(() async {
        definition.validate();
        final record = _record(bot);
        final variables = List<dynamic>.of(record['variables'] as List? ?? []);
        if (variables.length >= 64) {
          throw const BuilderFailure('A bot may define at most 64 variables.');
        }
        if (variables.any(
          (v) => v['name'] == definition.name && v['scope'] == definition.scope,
        )) {
          throw const BuilderFailure(
            'A variable with this name and scope already exists.',
          );
        }
        variables.add(definition.toJson());
        record['variables'] = variables;
        await _definitions!.put(bot, record);
      });
  Future<List<String>> credentials(String bot) async {
    await ready;
    return List<String>.from(_record(bot)['credentials'] as List? ?? []);
  }

  Future<void> removeDefinition(String bot, VariableDefinition definition) =>
      _serialize(() async {
        final record = _record(bot);
        final definitions = List<dynamic>.of(
          record['variables'] as List? ?? [],
        );
        await data.removeVariable(bot, definition.scope, definition.name);
        definitions.removeWhere(
          (d) => d['name'] == definition.name && d['scope'] == definition.scope,
        );
        record['variables'] = definitions;
        await _definitions!.put(bot, record);
      });

  String _secretKey(String bot, String name) => 'builder:$bot:$name';
  Future<String?> secret(String bot, String name) =>
      vault.read(_secretKey(bot, name));
  Future<void> saveCredential(
    String bot,
    String name,
    String value,
  ) => _serialize(() async {
    if (!BuilderValues.name.hasMatch(name) ||
        value.isEmpty ||
        value.length > 8192 ||
        value.contains('\r') ||
        value.contains('\n')) {
      throw const BuilderFailure(
        'Enter a valid credential name and a nonempty, single-line key.',
      );
    }
    final record = _record(bot),
        names = List<String>.from(_record(bot)['credentials'] as List? ?? []);
    if (!names.contains(name)) {
      if (names.length >= 32) {
        throw const BuilderFailure('A bot may save at most 32 credentials.');
      }
      names.add(name);
    }
    // Record the reference first so a failed write remains discoverable/removable.
    record['credentials'] = names;
    await _definitions!.put(bot, record);
    await vault.write(_secretKey(bot, name), value);
  });
  Future<void> removeCredential(String bot, String name) =>
      _serialize(() async {
        await vault.delete(_secretKey(bot, name));
        final record = _record(bot);
        record['credentials'] = List<String>.from(
          record['credentials'] as List? ?? [],
        )..remove(name);
        await _definitions!.put(bot, record);
      });
  BuilderVariables variables(String bot) => _BotVariables(this, bot);
  String _key(String bot, String scope, String? userId) {
    if (scope != 'bot' && scope != 'user') {
      throw const BuilderFailure('Unknown variable scope.');
    }
    if (scope == 'user' &&
        (userId == null || !RegExp(r'^\d+$').hasMatch(userId))) {
      throw const BuilderFailure(
        'User variables require an event with a Telegram user.',
      );
    }
    return scope == 'bot' ? '' : userId!;
  }

  Future<Map<String, dynamic>> read(String bot, String? userId) async {
    await ready;
    final definitions = await this.definitions(bot);
    if (definitions.isEmpty) {
      return {'bot': <String, dynamic>{}, 'user': <String, dynamic>{}};
    }
    final botValues = await data.read(bot, 'bot', '');
    final userValues = userId == null
        ? <String, dynamic>{}
        : await data.read(bot, 'user', _key(bot, 'user', userId));
    return {
      'bot': {
        for (final d in definitions.where((d) => d.scope == 'bot'))
          d.name: botValues.containsKey(d.name) ? botValues[d.name] : d.initial,
      },
      'user': {
        if (userId != null)
          for (final d in definitions.where((d) => d.scope == 'user'))
            d.name: userValues.containsKey(d.name)
                ? userValues[d.name]
                : d.initial,
      },
    };
  }

  Future<dynamic> change(
    String bot,
    String? userId,
    String scope,
    String name,
    dynamic value, {
    bool increment = false,
  }) => _serialize(() async {
    final definition = (await definitions(
      bot,
    )).where((d) => d.scope == scope && d.name == name).firstOrNull;
    if (definition == null) {
      throw BuilderFailure(
        'Unknown variable: $scope.$name. Create it in Variables first.',
      );
    }
    final owner = _key(bot, scope, userId);
    final values = await data.read(bot, scope, owner);
    final dynamic next;
    if (increment) {
      if (definition.type != 'number' || value is! num) {
        throw const BuilderFailure(
          'Increment requires a numeric variable and amount.',
        );
      }
      next = definition.convert(
        (definition.convert(values[name] ?? definition.initial) as num) + value,
      );
    } else {
      next = definition.convert(value);
    }
    if (next == definition.convert(definition.initial)) {
      values.remove(name);
    } else {
      values[name] = next;
    }
    if (utf8.encode(jsonEncode(values)).length > 16384) {
      throw const BuilderFailure('This variable record exceeds 16 KiB.');
    }
    await data.write(
      bot,
      scope,
      owner,
      name,
      next,
      remove: next == definition.convert(definition.initial),
    );
    return next;
  });
  Future<void> remove(String bot) => _serialize(() async {
    for (final name in await credentials(bot)) {
      await vault.delete(_secretKey(bot, name));
    }
    await data.remove(bot);
    await _definitions!.delete(bot);
  });
  Future<void> close() async {
    await _tail;
    await _definitions?.close();
    await _data?.close();
    _data = null;
    _definitions = null;
    _opening = null;
  }
}

class _BotVariables implements BuilderVariables, BuilderSqlVariables {
  _BotVariables(this.store, this.bot);
  final BuilderStore store;
  final String bot;
  @override
  Future<BuilderJson> read(String? userId) => store.read(bot, userId);
  @override
  Future<dynamic> change(
    String? userId,
    String scope,
    String name,
    dynamic value, {
    bool increment = false,
  }) => store.change(bot, userId, scope, name, value, increment: increment);
  @override
  Future<BuilderJson> query(String sql, List<dynamic> parameters) =>
      store.data.query(bot, sql, parameters);
}
