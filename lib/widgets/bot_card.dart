import 'package:bottogram/l10n/strings.dart';
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
      if (mounted && widget.bot.telegramConnectionIssue == null) {
        context.showSnackBar(
          error is PluginException
              ? error.message
              : context.strings.theBotCouldNotBeStarted2,
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
    final connectionWarning = bot.telegramConnectionIssue != null;
    final status = bot.setupError != null || error != null || connectionWarning
        ? Tooltip(
            message: context.strings.viewBotError,
            child: TextButton(
              onPressed: () => _settings(focusError: true),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                foregroundColor: connectionWarning
                    ? BColors.of(context).warning
                    : BColors.of(context).error,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: BStatus(
                label: connectionWarning
                    ? context.strings.telegramOffline
                    : context.strings.needsAttention,
                icon: connectionWarning ? Icons.cloud_off_outlined : null,
                color: connectionWarning
                    ? BColors.of(context).warning
                    : BColors.of(context).error,
                background: connectionWarning
                    ? BColors.of(context).warningWash
                    : BColors.of(context).errorWash,
              ),
            ),
          )
        : setupOnly
        ? BStatus(
            label: context.strings.setupOnly,
            color: BColors.of(context).warning,
            background: BColors.of(context).warningWash,
          )
        : bot.active
        ? BStatus(
            label: context.strings.active,
            color: BColors.of(context).success,
            background: BColors.of(context).successWash,
          )
        : BStatus(label: context.strings.stopped);
    final compact = widget.compact;
    final theme = Theme.of(context).textTheme;
    final colors = BColors.of(context);
    final icon = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.subtle,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Icon(
        plugin ? Icons.extension_outlined : Icons.smart_toy_outlined,
        size: compact ? 22 : 24,
        color: colors.ink,
      ),
    );
    final title = Tooltip(
      message: bot.name,
      excludeFromSemantics: true,
      child: Text(
        bot.name,
        maxLines: compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: compact ? theme.titleMedium : theme.headlineSmall,
      ),
    );
    final kind = plugin
        ? setup!.pluginName ?? context.strings.pluginBot
        : context.strings.manualBot;
    final summary = context.strings.botEventAndActionCount(
      bot.events.length,
      actions,
    );
    final updateButton = update == null
        ? null
        : Tooltip(
            message: context.strings.reviewPluginVersion(update.version),
            child: TextButton(
              onPressed: () => _settings(focusPluginUpdate: true),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: EdgeInsets.zero,
                alignment: AlignmentDirectional.centerStart,
              ),
              child: Text(context.strings.updateAvailable),
            ),
          );
    final controls = [
      IconButton(
        tooltip: context.strings.botSettings,
        onPressed: _settings,
        icon: Icon(Icons.settings_outlined, size: compact ? 22 : 24),
      ),
      if (compact) const SizedBox(width: 4),
      IconButton.outlined(
        tooltip: setupOnly
            ? context.strings.configurePlugin
            : bot.active
            ? context.strings.stopBot
            : bot.resumeOnLaunch
            ? context.strings.turnOffAutoStart
            : context.strings.startBot,
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
                size: compact ? 22 : 24,
              ),
      ),
    ];

    if (compact) {
      final textScaler = MediaQuery.textScalerOf(context);
      // Fallback fonts can round line heights differently for the same style.
      final headerHeight =
          (textScaler.scale(theme.titleMedium!.fontSize!) +
                  textScaler.scale(theme.bodySmall!.fontSize!)) *
              1.5 +
          4;
      return BPanel(
        onTap: _open,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: headerHeight),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 2),
                        Text(
                          plugin ? kind : summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        status,
                        if (updateButton != null) updateButton,
                      ],
                    ),
                  ),
                ),
                ...controls,
              ],
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
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: status,
                ),
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
                        plugin ? context.strings.openUsersAndInbox : summary,
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
