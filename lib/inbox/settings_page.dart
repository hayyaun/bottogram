import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';

import 'models.dart';
import 'repository.dart';

String formatInboxBytes(int bytes) =>
    bytes < 1024
        ? '$bytes B'
        : bytes < mib
        ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
        : '${(bytes / mib).toStringAsFixed(2)} MiB';

class InboxSettingsPage extends StatefulWidget {
  const InboxSettingsPage({super.key, required this.repository});
  final InboxRepository repository;
  @override
  State<InboxSettingsPage> createState() => _InboxSettingsPageState();
}

class _InboxSettingsPageState extends State<InboxSettingsPage> {
  late final TextEditingController _limit;
  StreamSubscription<void>? _subscription;
  InboxUsage? _usage;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _limit = TextEditingController(
      text: '${widget.repository.settings.limitMiB}',
    );
    _subscription = widget.repository.changes.listen((_) => _refresh());
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final usage = await widget.repository.usage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'Could not read cache usage. Check free space and try again.',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error =
                  error is InboxException
                      ? error.message
                      : 'Cache storage could not be updated. Check free space and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Permanently clear message cache?'),
            content: const Text(
              'All retained messages and downloaded attachments for this bot will be removed. '
              'Telegram cannot restore these messages. The user list, bot configuration, and cache limit will remain.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear cache'),
              ),
            ],
          ),
    );
    if (confirmed == true && mounted) await _run(widget.repository.clearCache);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inbox settings')),
    body: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: BContent(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BHeading(
              title: 'Storage & cache',
              subtitle:
                  'Control how much conversation history stays on this device.',
            ),
            const SizedBox(height: 28),
            BPanel(
              child: BSection(
                title: 'Message cache',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _usage == null
                          ? 'Reading usage…'
                          : '${formatInboxBytes(_usage!.cacheBytes)} used of ${widget.repository.settings.limitMiB} MiB',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value:
                          _usage == null
                              ? null
                              : (_usage!.cacheBytes /
                                      (widget.repository.settings.limitMiB *
                                          mib))
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _limit,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cache limit (MiB)',
                        helperText: '1–512 MiB per bot · default 10 MiB',
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed:
                          _busy
                              ? null
                              : () => _run(() async {
                                final value = int.tryParse(_limit.text.trim());
                                if (value == null) {
                                  throw const InboxException(
                                    'Enter a whole number from 1 to 512 MiB.',
                                  );
                                }
                                await widget.repository.setLimit(value);
                              }),
                      child: const Text('Save limit'),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Keeps up to 20 recent messages per conversation within the shared budget. Attachments download only when opened. Old attachments are removed first, then old messages. Lowering the limit removes excess cached content immediately.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            BPanel(
              child: BSection(
                title: 'User directory',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'User directory: ${_usage == null ? '…' : formatInboxBytes(_usage!.directoryBytes)} · ${_usage?.userCount ?? 0} known users',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'User IDs, names, last interaction times, and settings are stored separately from the message cache. Brief extra space may be needed when writing or reclaiming storage.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busy ? null : _clear,
              style: OutlinedButton.styleFrom(foregroundColor: BColors.error),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear message cache'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              BNotice(message: _error!, error: true),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}
