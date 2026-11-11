import 'package:bottogram/builder/engine.dart';
import 'package:bottogram/builder/step_editor.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/builder/values.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/ui/dialogs.dart';
import 'package:bottogram/utils/valid.dart';
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
  late final draft = VirtAct(type: widget.act.type, text: widget.act.text)
    ..config = Map.of(widget.act.config)
    ..rmu = widget.act.rmu?.copy(widget.act.rmu?.name ?? '');
  final _references = <String>[
    'event.text',
    'event.input',
    'event.userId',
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
    for (final (index, act) in widget.ev.acts.indexed) {
      if (identical(act, widget.act)) break;
      final name = act.config['output'] ?? 'step${index + 1}';
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

  Future<void> _save(BuilderStep step) async {
    if (widget.ev.acts.indexed.any(
      (entry) =>
          !identical(entry.$2, widget.act) &&
          (entry.$2.config['output'] ?? 'step${entry.$1 + 1}') ==
              step.config['output'],
    )) {
      throw const BuilderFailure(
        'Another action already uses this output name.',
      );
    }
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
    final previousText = widget.act.text,
        previousConfig = widget.act.config,
        previousKeyboard = widget.act.rmu;
    widget.act
      ..text = step.text
      ..config = step.config
      ..rmu = draft.rmu;
    final added = <VirtEvent>[];
    void bind(VirtEventType type, String query) {
      if (widget.bot.events.any((e) => e.type == type && e.query == query)) {
        return;
      }
      final event = VirtEvent(type: type, query: query);
      widget.bot.events.add(event);
      added.add(event);
    }

    final rmu = draft.rmu;
    if (rmu is VirtRMUKeyboard) {
      for (final text in rmu.items.whereType<String>()) {
        bind(VirtEventType.text, text);
      }
    }
    if (rmu is VirtRMUInlineKeyboard) {
      for (final item in rmu.items.whereType<KeyValue>()) {
        if (!isValidUrl(item.value)) {
          bind(VirtEventType.callbackQuery, item.value);
        }
      }
    }
    try {
      await context.read<BotsCubit>().saveBot(widget.bot);
    } catch (_) {
      widget.act
        ..text = previousText
        ..config = previousConfig
        ..rmu = previousKeyboard;
      widget.bot.events.removeWhere(added.contains);
      rethrow;
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    if (!await confirmRemoval(
          context,
          title: 'Delete action?',
          message: 'Later actions referring to its output will need updating.',
          action: 'Delete action',
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
      'output':
          draft.config['output'] ??
          'step${widget.ev.acts.indexOf(widget.act) + 1}',
    }),
    references: _references,
    keyboard: RMUEditor(act: draft),
    onSave: _save,
    onDelete: _remove,
  );
}
