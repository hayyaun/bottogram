import 'package:bottogram/background/controller.dart';
import 'package:bottogram/background/guide.dart';
import 'package:bottogram/dialogs/share_dialog.dart';
import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/plugins/bot_qr.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/theme_preferences.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.scrollHeader});
  final Widget? scrollHeader;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Future<void> _ready;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ready = Future.wait([
      context.read<BotsCubit>().ready,
      context.read<PluginRepository>().ready,
    ]).then((_) {});
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    final store = context.read<BotsCubit>();
    try {
      store.lastError = null;
      await chooseBotImport(context);
      if (mounted) setState(() => _error = store.lastError);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The bot configuration could not be imported.');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _chooseInbox(List<VirtBot> bots) async {
    final selected = await showModalBottomSheet<VirtBot>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'Choose a bot',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: bots.length,
                      itemBuilder:
                          (context, index) => ListTile(
                            leading: const Icon(Icons.smart_toy_outlined),
                            title: Text(bots[index].name),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(context, bots[index]),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (selected == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => InboxUsersPage(bot: selected)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bots = context.watch<BotsCubit>().state;
    final plugins = context.watch<PluginRepository>();
    final background = context.watch<BackgroundController?>();
    final appearance = context.watch<ThemePreferences?>();
    return SingleChildScrollView(
      child: BContent(
        maxWidth: 840,
        padding: EdgeInsets.fromLTRB(
          24,
          widget.scrollHeader == null ? 24 : 16,
          24,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: FutureBuilder<void>(
          future: _ready,
          builder: (context, snapshot) {
            final ready =
                snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.scrollHeader != null) widget.scrollHeader!,
                const BHeading(
                  title: 'Settings',
                  subtitle: 'Your device, local data, and app information.',
                ),
                const SizedBox(height: 24),
                if (appearance != null) ...[
                  BSection(
                    title: 'Appearance',
                    child: BPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Theme',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'System follows your device. Light and Dark stay as selected.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final mode in ThemeMode.values)
                                ChoiceChip(
                                  label: Text(switch (mode) {
                                    ThemeMode.system => 'System',
                                    ThemeMode.light => 'Light',
                                    ThemeMode.dark => 'Dark',
                                  }),
                                  selected: appearance.mode == mode,
                                  onSelected:
                                      appearance.available && !appearance.saving
                                          ? (_) => appearance.setMode(mode)
                                          : null,
                                ),
                            ],
                          ),
                          if (appearance.loading || appearance.saving) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
                          if (appearance.error != null) ...[
                            const SizedBox(height: 12),
                            BNotice(message: appearance.error!, error: true),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
                BPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'On this device',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
                      if (snapshot.hasError)
                        const BNotice(
                          message:
                              'Local storage could not be read. Reopen Bottogram to try again.',
                          error: true,
                        )
                      else if (!ready)
                        const LinearProgressIndicator()
                      else
                        Wrap(
                          spacing: 32,
                          runSpacing: 16,
                          children: [
                            _metric(context, 'Bots', bots.length),
                            _metric(
                              context,
                              'Running',
                              bots.where((bot) => bot.active).length,
                            ),
                            _metric(
                              context,
                              'Plugins',
                              plugins.installed.length,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                BSection(
                  title: 'Data & storage',
                  child: BPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _SettingsRow(
                          icon: Icons.file_download_outlined,
                          title:
                              _importing ? 'Importing bots...' : 'Import bots',
                          description:
                              'Restore a backup file or scan a plugin bot QR code.',
                          onTap: ready && !_importing ? _import : null,
                        ),
                        const Divider(),
                        _SettingsRow(
                          icon: Icons.ios_share_outlined,
                          title: 'Export bot configurations',
                          description:
                              'Choose manual bots to share or save. Files include bot tokens.',
                          onTap:
                              ready && !_importing
                                  ? () => showDialog<void>(
                                    context: context,
                                    builder: (_) => const ShareDialog(),
                                  )
                                  : null,
                        ),
                        const Divider(),
                        _SettingsRow(
                          icon: Icons.storage_outlined,
                          title: 'Inbox & cache',
                          description:
                              bots.isEmpty
                                  ? 'Add a bot to manage its messages and cache limits.'
                                  : 'Choose a bot to manage users, messages, and cache limits.',
                          onTap:
                              ready && bots.isNotEmpty
                                  ? () => _chooseInbox(bots)
                                  : null,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  BNotice(message: _error!, error: true),
                ],
                const SizedBox(height: 28),
                BSection(
                  title: 'Background activity',
                  child: BPanel(
                    padding:
                        background?.snapshot.supported == true
                            ? EdgeInsets.zero
                            : const EdgeInsets.all(24),
                    child:
                        background?.snapshot.supported == true
                            ? _SettingsRow(
                              icon: Icons.battery_charging_full_outlined,
                              title: 'Keep bots running',
                              description:
                                  background!.checked
                                      ? backgroundRequirement(background)
                                      : 'Check battery, background activity, and notification permissions.',
                              onTap:
                                  () => Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => BackgroundGuide(
                                            controller: background,
                                          ),
                                    ),
                                  ),
                            )
                            : const Text(
                              'Keep Bottogram running and this device connected to the internet while bots are started. Reopen the app and start bots again after a device restart.',
                            ),
                  ),
                ),
                const SizedBox(height: 28),
                BSection(
                  title: 'About',
                  child: BPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _SettingsRow(
                          icon: Icons.info_outline,
                          title: 'About Bottogram',
                          description:
                              'Create and manage Telegram bots on this device.',
                          onTap:
                              () => showAboutDialog(
                                context: context,
                                applicationName: 'Bottogram',
                                applicationIcon: Image.asset(
                                  'assets/icon/foreground.png',
                                  width: 40,
                                  height: 40,
                                ),
                                children: [
                                  const Text(
                                    'Bot configurations and retained conversations are stored on this device. Plugin credentials use platform secure storage. Configuration exports contain tokens and do not include plugin setups or conversation history.',
                                  ),
                                ],
                              ),
                        ),
                        const Divider(),
                        _SettingsRow(
                          icon: Icons.description_outlined,
                          title: 'Open-source licenses',
                          description:
                              'Libraries and notices used by Bottogram.',
                          onTap:
                              () => showLicensePage(
                                context: context,
                                applicationName: 'Bottogram',
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, int value) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$value', style: Theme.of(context).textTheme.headlineMedium),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: onTap != null,
    leading: Icon(icon, size: 22),
    title: Text(title, style: Theme.of(context).textTheme.titleSmall),
    subtitle: Text(description, style: Theme.of(context).textTheme.bodySmall),
    trailing: const Icon(Icons.chevron_right, size: 20),
    minLeadingWidth: 24,
    horizontalTitleGap: 12,
    onTap: onTap,
  );
}
