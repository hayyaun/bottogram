import 'dart:async';

import 'package:bottogram/inbox/conversation_page.dart';
import 'package:bottogram/inbox/models.dart';
import 'package:bottogram/inbox/repository.dart';
import 'package:bottogram/inbox/settings_page.dart';
import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';

import 'inbox_repository_test.dart' show message, MemorySource;

/// Widget tests use an in-memory service; disk behavior is covered separately.
class WidgetInbox extends Fake implements InboxRepository {
  final notifications = StreamController<void>.broadcast();
  final known = [
    for (var i = 26; i >= 1; i--)
      KnownUser(id: i, name: 'User $i', lastInteraction: i),
  ];
  final retained = <CachedMessage>[
    CachedMessage.fromTelegram(message(1, 1), outgoing: false),
  ];
  InboxSettings current = const InboxSettings();
  @override
  String? get lastError => null;
  @override
  Stream<void> get changes => notifications.stream;
  @override
  InboxSettings get settings => current;
  @override
  Future<UserPage> users({int page = 0}) async => UserPage(
    known.skip(page * inboxPageSize).take(inboxPageSize).toList(),
    known.length,
    page,
  );
  @override
  Future<List<CachedMessage>> messages(int chatId) async => List.of(retained);
  @override
  Future<InboxUsage> usage() async => InboxUsage(
    cacheBytes: 100,
    directoryBytes: 50,
    limitBytes: settings.limitBytes,
    userCount: known.length,
  );
  @override
  Future<void> clearCache() async {
    retained.clear();
    notifications.add(null);
  }

  @override
  Future<void> setLimit(int limitMiB) async {
    if (limitMiB < 1 || limitMiB > 512) {
      throw const InboxException('Enter a limit from 1 to 512 MiB.');
    }
    current = InboxSettings(limitMiB: limitMiB);
    notifications.add(null);
  }
}

void main() {
  late WidgetInbox repository;
  setUp(() {
    repository = WidgetInbox();
  });
  tearDown(() async {
    await repository.notifications.close();
  });

  void unmountAfter(WidgetTester tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('users paginate and latest interaction appears first', (
    tester,
  ) async {
    unmountAfter(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: InboxUsersPage(
          bot: VirtBot('Test bot', 'not-a-real-token'),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('User 26'), findsOneWidget);
    expect(find.text('Page 1 of 2 · 26 users'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('User 1'), findsOneWidget);
    expect(find.text('Page 2 of 2 · 26 users'), findsOneWidget);
  });

  testWidgets(
    'failed reply preserves draft; success clears it; clearing removes visible history',
    (tester) async {
      unmountAfter(tester);
      var fail = true;
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: InboxConversationPage(
            repository: repository,
            user: repository.known.last,
            source: MemorySource(1),
            send: (text) async {
              if (fail) throw TelegramException(403);
              sent.add(text);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Please contact us');
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('blocked'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Please contact us',
      );
      fail = false;
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pumpAndSettle();
      expect(sent, ['Please contact us']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await repository.clearCache();
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsNothing);
      expect(find.text('No retained messages'), findsOneWidget);
    },
  );

  testWidgets(
    'settings validate limits and require confirmation before clearing',
    (tester) async {
      unmountAfter(tester);
      await tester.pumpWidget(
        MaterialApp(home: InboxSettingsPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.ensureVisible(find.text('Save limit'));
      await tester.tap(find.text('Save limit'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a limit from 1 to 512 MiB.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2');
      await tester.ensureVisible(find.text('Save limit'));
      await tester.tap(find.text('Save limit'));
      await tester.pumpAndSettle();
      expect(repository.settings.limitMiB, 2);
      await tester.ensureVisible(find.text('Clear message cache'));
      await tester.tap(find.text('Clear message cache'));
      await tester.pumpAndSettle();
      expect(find.text('Permanently clear message cache?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.retained.length, 1);
      await tester.tap(find.text('Clear message cache'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear cache'));
      await tester.pumpAndSettle();
      expect(repository.retained, isEmpty);
      expect(repository.known.length, 26);
    },
  );
}
