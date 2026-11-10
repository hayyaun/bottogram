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
          _error = 'Local bot settings could not be opened.';
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
          title: definition == null ? 'Delete credential?' : 'Delete variable?',
          message: definition == null
              ? 'Actions using this credential will fail until it is replaced.'
              : 'Remove this variable and its saved values for every user of this bot?',
          action: 'Delete',
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
      if (mounted) setState(() => _error = 'The item could not be removed.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Variables and credentials')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_error != null) BNotice(message: _error!, error: true),
              BSection(
                title: 'Variables',
                description:
                    'User values belong to one Telegram user. Bot values are shared by the whole bot. Defaults do not create a record for every user.',
                trailing: TextButton.icon(
                  onPressed: () => _add(false),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
                child: Column(
                  children: [
                    if (_definitions.isEmpty)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('No variables yet'),
                        subtitle: Text(
                          'Create a variable, then use Set variable or Increment variable in an event.',
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
                        subtitle: Text('${d.type} · default: ${d.initial}'),
                        trailing: IconButton(
                          tooltip: 'Delete variable',
                          onPressed: () => _remove(definition: d),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              BSection(
                title: 'API credentials',
                description:
                    'Keys are saved in secure storage on this device. Actions refer to a credential by name.',
                trailing: TextButton.icon(
                  onPressed: () => _add(true),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
                child: Column(
                  children: [
                    if (_credentials.isEmpty)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('No saved credentials'),
                      ),
                    for (final name in _credentials)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.key_outlined),
                        title: Text(name),
                        subtitle: const Text('Value hidden'),
                        onTap: () => _add(true, existing: name),
                        trailing: IconButton(
                          tooltip: 'Delete credential',
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
              : 'The value could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.credential ? 'Save API credential' : 'Create variable'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              enabled: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText:
                    'Letters, numbers and underscores; start with a letter.',
              ),
            ),
            const SizedBox(height: 12),
            if (!widget.credential) ...[
              DropdownButtonFormField<String>(
                initialValue: scope,
                decoration: const InputDecoration(labelText: 'Scope'),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('Per user')),
                  DropdownMenuItem(value: 'bot', child: Text('Whole bot')),
                ],
                onChanged: (v) => setState(() => scope = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in ['number', 'text', 'boolean'])
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => type = v!),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: value,
              obscureText: widget.credential,
              decoration: InputDecoration(
                labelText: widget.credential ? 'API key' : 'Default value',
                helperText: !widget.credential && type == 'boolean'
                    ? 'true or false'
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
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: busy ? null : save, child: const Text('Save')),
    ],
  );
}
