import 'package:bottogram/l10n/strings.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/plugins_page.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/setup_fields.dart';
import 'package:bottogram/store/bots.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';

class CreateBotPage extends StatefulWidget {
  const CreateBotPage({super.key, required this.bots, required this.plugins});
  final BotsCubit bots;
  final PluginRepository plugins;
  @override
  State<CreateBotPage> createState() => _CreateBotPageState();
}

class _CreateBotPageState extends State<CreateBotPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _token = TextEditingController();
  final _admin = TextEditingController();
  final _parameters = <String, TextEditingController>{};
  PluginManifest? _plugin;
  bool _saving = false;
  String? _error;
  late final Future<void> _ready = widget.plugins.ready;

  @override
  void initState() {
    super.initState();
    widget.plugins.addListener(_catalogChanged);
  }

  void _catalogChanged() {
    if (_plugin != null &&
        !widget.plugins.installed.any(
          (p) => p.storageKey == _plugin!.storageKey,
        )) {
      _select(null);
    }
  }

  @override
  void dispose() {
    widget.plugins.removeListener(_catalogChanged);
    for (final ctrl in [_name, _token, _admin, ..._parameters.values]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _select(String? key) {
    for (final ctrl in _parameters.values) {
      ctrl.dispose();
    }
    _parameters.clear();
    _plugin = key == null
        ? null
        : widget.plugins.installed.firstWhere((p) => p.storageKey == key);
    for (final field in _plugin?.fields ?? <PluginField>[]) {
      _parameters[field.key] = TextEditingController(
        text: field.defaultValue ?? '',
      );
    }
    setState(() => _error = null);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.bots.create(
        name: _name.text.trim(),
        token: _token.text.trim(),
        adminIds: _admin.text.trim(),
        plugin: _plugin,
        parameters: _parameters.map((key, ctrl) => MapEntry(key, ctrl.text)),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PluginException
              ? error.message
              : context.strings.theBotCouldNotBeSaved,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.strings.createBot)),
    body: FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return BEmptyState(
            icon: Icons.folder_off_outlined,
            title: context.strings.settingsUnavailable,
            message: context.strings.botSettingsStorageCouldNotBe,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: BContent(
            maxWidth: 760,
            child: Form(
              key: _form,
              child: AbsorbPointer(
                absorbing: _saving,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BHeading(
                      title: context.strings.botSetup,
                      subtitle:
                          context.strings.connectYourTelegramBotThenChoose,
                    ),
                    const SizedBox(height: 32),
                    BPanel(
                      child: BSection(
                        title: context.strings.telegramDetails,
                        description:
                            context.strings.theseDetailsBelongToEveryBot,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _name,
                              maxLength: 100,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: context.strings.botName,
                                hintText: context.strings.aNameYouWillRecognize,
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? context.strings.enterABotName
                                  : null,
                            ),
                            _SetupHelp(
                              label:
                                  context.strings.helpWithTheTelegramBotToken,
                              title: context.strings.getATelegramBotToken,
                              description: context
                                  .strings
                                  .openBotFatherInTelegramAndSend,
                              illustration:
                                  'assets/help/telegram_bot_token.png',
                              illustrationLabel:
                                  context.strings.botfatherSFinalReplyWithThe,
                            ),
                            SecretFormField(
                              controller: _token,
                              label: context.strings.telegramBotToken,
                              secret: true,
                              helpText:
                                  context.strings.createABotWithBotFatherIn,
                              validator: (value) =>
                                  RegExp(
                                    r'^[0-9]+:[A-Za-z0-9_-]+$',
                                  ).hasMatch(value?.trim() ?? '')
                                  ? null
                                  : context
                                        .strings
                                        .enterTheTelegramBotTokenFrom,
                            ),
                            _SetupHelp(
                              label: context.strings.helpWithAdminIDs,
                              title: context.strings.findYourTelegramUserID,
                              description: context
                                  .strings
                                  .openUserinfobotFromTheTelegramAccount,
                              illustration: 'assets/help/telegram_admin_id.png',
                              illustrationLabel: context
                                  .strings
                                  .exampleReplyShowingANumericTelegram,
                            ),
                            AdminIdsField(controller: _admin),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    BPanel(
                      child: BSection(
                        title: context.strings.setupMethod,
                        description: context.strings.buildYourOwnActionsOrUse,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListenableBuilder(
                              listenable: widget.plugins,
                              builder: (context, _) =>
                                  DropdownButtonFormField<String>(
                                    key: ValueKey(
                                      _plugin?.storageKey ?? 'manual',
                                    ),
                                    initialValue:
                                        _plugin?.storageKey ?? 'manual',
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: context.strings.setupMethod,
                                      prefixIcon: Icon(Icons.tune_rounded),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'manual',
                                        child: Text(context.strings.manual),
                                      ),
                                      for (final plugin
                                          in widget.plugins.installed)
                                        DropdownMenuItem(
                                          value: plugin.storageKey,
                                          child: Text(
                                            '${plugin.name} · ${plugin.version}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (key) =>
                                        _select(key == 'manual' ? null : key),
                                  ),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                icon: const Icon(
                                  Icons.extension_outlined,
                                  size: 18,
                                ),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => PluginsPage(
                                        repository: widget.plugins,
                                      ),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                                label: Text(context.strings.managePlugins),
                              ),
                            ),
                            if (_plugin != null) ...[
                              const Divider(),
                              const SizedBox(height: 24),
                              PluginSetupFields(
                                plugin: _plugin!,
                                controllers: _parameters,
                              ),
                              BNotice(
                                icon: Icons.lock_outline_rounded,
                                message: _plugin!.executable
                                    ? context
                                          .strings
                                          .credentialsAreSavedSecurelyStartThe
                                    : context
                                          .strings
                                          .settingsWillBeSavedSecurelyThis,
                              ),
                            ] else
                              Text(
                                context
                                    .strings
                                    .addEventsRepliesAndKeyboardsAfter,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      BNotice(message: _error!, error: true),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text(
                        _saving
                            ? context.strings.saving
                            : context.strings.createBot,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _SetupHelp extends StatelessWidget {
  const _SetupHelp({
    required this.label,
    required this.title,
    required this.description,
    required this.illustration,
    required this.illustrationLabel,
  });

  final String label;
  final String title;
  final String description;
  final String illustration;
  final String illustrationLabel;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: IconButton(
      tooltip: label,
      color: BColors.of(context).muted,
      icon: const Icon(Icons.help_outline_rounded, size: 18),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          scrollable: true,
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(description),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BottogramDesign.controlRadius,
                  child: Image.asset(
                    illustration,
                    fit: BoxFit.contain,
                    semanticLabel: illustrationLabel,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.strings.done),
            ),
          ],
        ),
      ),
    ),
  );
}
