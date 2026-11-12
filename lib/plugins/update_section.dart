import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../store/bots.dart';
import '../ui/design.dart';
import '../units/virt_bot.dart';
import 'capability_review.dart';
import 'manifest.dart';
import 'repository.dart';
import 'upgrade.dart';

class PluginUpdateSection extends StatefulWidget {
  const PluginUpdateSection({
    super.key,
    required this.bot,
    required this.plugin,
  });
  final VirtBot bot;
  final PluginManifest plugin;

  @override
  State<PluginUpdateSection> createState() => _PluginUpdateSectionState();
}

class _PluginUpdateSectionState extends State<PluginUpdateSection> {
  String? _selectedKey;
  String? _error;
  bool _busy = false;

  Future<void> _review(PluginManifest target) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = context.read<PluginRepository>();
    final bots = context.read<BotsCubit>();
    try {
      final plan = await repository.reviewUpgrade(
        widget.bot.key,
        widget.bot.token,
        target,
      );
      if (!mounted) return;
      final active = widget.bot.active;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.strings.updatePluginConfirmation(target.name)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.strings.pluginVersionChange(
                      plan.current.version,
                      plan.target.version,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    active
                        ? context.strings.theBotWillPauseWhileThe
                        : context.strings.theBotWillStayStoppedAfter,
                  ),
                  const SizedBox(height: 12),
                  Text(context.strings.theUpdatedPluginReusesThisBot),
                  if (plan.preservedAutomationIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.strings.pluginProgressRetained(
                        plan.preservedAutomationIds.join(', '),
                      ),
                    ),
                  ],
                  if (plan.removedAutomationIds.isNotEmpty ||
                      plan.replacedAutomationIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.strings.pluginRetiredRoutines(
                        [
                          ...plan.removedAutomationIds,
                          ...plan.replacedAutomationIds,
                        ].join(', '),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(target.description ?? target.name),
                  PluginCapabilityReview(
                    plugin: target,
                    fields: widget.bot.setup!.values,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                active
                    ? context.strings.applyAndRestart
                    : context.strings.applyUpdate,
              ),
            ),
          ],
        ),
      );
      if (accepted == true) await bots.upgradePlugin(widget.bot, target);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PluginException
              ? error.message
              : context.strings.theUpdateCouldNotBePrepared,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = context.watch<PluginRepository>().newerLiveVersions(
      widget.plugin,
    );
    if (candidates.isEmpty && _error == null) {
      return const SizedBox.shrink();
    }
    final selected =
        candidates.where((p) => p.storageKey == _selectedKey).firstOrNull ??
        PluginUpgradePlan.firstCompatibleTarget(
          widget.plugin,
          widget.bot.setup!,
          candidates,
        ) ??
        candidates.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        BPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.strings.pluginUpdates,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (selected != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(selected.storageKey),
                  initialValue: selected.storageKey,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.strings.installedVersion,
                  ),
                  items: [
                    for (final p in candidates)
                      DropdownMenuItem(
                        value: p.storageKey,
                        child: Text(
                          context.strings.versionLabel(p.version),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _selectedKey = value),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _review(selected),
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(
                    _busy
                        ? context.strings.checkingUpdate
                        : context.strings.reviewUpdate,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                BNotice(message: _error!, error: true),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
