import 'dart:ui' show ImageFilter;

import 'package:bottogram/background/controller.dart';
import 'package:bottogram/background/guide.dart';
import 'package:bottogram/dialogs/share_dialog.dart';
import 'package:bottogram/pages/create_bot.dart';
import 'package:bottogram/pages/settings.dart';
import 'package:bottogram/pages/store.dart';
import 'package:bottogram/plugins/bot_qr.dart';
import 'package:bottogram/plugins/plugins_page.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/widgets/bot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum _HomeTab { bots, store, plugins, settings }

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  _HomeTab _page = _HomeTab.bots;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _addBot() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder:
          (_) => CreateBotPage(
            bots: context.read<BotsCubit>(),
            plugins: context.read<PluginRepository>(),
          ),
    ),
  );
  void _share() =>
      showDialog<void>(context: context, builder: (_) => const ShareDialog());

  List<Widget> _botActions() {
    final background = context.watch<BackgroundController?>();
    return [
      if (background != null && background.checked && background.needsGuide)
        IconButton(
          tooltip: backgroundRequirement(background),
          color: BColors.of(context).warning,
          icon: const Icon(Icons.warning_amber_rounded),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => BackgroundGuide(controller: background),
            ),
          ),
        ),
      IconButton(
        tooltip: 'Import bots',
        icon: const Icon(Icons.file_download_outlined),
        onPressed: () => chooseBotImport(context),
      ),
      IconButton(
        tooltip: 'Share bots',
        onPressed: _share,
        icon: const Icon(Icons.ios_share_outlined),
      ),
    ];
  }

  Widget _brand({bool inverse = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/icon/foreground.png',
        width: 32,
        height: 32,
        cacheWidth: 96,
      ),
      const SizedBox(width: 10),
      Text(
        widget.title,
        style: BottogramDesign.text(
          20,
          strong: true,
          color: inverse ? BColors.canvas : BColors.of(context).ink,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final compact = constraints.maxWidth < 600;
      return Scaffold(
        extendBody: !wide,
        bottomNavigationBar: wide ? null : _mobileNavigation(),
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 232,
                  color: BColors.ink,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 32, 20, 40),
                        child: _brand(inverse: true),
                      ),
                      _railItem(
                        _HomeTab.bots,
                        Icons.smart_toy_outlined,
                        'Bots',
                      ),
                      _railItem(
                        _HomeTab.store,
                        Icons.storefront_outlined,
                        'Store',
                      ),
                      _railItem(
                        _HomeTab.plugins,
                        Icons.extension_outlined,
                        'Plugins',
                      ),
                      _railItem(
                        _HomeTab.settings,
                        Icons.settings_outlined,
                        'Settings',
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.devices_outlined,
                              color: BColors.inverseMuted,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'On this device',
                              style: BottogramDesign.text(
                                13,
                                color: BColors.inverseMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: switch (_page) {
                  _HomeTab.bots => _bots(wide, compact: compact),
                  _HomeTab.store => StorePage(
                    scrollHeader: wide ? null : _mobileHeader(compact: compact),
                  ),
                  _HomeTab.plugins => PluginsPage(
                    repository: context.read<PluginRepository>(),
                    embedded: true,
                    scrollHeader: wide ? null : _mobileHeader(compact: compact),
                  ),
                  _HomeTab.settings => SettingsPage(
                    scrollHeader: wide ? null : _mobileHeader(compact: compact),
                  ),
                },
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _mobileHeader({required bool compact}) => Padding(
    padding: EdgeInsets.only(bottom: compact ? 12 : 32),
    child: SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          _brand(),
          if (compact && _page == _HomeTab.bots)
            Row(mainAxisSize: MainAxisSize.min, children: _botActions()),
        ],
      ),
    ),
  );

  Widget _mobileNavigation() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: BColors.of(context).ink.withValues(alpha: .12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              color: BColors.of(context).surface.withValues(alpha: .72),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
                side: BorderSide(color: BColors.of(context).line),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final label = TextPainter(
                      text: TextSpan(
                        text: 'Settings',
                        style: BottogramDesign.text(12, strong: true),
                      ),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout();
                    final showLabels =
                        (constraints.maxWidth - 60) / 4 >= label.width + 8;
                    label.dispose();
                    return Row(
                      children: [
                        Expanded(
                          child: _mobileItem(
                            _HomeTab.bots,
                            Icons.smart_toy_outlined,
                            'Bots',
                            showLabel: showLabels,
                          ),
                        ),
                        Expanded(
                          child: _mobileItem(
                            _HomeTab.store,
                            Icons.storefront_outlined,
                            'Store',
                            showLabel: showLabels,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: IconButton.filled(
                            onPressed: _addBot,
                            tooltip: 'Create bot',
                            style: IconButton.styleFrom(
                              minimumSize: const Size(52, 52),
                              backgroundColor: BColors.of(context).ink,
                              foregroundColor: BColors.of(context).canvas,
                              shape: const CircleBorder(),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 28),
                          ),
                        ),
                        Expanded(
                          child: _mobileItem(
                            _HomeTab.plugins,
                            Icons.extension_outlined,
                            'Plugins',
                            showLabel: showLabels,
                          ),
                        ),
                        Expanded(
                          child: _mobileItem(
                            _HomeTab.settings,
                            Icons.settings_outlined,
                            'Settings',
                            showLabel: showLabels,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _mobileItem(
    _HomeTab index,
    IconData icon,
    String label, {
    required bool showLabel,
  }) => Tooltip(
    message: label,
    child: Semantics(
      label: label,
      button: true,
      selected: _page == index,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => setState(() => _page = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color:
                _page == index
                    ? BColors.of(context).subtle
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color:
                    _page == index
                        ? BColors.of(context).ink
                        : BColors.of(context).muted,
              ),
              if (showLabel) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  style: BottogramDesign.text(12, strong: _page == index),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _railItem(_HomeTab index, IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Material(
      color: _page == index ? const Color(0xFF205D66) : Colors.transparent,
      borderRadius: BottogramDesign.controlRadius,
      child: ListTile(
        selected: _page == index,
        selectedColor: BColors.canvas,
        textColor: BColors.inverseMuted,
        iconColor: BColors.inverseMuted,
        leading: Icon(icon),
        title: Text(label),
        minTileHeight: 56,
        shape: const RoundedRectangleBorder(
          borderRadius: BottogramDesign.controlRadius,
        ),
        onTap: () => setState(() => _page = index),
      ),
    ),
  );

  Widget _bots(bool wide, {required bool compact}) => FutureBuilder<void>(
    future: context.read<BotsCubit>().ready,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const BEmptyState(
          icon: Icons.folder_off_outlined,
          title: 'Bot storage is unavailable',
          message: 'Check free space, then reopen Bottogram.',
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      return BlocBuilder<BotsCubit, List<VirtBot>>(
        builder: (context, allBots) {
          final store = context.read<BotsCubit>();
          final query = _search.text.trim().toLowerCase();
          final bots =
              allBots
                  .where((bot) => bot.name.toLowerCase().contains(query))
                  .toList();
          final search = TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search bots',
              prefixIcon: Icon(Icons.search),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          );
          return BContent(
            padding: EdgeInsets.fromLTRB(
              24,
              wide
                  ? 24
                  : compact
                  ? 8
                  : 16,
              24,
              wide ? 24 : 0,
            ),
            child: LayoutBuilder(
              builder:
                  (context, constraints) => CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!wide) _mobileHeader(compact: compact),
                            BHeading(
                              title: 'Your bots',
                              subtitle:
                                  'Create and manage Telegram bots on this device.',
                              actions: [
                                if (!compact) ..._botActions(),
                                if (wide) ...[
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    onPressed: _addBot,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Create bot'),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: compact ? 16 : 24),
                            if (store.lastError != null) ...[
                              BNotice(
                                message: store.lastError!,
                                error: true,
                                trailing: IconButton(
                                  tooltip: 'Dismiss',
                                  onPressed:
                                      () => setState(
                                        () => store.lastError = null,
                                      ),
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (allBots.isNotEmpty) ...[
                              if (constraints.maxWidth < 500)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${allBots.length} ${allBots.length == 1 ? 'bot' : 'bots'}',
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                    ),
                                    SizedBox(height: compact ? 8 : 12),
                                    search,
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    Text(
                                      '${allBots.length} ${allBots.length == 1 ? 'bot' : 'bots'}',
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                    ),
                                    const Spacer(),
                                    SizedBox(width: 300, child: search),
                                  ],
                                ),
                              SizedBox(height: compact ? 16 : 24),
                            ],
                          ],
                        ),
                      ),
                      if (allBots.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: BEmptyState(
                            icon: Icons.smart_toy_outlined,
                            title: 'Your first bot starts here',
                            message:
                                'Add your Telegram bot token, choose a setup method, and keep everything in one place.',
                          ),
                        )
                      else if (bots.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: BEmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'No matching bots',
                            message:
                                'Try a different name or clear the search.',
                            action: TextButton(
                              onPressed: () => setState(_search.clear),
                              child: const Text('Clear search'),
                            ),
                          ),
                        )
                      else if (compact)
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 24),
                          sliver: SliverList.separated(
                            itemCount: bots.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final bot = bots[index];
                              return BotCard(
                                key: ObjectKey(bot),
                                bot: bot,
                                compact: true,
                              );
                            },
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 24),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount:
                                      constraints.maxWidth < 600
                                          ? 1
                                          : constraints.maxWidth < 1000
                                          ? 2
                                          : 3,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  mainAxisExtent:
                                      248 +
                                      (MediaQuery.textScalerOf(
                                                    context,
                                                  ).scale(16) -
                                                  16)
                                              .clamp(0, 32)
                                              .toDouble() *
                                          10,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (_, index) => BotCard(bot: bots[index]),
                              childCount: bots.length,
                            ),
                          ),
                        ),
                      if (!wide)
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: MediaQuery.paddingOf(context).bottom + 16,
                          ),
                        ),
                    ],
                  ),
            ),
          );
        },
      );
    },
  );
}
