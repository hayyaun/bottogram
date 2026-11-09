import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ShareDialog extends StatefulWidget {
  const ShareDialog({super.key});
  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  final Set<int> _selected = {};
  bool _sharing = false;
  String? _error;
  Future<void> _share() async {
    if (_sharing || _selected.isEmpty) return;
    setState(() {
      _sharing = true;
      _error = null;
    });
    final store = context.read<BotsCubit>();
    final result = await store.share(_selected.toList());
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _sharing = false;
      _error = store.lastError ?? 'The bots could not be shared. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bots = context.read<BotsCubit>().state;
    final exportable = {
      for (final (index, bot) in bots.indexed)
        if (bot.setup?.usesPlugin != true && bot.setupError == null) index,
    };
    return AlertDialog(
      title: const Text('Share bots'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Shared files include Telegram bot tokens. Choose who you share them with.',
              ),
              const SizedBox(height: 16),
              if (bots.isEmpty) const Text('Create a bot before sharing.'),
              for (final (index, bot) in bots.indexed)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(bot.name),
                  value: _selected.contains(index),
                  subtitle:
                      exportable.contains(index)
                          ? null
                          : const Text(
                            'Plugin and incomplete setups cannot be exported.',
                          ),
                  onChanged:
                      _sharing || !exportable.contains(index)
                          ? null
                          : (value) => setState(() {
                            value == true
                                ? _selected.add(index)
                                : _selected.remove(index);
                          }),
                ),
              if (exportable.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        _sharing
                            ? null
                            : () => setState(() {
                              _selected
                                ..clear()
                                ..addAll(exportable);
                            }),
                    icon: const Icon(Icons.select_all),
                    label: const Text('Select all'),
                  ),
                ),
              if (_error != null) BNotice(message: _error!, error: true),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sharing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _sharing || _selected.isEmpty ? null : _share,
          icon: const Icon(Icons.ios_share_outlined, size: 18),
          label: Text(_sharing ? 'Sharing…' : 'Share selected'),
        ),
      ],
    );
  }
}
