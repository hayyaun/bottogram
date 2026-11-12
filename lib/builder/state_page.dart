import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import '../ui/design.dart';
import '../ui/dialogs.dart';
import 'store.dart';
import 'values.dart';

class BuilderStatePage extends StatefulWidget {
  const BuilderStatePage({super.key, required this.botId});
  final String botId;
  @override
  State<BuilderStatePage> createState() => _BuilderStatePageState();
}

class _BuilderStatePageState extends State<BuilderStatePage> {
  List<VariableDefinition> _definitions = [];
  List<String> _credentials = [];
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final definitions = await BuilderStore.shared.definitions(widget.botId),
          credentials = await BuilderStore.shared.credentials(widget.botId);
      if (mounted) {
        setState(() {
          _definitions = definitions;
          _credentials = credentials;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = context.strings.localBotSettingsCouldNotBe;
        });
      }
    }
  }

  Future<void> _add(bool credential, {String? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _StateEntry(
        botId: widget.botId,
        credential: credential,
        existing: existing,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _remove({
    VariableDefinition? definition,
    String? credential,
  }) async {
    if (!await confirmRemoval(
          context,
          title: definition == null
              ? context.strings.deleteCredential
              : context.strings.deleteVariable,
          message: definition == null
              ? context.strings.actionsUsingThisCredentialWillFail
              : context.strings.removeThisVariableAndItsSaved,
          action: context.strings.delete,
        ) ||
        !mounted) {
      return;
    }
    try {
      if (definition != null) {
        await BuilderStore.shared.removeDefinition(widget.botId, definition);
      } else {
        await BuilderStore.shared.removeCredential(widget.botId, credential!);
      }
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.strings.theItemCouldNotBeRemoved);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.strings.variablesAndCredentials)),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_error != null) BNotice(message: _error!, error: true),
              BSection(
                title: context.strings.variables,
                description: context.strings.userValuesBelongToOneTelegram,
                trailing: TextButton.icon(
                  onPressed: () => _add(false),
                  icon: const Icon(Icons.add),
                  label: Text(context.strings.add),
                ),
                child: Column(
                  children: [
                    if (_definitions.isEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.strings.noVariablesYet),
                        subtitle: Text(
                          context.strings.createAVariableThenUseSet,
                        ),
                      ),
                    for (final d in _definitions)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          d.scope == 'user'
                              ? Icons.person_outline
                              : Icons.smart_toy_outlined,
                        ),
                        title: SelectableText('${d.scope}.${d.name}'),
                        subtitle: Text(
                          context.strings.variableSummary(
                            d.type,
                            '${d.initial}',
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: context.strings.deleteVariable2,
                          onPressed: () => _remove(definition: d),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              BSection(
                title: context.strings.apiCredentials,
                description: context.strings.keysAreSavedInSecureStorage,
                trailing: TextButton.icon(
                  onPressed: () => _add(true),
                  icon: const Icon(Icons.add),
                  label: Text(context.strings.add),
                ),
                child: Column(
                  children: [
                    if (_credentials.isEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.strings.noSavedCredentials),
                      ),
                    for (final name in _credentials)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.key_outlined),
                        title: Text(name),
                        subtitle: Text(context.strings.valueHidden),
                        onTap: () => _add(true, existing: name),
                        trailing: IconButton(
                          tooltip: context.strings.deleteCredential2,
                          onPressed: () => _remove(credential: name),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
  );
}

class _StateEntry extends StatefulWidget {
  const _StateEntry({
    required this.botId,
    required this.credential,
    this.existing,
  });
  final String botId;
  final bool credential;
  final String? existing;
  @override
  State<_StateEntry> createState() => _StateEntryState();
}

class _StateEntryState extends State<_StateEntry> {
  late final name = TextEditingController(text: widget.existing ?? '');
  final value = TextEditingController();
  var scope = 'user', type = 'number';
  String? error;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    value.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      if (widget.credential) {
        await BuilderStore.shared.saveCredential(
          widget.botId,
          name.text.trim(),
          value.text,
        );
      } else {
        final initial = value.text.isEmpty
            ? type == 'number'
                  ? 0
                  : type == 'boolean'
                  ? false
                  : ''
            : value.text;
        final definition = VariableDefinition(
          name.text.trim(),
          scope,
          type,
          initial,
        );
        await BuilderStore.shared.addDefinition(
          widget.botId,
          VariableDefinition(
            definition.name,
            scope,
            type,
            definition.convert(initial),
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is BuilderFailure
              ? e.message
              : context.strings.theValueCouldNotBeSaved,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.credential
          ? context.strings.saveAPICredential
          : context.strings.createVariable,
    ),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              enabled: widget.existing == null,
              decoration: InputDecoration(
                labelText: context.strings.name,
                helperText:
                    context.strings.lettersNumbersAndUnderscoresStartWith,
              ),
            ),
            const SizedBox(height: 12),
            if (!widget.credential) ...[
              DropdownButtonFormField<String>(
                initialValue: scope,
                decoration: InputDecoration(labelText: context.strings.scope),
                items: [
                  DropdownMenuItem(
                    value: 'user',
                    child: Text(context.strings.perUser),
                  ),
                  DropdownMenuItem(
                    value: 'bot',
                    child: Text(context.strings.wholeBot),
                  ),
                ],
                onChanged: (v) => setState(() => scope = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(
                  labelText: context.strings.typeLabel,
                ),
                items: [
                  for (final t in ['number', 'text', 'boolean'])
                    DropdownMenuItem(
                      value: t,
                      child: Text(switch (t) {
                        'number' => context.strings.numberValueType,
                        'text' => context.strings.textValueType,
                        _ => context.strings.booleanValueType,
                      }),
                    ),
                ],
                onChanged: (v) => setState(() => type = v!),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: value,
              obscureText: widget.credential,
              decoration: InputDecoration(
                labelText: widget.credential
                    ? context.strings.apiKey
                    : context.strings.defaultValue,
                helperText: !widget.credential && type == 'boolean'
                    ? context.strings.trueOrFalse
                    : null,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text(context.strings.cancel),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(context.strings.save),
      ),
    ],
  );
}
