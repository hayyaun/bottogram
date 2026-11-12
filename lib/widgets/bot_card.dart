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
  const BotCard({super.key, required this.bot, this.compact = false});
  final VirtBot bot;
  final bool compact;
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
    final compact = widget.compact;
    final theme = Theme.of(context).textTheme;
    final colors = BColors.of(context);
    final icon = Container(
      width: compact ? 36 : 44,
      height: compact ? 36 : 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.subtle,
        borderRadius: BorderRadius.all(Radius.circular(compact ? 10 : 12)),
      ),
      child: Icon(
        plugin ? Icons.extension_outlined : Icons.smart_toy_outlined,
        size: compact ? 20 : 24,
        color: colors.ink,
      ),
    );
    final title = Tooltip(
      message: bot.name,
      excludeFromSemantics: true,
      child: Text(
        bot.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: compact ? theme.titleSmall : theme.headlineSmall,
      ),
    );
    final kind = plugin ? setup!.pluginName ?? 'Plugin bot' : 'Manual bot';
    final summary =
        '${bot.events.length} ${bot.events.length == 1 ? 'event' : 'events'} · $actions ${actions == 1 ? 'action' : 'actions'}';
    final updateButton = update == null
        ? null
        : Tooltip(
            message: 'Review version ${update.version}',
            child: TextButton(
              onPressed: () => _settings(focusPluginUpdate: true),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: EdgeInsets.zero,
                alignment: AlignmentDirectional.centerStart,
              ),
              child: const Text('Update available'),
            ),
          );
    final controls = [
      IconButton(
        tooltip: 'Bot settings',
        onPressed: _settings,
        icon: Icon(Icons.settings_outlined, size: compact ? 20 : 24),
      ),
      IconButton.outlined(
        tooltip: setupOnly
            ? 'Configure plugin'
            : bot.active
            ? 'Stop bot'
            : bot.resumeOnLaunch
            ? 'Turn off auto-start'
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
                    : bot.resumeOnLaunch
                    ? Icons.stop_circle_outlined
                    : Icons.play_arrow_rounded,
                size: compact ? 20 : 24,
              ),
      ),
    ];

    if (compact) {
      return BPanel(
        onTap: _open,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          status,
                          Text(
                            plugin ? kind : summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BottogramDesign.text(
                              13,
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ...controls,
              ],
            ),
            if (updateButton != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 46),
                child: updateButton,
              ),
          ],
        ),
      );
    }

    return BPanel(
      onTap: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              icon,
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: status),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: title),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind,
                      style: theme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (updateButton != null)
                      updateButton
                    else ...[
                      const SizedBox(height: 4),
                      Text(
                        plugin ? 'Open users and inbox' : summary,
                        style: BottogramDesign.text(13, color: colors.muted),
                      ),
                    ],
                  ],
                ),
              ),
              ...controls,
            ],
          ),
        ],
      ),
    );
  }
}
