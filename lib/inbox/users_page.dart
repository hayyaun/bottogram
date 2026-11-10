import 'dart:async';

import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';
import 'package:intl/intl.dart';

import 'conversation_page.dart';
import 'models.dart';
import 'repository.dart';
import 'settings_page.dart';
import 'diagnostics.dart';

class InboxUsersPage extends StatefulWidget {
  const InboxUsersPage({super.key, required this.bot, this.repository});
  final VirtBot bot;
  final InboxRepository? repository;
  @override
  State<InboxUsersPage> createState() => _InboxUsersPageState();
}

class _InboxUsersPageState extends State<InboxUsersPage> {
  InboxRepository? _repository;
  StreamSubscription<void>? _subscription;
  UserPage? _page;
  int _requestedPage = 0;
  int _request = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final repository = widget.repository ?? await widget.bot.inbox;
      if (!mounted) return;
      _repository = repository;
      _subscription = repository.changes.listen((_) => _load());
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'Could not open the inbox. Check free space and try again.',
        );
      }
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final result = await _repository!.users(page: _requestedPage);
      if (!mounted || request != _request) return;
      setState(() {
        _page = result;
        _requestedPage = result.page;
        _error = null;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not read the user list. Try again.');
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _changePage(int value) {
    _requestedPage = value;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final page = _page;
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Conversations',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Known users, most recent interaction first. Activity is recorded while the bot is running; this is not an online status.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (repository?.lastError != null ||
                  InboxDiagnostics.error != null) ...[
                const SizedBox(height: 12),
                BNotice(
                  message: repository?.lastError ?? InboxDiagnostics.error!,
                  error: true,
                ),
              ],
            ],
          ),
        ),
      ),
      if (_error != null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: BEmptyState(
            icon: Icons.error_outline,
            title: 'Inbox unavailable',
            message: _error!,
            action: TextButton(
              onPressed: repository == null ? _open : _load,
              child: const Text('Retry'),
            ),
          ),
        )
      else if (page == null)
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        )
      else if (page.total == 0)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: BEmptyState(
            icon: Icons.forum_outlined,
            title: 'Your conversations will appear here',
            message:
                'No users observed yet. Start the bot to collect new private conversations.',
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index.isOdd) return const SizedBox(height: 12);
              final user = page.users[index ~/ 2];
              return BPanel(
                key: ValueKey(user.id),
                padding: EdgeInsets.zero,
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder:
                            (_) => InboxConversationPage(
                              repository: repository!,
                              user: user,
                              send:
                                  (text) => repository.sendReply(
                                    widget.bot.bot.api,
                                    user.id,
                                    text,
                                  ),
                              source: TelegramAttachmentSource(
                                () => widget.bot.bot.api,
                                widget.bot.token,
                              ),
                            ),
                      ),
                    ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: BColors.of(context).subtle,
                    foregroundColor: BColors.of(context).ink,
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(
                    user.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      user.username == null
                          ? '${user.id}'
                          : '@${user.username} · ${user.id}',
                      DateFormat.yMd().add_Hm().format(
                        DateTime.fromMillisecondsSinceEpoch(
                          user.lastInteraction * 1000,
                        ),
                      ),
                    ].join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              );
            }, childCount: page.users.length * 2 - 1),
          ),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.bot.name} · Users',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (repository != null)
            IconButton(
              tooltip: 'Inbox settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => InboxSettingsPage(repository: repository),
                    ),
                  ),
            ),
        ],
      ),
      body: BContent(
        maxWidth: 960,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: repository == null ? _open : _load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: slivers,
                ),
              ),
            ),
            if (page != null && page.total > 0)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed:
                            page.page == 0
                                ? null
                                : () => _changePage(page.page - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          'Page ${page.page + 1} of ${(page.total + inboxPageSize - 1) ~/ inboxPageSize} · ${page.total} users',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed:
                            !page.hasNext
                                ? null
                                : () => _changePage(page.page + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
