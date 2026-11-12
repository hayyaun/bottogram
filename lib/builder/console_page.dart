import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'console.dart';

class BuilderConsolePage extends StatefulWidget {
  const BuilderConsolePage({
    super.key,
    required this.botId,
    required this.botName,
  });
  final String botId;
  final String botName;
  @override
  State<BuilderConsolePage> createState() => _BuilderConsolePageState();
}

class _BuilderConsolePageState extends State<BuilderConsolePage> {
  var _errorsOnly = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.strings.botConsoleTitle(widget.botName)),
      actions: [
        IconButton(
          tooltip: context.strings.clearConsole,
          onPressed: () => BuilderConsole.shared.clear(widget.botId),
          icon: const Icon(Icons.clear_all),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.strings.thisSessionLatest200EntriesRequest,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilterChip(
                label: Text(context.strings.errors),
                selected: _errorsOnly,
                onSelected: (v) => setState(() => _errorsOnly = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: BuilderConsole.shared,
            builder: (context, _) {
              final entries = BuilderConsole.shared
                  .entries(widget.botId)
                  .where(
                    (e) =>
                        !_errorsOnly || {'error', 'failed'}.contains(e.status),
                  )
                  .toList();
              if (entries.isEmpty) {
                return Center(child: Text(context.strings.runTheBotToSeeIts));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final e = entries[index];
                  final error = {'error', 'failed'}.contains(e.status);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      error
                          ? Icons.error_outline
                          : e.status == 'success'
                          ? Icons.check_circle_outline
                          : Icons.bolt_outlined,
                      color: error ? Theme.of(context).colorScheme.error : null,
                    ),
                    title: SelectableText(e.message),
                    subtitle: Text(
                      '#${e.run} · ${e.event}${e.step.isEmpty ? '' : ' → ${e.step}'} · ${e.status}${e.elapsed == null ? '' : context.strings.consoleElapsed('${e.elapsed!.inMilliseconds}')}\n${e.time.toLocal().toIso8601String().substring(11, 19)}',
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
