import 'dart:async';

import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';

import 'models.dart';
import 'repository.dart';

String formatInboxBytes(int bytes) => bytes < 1024
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
        setState(() => _error = context.strings.couldNotReadCacheUsageCheck);
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
          () => _error = error is InboxException
              ? error.message
              : context.strings.cacheStorageCouldNotBeUpdated,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.permanentlyClearMessageCache),
        content: Text(
          context.strings.allRetainedMessagesAndDownloadedAttachments,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.strings.clearCache),
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
    appBar: AppBar(title: Text(context.strings.inboxSettings)),
    body: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: BContent(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BHeading(
              title: context.strings.storageCache,
              subtitle: context.strings.controlHowMuchConversationHistoryStays,
            ),
            const SizedBox(height: 28),
            BPanel(
              child: BSection(
                title: context.strings.messageCache,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _usage == null
                          ? context.strings.readingUsage
                          : context.strings.cacheUsage(
                              formatInboxBytes(_usage!.cacheBytes),
                              '${widget.repository.settings.limitMiB}',
                            ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _usage == null
                          ? null
                          : (_usage!.cacheBytes /
                                    (widget.repository.settings.limitMiB * mib))
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
                      decoration: InputDecoration(
                        labelText: context.strings.cacheLimitMiB,
                        helperText: context.strings.label1512MiBPerBotDefault,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final value = int.tryParse(_limit.text.trim());
                              if (value == null) {
                                throw InboxException(
                                  context.strings.enterAWholeNumberFrom1,
                                );
                              }
                              await widget.repository.setLimit(value);
                            }),
                      child: Text(context.strings.saveLimit),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      context.strings.keepsUpTo20RecentMessages,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            BPanel(
              child: BSection(
                title: context.strings.userDirectory,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.strings.userDirectorySummary(
                        _usage == null
                            ? '…'
                            : formatInboxBytes(_usage!.directoryBytes),
                        '${_usage?.userCount ?? 0}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.strings.userIDsNamesLastInteractionTimes,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busy ? null : _clear,
              style: OutlinedButton.styleFrom(
                foregroundColor: BColors.of(context).error,
              ),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(context.strings.clearMessageCache),
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
