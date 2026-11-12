import 'package:bottogram/l10n/strings.dart';
import 'package:bottogram/background/controller.dart';
import 'package:bottogram/background/guide.dart';
import 'package:bottogram/dialogs/share_dialog.dart';
import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/plugins/bot_qr.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/language_preferences.dart';
import 'package:bottogram/ui/theme_preferences.dart';
import 'package:bottogram/updates/app_updates.dart';
import 'package:bottogram/updates/update_notice.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/utils/context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.scrollHeader});
  final Widget? scrollHeader;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static final _githubRepository = Uri.https(
    'github.com',
    '/hayyaun/bottogram',
  );
  static final _githubIssues = Uri.https(
    'github.com',
    '/hayyaun/bottogram/issues',
  );

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
        setState(() => _error = context.strings.theBotConfigurationCouldNotBe);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openGitHubPage(Uri url) async {
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Show the same feedback if the platform cannot open the link.
    }
    if (!opened && mounted) {
      context.showSnackBar(context.strings.githubLinkCouldNotBeOpened);
    }
  }

  Future<void> _chooseInbox(List<VirtBot> bots) async {
    final selected = await showModalBottomSheet<VirtBot>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  context.strings.chooseABot,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: bots.length,
                  itemBuilder: (context, index) => ListTile(
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
    final language = context.watch<LanguagePreferences?>();
    final updates = context.watch<AppUpdates?>();
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
                BHeading(
                  title: context.strings.settings,
                  subtitle: context.strings.yourDeviceLocalDataAndApp,
                ),
                const SizedBox(height: 24),
                if (language != null) ...[
                  BSection(
                    title: context.strings.language,
                    child: BPanel(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in AppLanguage.values)
                            ChoiceChip(
                              label: Text(switch (option) {
                                AppLanguage.system =>
                                  context.strings.deviceLanguage,
                                AppLanguage.english => 'English',
                                AppLanguage.persian => 'فارسی',
                              }),
                              selected: language.language == option,
                              onSelected: language.available && !language.saving
                                  ? (selected) {
                                      if (selected) {
                                        language.setLanguage(option);
                                      }
                                    }
                                  : null,
                            ),
                          if (!language.available)
                            BNotice(
                              message: context.strings.languageUnavailable,
                              error: true,
                            )
                          else if (language.saveFailed)
                            BNotice(
                              message: context.strings.languageSaveFailed,
                              error: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
                if (appearance != null) ...[
                  BSection(
                    title: context.strings.appearance,
                    child: BPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.strings.theme,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.strings.systemFollowsYourDeviceLightAnd,
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
                                    ThemeMode.system => context.strings.system,
                                    ThemeMode.light => context.strings.light,
                                    ThemeMode.dark => context.strings.dark,
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
                            BNotice(
                              message: appearance.available
                                  ? context.strings.themeSaveFailed
                                  : context.strings.themeLoadFailed,
                              error: true,
                            ),
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
                        context.strings.onThisDevice,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
                      if (snapshot.hasError)
                        BNotice(
                          message: context.strings.localStorageCouldNotBeRead,
                          error: true,
                        )
                      else if (!ready)
                        const LinearProgressIndicator()
                      else
                        Wrap(
                          spacing: 32,
                          runSpacing: 16,
                          children: [
                            _metric(context, context.strings.bots, bots.length),
                            _metric(
                              context,
                              context.strings.running,
                              bots.where((bot) => bot.active).length,
                            ),
                            _metric(
                              context,
                              context.strings.plugins,
                              plugins.installed.length,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                BSection(
                  title: context.strings.dataStorage,
                  child: BPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _SettingsRow(
                          icon: Icons.file_download_outlined,
                          title: _importing
                              ? context.strings.importingBots
                              : context.strings.importBots,
                          description: context.strings.restoreABackupFileOrScan,
                          onTap: ready && !_importing ? _import : null,
                        ),
                        const Divider(),
                        _SettingsRow(
                          icon: Icons.ios_share_outlined,
                          title: context.strings.exportBotConfigurations,
                          description:
                              context.strings.chooseManualBotsToShareOr,
                          onTap: ready && !_importing
                              ? () => showDialog<void>(
                                  context: context,
                                  builder: (_) => const ShareDialog(),
                                )
                              : null,
                        ),
                        const Divider(),
                        _SettingsRow(
                          icon: Icons.storage_outlined,
                          title: context.strings.inboxCache,
                          description: bots.isEmpty
                              ? context.strings.addABotToManageIts
                              : context.strings.chooseABotToManageUsers,
                          onTap: ready && bots.isNotEmpty
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
                  title: context.strings.backgroundActivity,
                  child: BPanel(
                    padding: background?.snapshot.supported == true
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(24),
                    child: background?.snapshot.supported == true
                        ? _SettingsRow(
                            icon: Icons.battery_charging_full_outlined,
                            title: context.strings.keepBotsRunning,
                            description: background!.checked
                                ? backgroundRequirement(background)
                                : context
                                      .strings
                                      .checkBatteryBackgroundActivityAndNotification,
                            onTap: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    BackgroundGuide(controller: background),
                              ),
                            ),
                          )
                        : Text(
                            context.strings.keepBottogramRunningAndThisDevice,
                          ),
                  ),
                ),
                const SizedBox(height: 28),
                BSection(
                  title: context.strings.support,
                  child: BPanel(
                    padding: EdgeInsets.zero,
                    child: _SettingsRow(
                      icon: Icons.bug_report_outlined,
                      title: context.strings.reportAProblem,
                      description: context.strings.reportAProblemDescription,
                      trailingIcon: Icons.open_in_new_rounded,
                      onTap: () => _openGitHubPage(_githubIssues),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                BSection(
                  title: context.strings.about,
                  child: BPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        if (updates != null) ...[
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: AppUpdateSettings(updates: updates),
                          ),
                          const Divider(),
                        ],
                        _SettingsRow(
                          icon: Icons.info_outline,
                          title: context.strings.aboutBottogram,
                          description:
                              context.strings.createAndManageTelegramBotsOn,
                          onTap: () => showAboutDialog(
                            context: context,
                            applicationName: 'Bottogram',
                            applicationVersion: updates?.installedVersion,
                            applicationIcon: Image.asset(
                              'assets/icon/foreground.png',
                              width: 40,
                              height: 40,
                            ),
                            children: [
                              Text(
                                context
                                    .strings
                                    .botConfigurationsAndRetainedConversationsAre,
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        _SettingsRow(
                          icon: Icons.description_outlined,
                          title: context.strings.openSourceLicenses,
                          description: context
                              .strings
                              .librariesAndNoticesUsedByBottogram,
                          onTap: () => showLicensePage(
                            context: context,
                            applicationName: 'Bottogram',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () => _openGitHubPage(_githubRepository),
                    style: TextButton.styleFrom(
                      foregroundColor: BColors.of(context).muted,
                      iconColor: BColors.of(context).muted,
                      textStyle: BottogramDesign.text(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.code_rounded, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(context.strings.sourceCodeOnGitHub),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.open_in_new_rounded, size: 12),
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
    this.trailingIcon = Icons.chevron_right,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final IconData trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: onTap != null,
    leading: Icon(icon, size: 22),
    title: Text(title, style: Theme.of(context).textTheme.titleSmall),
    subtitle: Text(description, style: Theme.of(context).textTheme.bodySmall),
    trailing: Icon(trailingIcon, size: 20),
    minLeadingWidth: 24,
    horizontalTitleGap: 12,
    onTap: onTap,
  );
}
