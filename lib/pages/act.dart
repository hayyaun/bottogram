import 'package:bottogram/builder/engine.dart';
import 'package:bottogram/builder/step_editor.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/ui/dialogs.dart';
import 'package:bottogram/widgets/rmu_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ActPage extends StatefulWidget {
  const ActPage({
    super.key,
    required this.act,
    required this.ev,
    required this.bot,
  });
  final VirtAct act;
  final VirtEvent ev;
  final VirtBot bot;
  @override
  State<ActPage> createState() => _ActPageState();
}

class _ActPageState extends State<ActPage> {
  final _store = BuilderStore.shared;
  late final _name = widget.act.libraryName;
  late final _source = _store.libraryAction(_name) ?? widget.act;
  late final _layout =
      _store.parts.lists.containsKey(_source.config['sharedList'])
      ? _store.parts.expandList(_source)
      : _source;
  late final draft = VirtAct(type: _layout.type, text: _layout.text)
    ..config = Map.of(_layout.config)
    ..rmu = _layout.rmu?.copy(_layout.rmu?.name ?? '');

  String get _output =>
      widget.act.config['output']?.toString() ??
      'step${widget.ev.acts.indexOf(widget.act) + 1}';
  final _references = <String>[
    'event.text',
    'event.input',
    'event.userId',
    'event.isAdmin',
    'event.firstName',
    'event.username',
    'event.chatId',
    'event.messageId',
    'event.arguments.0',
    'event.callbackData',
    'event.query',
  ];
  @override
  void initState() {
    super.initState();
    if (widget.ev.type == VirtEventType.command) {
      _references.add('event.argumentsText');
    }
    if (widget.ev.config['inputSeparator'] != null) {
      _references.add('event.inputParts.0');
    }
    for (final (index, placement) in widget.ev.acts.indexed) {
      if (identical(placement, widget.act)) break;
      final source = _store.libraryAction(placement.libraryName) ?? placement;
      final act = _store.parts.lists.containsKey(source.config['sharedList'])
          ? _store.parts.expandList(source)
          : source;
      final name = placement.config['output'] ?? 'step${index + 1}';
      _references.add(
        'steps.$name.${act.type == VirtActType.http
            ? 'body'
            : act.type == VirtActType.sql
            ? 'rows'
            : act.type == VirtActType.renderList
            ? 'text'
            : act.type == VirtActType.setVariable || act.type == VirtActType.incrementVariable
            ? 'value'
            : 'messageId'}',
      );
      if (act.type == VirtActType.renderList) {
        _references.add('steps.$name.keyboard');
        if (act.config['itemData']?.toString().trim().isNotEmpty == true) {
          _references.add('steps.$name.items');
        }
        if (act.config['richLayout'] is Map) {
          _references.add('steps.$name.rich');
        }
      }
    }
    _loadVariables();
  }

  Future<void> _loadVariables() async {
    if (!widget.bot.isInBox) return;
    try {
      final definitions = await BuilderStore.shared.definitions(
        builderBotId(widget.bot.token),
      );
      if (mounted) {
        setState(
          () => _references.addAll(
            definitions.map((d) => '${d.scope}.${d.name}'),
          ),
        );
      }
    } catch (_) {
      /* Opening the editor does not require available state storage. */
    }
  }

  String? _outputError(String name) {
    if (!BuilderValues.name.hasMatch(name)) {
      return 'Use letters, numbers and underscores; start with a letter or underscore.';
    }
    if (widget.ev.acts.indexed.any(
      (entry) =>
          !identical(entry.$2, widget.act) &&
          (entry.$2.config['output'] ?? 'step${entry.$1 + 1}') == name,
    )) {
      return 'Another action already uses this output name.';
    }
    return null;
  }

  Future<void> _addToLibrary(BuilderStep step) async {
    final entry = await showBEntryDialog<bool>(
      context,
      title: 'Save to action library',
      fieldLabel: 'Library name',
      initialType: true,
      action: 'Save and link',
      validate: (value) =>
          value.trim().length > 80 ? 'Use up to 80 characters.' : null,
    );
    if (entry == null || !mounted) return;
    await _save(step, libraryName: entry.text.trim());
  }

  Future<void> _renameOutput() async {
    final entry = await showBEntryDialog<bool>(
      context,
      title: 'Edit output name',
      fieldLabel: 'Output name',
      initialType: true,
      initialText: _output,
      action: 'Save',
      validate: _outputError,
    );
    if (entry == null || !mounted || entry.text == _output) return;
    final previous = _output;
    widget.act.config['output'] = entry.text;
    try {
      await context.read<BotsCubit>().saveBot(widget.bot);
      if (mounted) setState(() {});
    } catch (_) {
      widget.act.config['output'] = previous;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The output name could not be saved.')),
      );
    }
  }

  Future<void> _save(BuilderStep step, {String? libraryName}) async {
    final output = step.config['output'] as String;
    final error = _outputError(output);
    if (error != null) throw BuilderFailure(error);
    if (step.kind == 'callbackAnswer' &&
        widget.ev.type != VirtEventType.callbackQuery) {
      throw const BuilderFailure(
        'Button answers require a callback-query event.',
      );
    }
    if (step.kind == 'inlineAnswer' &&
        widget.ev.type != VirtEventType.inlineQuery) {
      throw const BuilderFailure(
        'Inline answers require an inline-query event.',
      );
    }
    final definition = VirtAct(type: draft.type, text: step.text)
      ..config = {...step.config}
      ..rmu = draft.rmu;
    if (draft.config.containsKey('keyboard')) {
      definition.config['keyboard'] = draft.config['keyboard'];
    } else {
      definition.config.remove('keyboard');
    }
    final resolved = _store.parts.resolve(definition);
    if (_name case final String name) {
      // The library's suggested output name is independent of this placement.
      definition.config['output'] = _source.config['output'];
      await _store.saveLibraryAction(name, definition, replace: true);
      if (mounted) Navigator.pop(context, true);
      return;
    }

    final bots = context.read<BotsCubit>();
    if (libraryName != null) {
      await _store.saveLibraryAction(libraryName, definition);
      if (!mounted) return;
    }
    final previousText = widget.act.text,
        previousConfig = widget.act.config,
        previousKeyboard = widget.act.rmu;
    final placement = libraryName == null
        ? definition
        : VirtAct.libraryReference(
            type: draft.type,
            name: libraryName,
            output: output,
          );
    widget.act
      ..text = placement.text
      ..config = placement.config
      ..rmu = placement.rmu;
    final added = widget.bot.bindKeyboardEvents(
      resolved.rmu,
      markup: resolved.config['keyboard'] is Map
          ? resolved.config['keyboard'] as Map
          : null,
    );
    try {
      await bots.saveBot(widget.bot);
    } catch (_) {
      widget.act
        ..text = previousText
        ..config = previousConfig
        ..rmu = previousKeyboard;
      widget.bot.events.removeWhere(added.contains);
      if (libraryName != null) {
        throw const BuilderFailure(
          'The action is in the library, but its link could not be saved. Add it from the action picker.',
        );
      }
      rethrow;
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    if (!await confirmRemoval(
          context,
          title: _name == null ? 'Delete action?' : 'Remove action from event?',
          message: 'Later actions referring to its output will need updating.',
          action: _name == null ? 'Delete action' : 'Remove from event',
        ) ||
        !mounted) {
      return;
    }
    final index = widget.ev.acts.indexOf(widget.act);
    widget.ev.acts.remove(widget.act);
    try {
      await context.read<BotsCubit>().saveBot(widget.bot);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      widget.ev.acts.insert(index, widget.act);
    }
  }

  @override
  Widget build(BuildContext context) => BuilderStepEditor(
    initial: BuilderStep(draft.type.name, draft.text, {
      ...draft.config,
      'output': _output,
    }),
    references: _references,
    keyboard: RMUEditor(act: draft),
    onSave: _save,
    onDelete: _remove,
    onAddToLibrary: _name == null ? _addToLibrary : null,
    libraryName: _name,
    onRenameOutput: _name == null ? null : _renameOutput,
  );
}
