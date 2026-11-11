import 'package:bottogram/pages/bot.dart';
import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/upgrade.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/utils/context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BotCard extends StatefulWidget {
  const BotCard({super.key, required this.bot});
  final VirtBot bot;
  @override
  State<BotCard> createState() => _BotCardState();
}

class _BotCardState extends State<BotCard> {
  bool _busy = false;
  void _open() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => InboxUsersPage(bot: widget.bot)),
  );
  void _settings({bool focusError = false, bool focusPluginUpdate = false}) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BotPage(
            bot: widget.bot,
            focusError: focusError,
            focusPluginUpdate: focusPluginUpdate,
          ),
        ),
      );
  Future<void> _toggle() async {
    if (_busy) return;
    final store = context.read<BotsCubit>();
    setState(() => _busy = true);
    try {
      await store.toggle(widget.bot);
      store.update();
    } catch (error) {
      if (mounted) {
        context.showSnackBar(
          error is PluginException
              ? error.message
              : 'The bot could not be started or stopped. Check its connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bot = widget.bot;
    final setup = bot.setup;
    final plugin = setup?.usesPlugin ?? false;
    final repository = context.watch<PluginRepository>();
    final manifest = repository.manifestFor(setup);
    final setupOnly = plugin && manifest?.executable != true;
    final update = manifest?.executable == true && bot.setupError == null
        ? PluginUpgradePlan.firstCompatibleTarget(
            manifest!,
            setup!,
            repository.newerLiveVersions(manifest),
          )
        : null;
    final error = bot.runtimeError;
    final actions = bot.events.fold<int>(
      0,
      (count, event) => count + event.acts.length,
    );
    final status = bot.setupError != null || error != null
        ? Tooltip(
            message: 'View bot error',
            child: TextButton(
              onPressed: () => _settings(focusError: true),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                foregroundColor: BColors.of(context).error,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: BStatus(
                label: 'Needs attention',
                color: BColors.of(context).error,
                background: BColors.of(context).errorWash,
              ),
            ),
          )
        : setupOnly
        ? BStatus(
            label: 'Setup only',
            color: BColors.of(context).warning,
            background: BColors.of(context).warningWash,
          )
        : bot.active
        ? BStatus(
            label: 'Active',
            color: BColors.of(context).success,
            background: BColors.of(context).successWash,
          )
        : const BStatus(label: 'Stopped');
    return BPanel(
      onTap: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BColors.of(context).subtle,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Icon(
                  plugin ? Icons.extension_outlined : Icons.smart_toy_outlined,
                  size: 24,
                  color: BColors.of(context).ink,
                ),
              ),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: status),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Tooltip(
              message: bot.name,
              excludeFromSemantics: true,
              child: Text(
                bot.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plugin
                          ? bot.setup!.pluginName ?? 'Plugin bot'
                          : 'Manual bot',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (update != null)
                      Tooltip(
                        message: 'Review version ${update.version}',
                        child: TextButton(
                          onPressed: () => _settings(focusPluginUpdate: true),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                          ),
                          child: const Text('Update available'),
                        ),
                      )
                    else ...[
                      const SizedBox(height: 4),
                      Text(
                        plugin
                            ? 'Open users and inbox'
                            : '${bot.events.length} ${bot.events.length == 1 ? 'event' : 'events'} · $actions ${actions == 1 ? 'action' : 'actions'}',
                        style: BottogramDesign.text(
                          13,
                          color: BColors.of(context).muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Bot settings',
                onPressed: _settings,
                icon: const Icon(Icons.settings_outlined),
              ),
              IconButton.outlined(
                tooltip: setupOnly
                    ? 'Configure plugin'
                    : bot.active
                    ? 'Stop bot'
                    : 'Start bot',
                onPressed: _busy
                    ? null
                    : setupOnly
                    ? _settings
                    : _toggle,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        setupOnly
                            ? Icons.tune_rounded
                            : bot.active
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
