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
          title: Text('Update ${target.name}?'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Version ${plan.current.version} → ${plan.target.version}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    active
                        ? 'The bot will pause while the update is applied, then start again.'
                        : 'The bot will stay stopped after the update.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The updated plugin reuses this bot’s identity, secure keys and saved preferences.',
                  ),
                  if (plan.preservedAutomationIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Progress retained: ${plan.preservedAutomationIds.join(', ')}. Pending work and acknowledged deliveries are preserved.',
                    ),
                  ],
                  if (plan.removedAutomationIds.isNotEmpty ||
                      plan.replacedAutomationIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Retired or replaced command routines: ${[...plan.removedAutomationIds, ...plan.replacedAutomationIds].join(', ')}. Their queued replies will not be replayed.',
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(active ? 'Apply and restart' : 'Apply update'),
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
              : 'The update could not be prepared. The current version has not changed.',
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
                'Plugin updates',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (selected != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(selected.storageKey),
                  initialValue: selected.storageKey,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Installed version',
                  ),
                  items: [
                    for (final p in candidates)
                      DropdownMenuItem(
                        value: p.storageKey,
                        child: Text(
                          'Version ${p.version}',
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
                  label: Text(_busy ? 'Checking update…' : 'Review update'),
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
