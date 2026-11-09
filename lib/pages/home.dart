import 'package:bottogram/dialogs/share_dialog.dart';
import 'package:bottogram/pages/create_bot.dart';
import 'package:bottogram/plugins/plugins_page.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/widgets/bot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  int _page = 0;
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
          color: inverse ? BColors.canvas : BColors.ink,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Scaffold(
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
                      _railItem(0, Icons.smart_toy_outlined, 'Bots'),
                      _railItem(1, Icons.extension_outlined, 'Plugins'),
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
                child: Column(
                  children: [
                    if (!wide)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _brand(),
                        ),
                      ),
                    Expanded(
                      child:
                          _page == 0
                              ? _bots(wide)
                              : PluginsPage(
                                repository: context.read<PluginRepository>(),
                                embedded: true,
                              ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _mobileNavigation() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: BColors.ink.withValues(alpha: .12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: const BorderSide(color: BColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(child: _mobileItem(0, Icons.smart_toy_outlined, 'Bots')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: IconButton.filled(
                  onPressed: _addBot,
                  tooltip: 'Create bot',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    backgroundColor: BColors.ink,
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 28),
                ),
              ),
              Expanded(
                child: _mobileItem(1, Icons.extension_outlined, 'Plugins'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _mobileItem(int index, IconData icon, String label) => Semantics(
    selected: _page == index,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => setState(() => _page = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _page == index ? BColors.subtle : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: _page == index ? BColors.ink : BColors.muted,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: BottogramDesign.text(12, strong: _page == index),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _railItem(int index, IconData icon, String label) => Padding(
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

  Widget _bots(bool wide) => FutureBuilder<void>(
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
            child: LayoutBuilder(
              builder:
                  (context, constraints) => CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BHeading(
                              title: 'Your bots',
                              subtitle:
                                  'Create and manage Telegram bots on this device.',
                              actions: [
                                IconButton(
                                  tooltip: 'Import bots',
                                  onPressed: store.import,
                                  icon: const Icon(
                                    Icons.file_download_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Share bots',
                                  onPressed: _share,
                                  icon: const Icon(Icons.ios_share_outlined),
                                ),
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
                            const SizedBox(height: 24),
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
                                    const SizedBox(height: 12),
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
                              const SizedBox(height: 24),
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
                      else
                        SliverPadding(
                          padding: EdgeInsets.only(bottom: wide ? 24 : 112),
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
                    ],
                  ),
            ),
          );
        },
      );
    },
  );
}
