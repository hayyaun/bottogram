import 'dart:async';
import 'dart:io';

import 'package:bottogram/inbox/models.dart';
import 'package:bottogram/inbox/repository.dart';
import 'package:bottogram/inbox/transformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:televerse/televerse.dart';

Map<String, dynamic> message(
  int user,
  int id, {
  String text = 'Hello',
  int? date,
  bool photo = false,
  int? size,
}) => {
  'message_id': id,
  'date': date ?? id,
  'chat': {'id': user, 'type': 'private', 'first_name': 'User $user'},
  'from': {'id': user, 'is_bot': false, 'first_name': 'User $user'},
  if (photo)
    'photo': [
      {
        'file_id': 'photo-$id',
        'file_unique_id': 'unique-$id',
        'width': 20,
        'height': 20,
        if (size != null) 'file_size': size,
      },
    ]
  else
    'text': text,
  if (!photo && text.startsWith('/'))
    'entities': [
      {
        'type': 'bot_command',
        'offset': 0,
        'length': text.split(RegExp(r'\s+')).first.length,
      },
    ],
};
Map<String, dynamic> update(
  int user,
  int id, {
  String text = 'Hello',
  bool photo = false,
  int? size,
}) => {
  'update_id': id,
  'message': message(user, id, text: text, photo: photo, size: size),
};

class MemorySource implements AttachmentSource {
  MemorySource(this.bytes, {this.fail = false, this.block = false});
  final int bytes;
  final bool fail;
  final bool block;
  int downloads = 0;
  final started = Completer<void>();
  final released = Completer<void>();
  @override
  Future<RemoteAttachment> locate(InboxAttachment attachment) async =>
      RemoteAttachment(Uri.parse('https://example.invalid/file'), bytes);
  @override
  Future<void> download(
    RemoteAttachment remote,
    File target,
    int maxBytes,
    DownloadCancellation cancellation,
  ) async {
    downloads++;
    await target.writeAsBytes(List.filled(block ? 10 : bytes, 1));
    if (!started.isCompleted) started.complete();
    if (block) {
      cancellation.abort = () {
        if (!released.isCompleted) released.complete();
      };
      await released.future;
      cancellation.check();
    }
    if (fail) throw const SocketException('Interrupted');
  }
}

void main() {
  late Directory root;
  late InboxRepository repository;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bottogram-inbox-test-');
    repository = await InboxRepository.open(root.path, 'testbot');
  });
  tearDown(() async {
    await repository.close();
    await root.delete(recursive: true);
  });

  test(
    'user pages are ordered, bounded, unique, and ignore group chats',
    () async {
      await repository.captureUpdates([
        for (var i = 1; i <= 60; i++) update(i, i),
        {
          'message': {
            ...message(-1, 100),
            'chat': {'id': -1, 'type': 'group', 'title': 'Group'},
          },
        },
      ]);
      final first = await repository.users();
      final second = await repository.users(page: 1);
      final last = await repository.users(page: 2);
      expect(first.total, 60);
      expect(first.users.length, 25);
      expect(first.users.first.id, 60);
      expect(second.users.first.id, 35);
      expect(last.users.length, 10);
      expect(last.hasNext, false);
      expect(
        {
          ...first.users.map((u) => u.id),
          ...second.users.map((u) => u.id),
          ...last.users.map((u) => u.id),
        }.length,
        60,
      );
      expect((await repository.users(page: 999)).page, 2);
    },
  );

  test(
    'deduplicates, applies edits, and keeps only 20 incoming and outgoing messages',
    () async {
      await repository.captureUpdates([
        for (var i = 1; i <= 24; i++) update(1, i),
      ]);
      await repository.captureSent(message(1, 25, text: 'Automatic reply'));
      await repository.captureSent(message(1, 26, text: 'Admin reply'));
      await repository.captureUpdates([
        update(1, 24),
        {
          'edited_message': {
            ...message(1, 24, text: 'Edited'),
            'edit_date': 100,
          },
        },
      ]);
      final messages = await repository.messages(1);
      expect(messages.length, 20);
      expect(messages.first.id, 7);
      expect(messages.last.text, 'Admin reply');
      expect(messages.last.outgoing, true);
      expect(messages.singleWhere((m) => m.id == 24).text, 'Edited');
      expect(messages.singleWhere((m) => m.id == 24).edited, true);
    },
  );

  test(
    'callbacks update the user without copying the bot message as incoming',
    () async {
      await repository.captureUpdates([
        update(1, 1),
        update(2, 2),
        {
          'callback_query': {
            'id': 'callback',
            'from': {'id': 1, 'first_name': 'Updated name'},
            'message': message(1, 50, text: 'An old bot keyboard'),
            'data': 'dice',
          },
        },
      ]);
      expect((await repository.users()).users.first.id, 1);
      expect((await repository.users()).users.first.name, 'Updated name');
      expect((await repository.messages(1)).length, 1);
    },
  );

  test(
    'new storage survives restart and remains isolated between bots',
    () async {
      final other = await InboxRepository.open(root.path, 'otherbot');
      await repository.captureUpdates([update(1, 1)]);
      await repository.setLimit(2);
      expect((await other.users()).total, 0);
      await other.captureUpdates([update(9, 9)]);
      await other.close();
      await repository.close();
      repository = await InboxRepository.open(root.path, 'testbot');
      expect(repository.settings.limitMiB, 2);
      expect((await repository.users()).users.single.id, 1);
      expect((await repository.messages(1)).single.text, 'Hello');
    },
  );

  test(
    'lowering limit evicts messages, compacts disk, and preserves the directory',
    () async {
      final text = 'x' * 4000;
      await repository.captureUpdates([
        for (var i = 1; i <= 350; i++) update((i - 1) ~/ 20 + 1, i, text: text),
      ]);
      final before = await repository.usage();
      expect(before.cacheBytes, greaterThan(mib));
      await repository.setLimit(1);
      final after = await repository.usage();
      expect(after.cacheBytes, lessThanOrEqualTo(mib));
      expect(after.cacheBytes, lessThan(before.cacheBytes));
      expect(after.userCount, before.userCount);
      expect(await repository.messages(1), isEmpty);
      expect((await repository.messages(18)).last.id, 350);
    },
  );

  test(
    'attachments download on demand, reuse files, and evict oldest opened media first',
    () async {
      await repository.setLimit(1);
      await repository.captureUpdates([
        update(1, 1, photo: true, size: 400000),
        update(1, 2, photo: true, size: 400000),
        update(1, 3, photo: true, size: 400000),
      ]);
      final messages = await repository.messages(1);
      final source = MemorySource(400000);
      expect(source.downloads, 0);
      final first = await repository.openAttachment(messages[0], source);
      final second = await repository.openAttachment(messages[1], source);
      await repository.openAttachment(messages[0], source);
      await repository.openAttachment(messages[2], source);
      expect(source.downloads, 3);
      expect(await first.exists(), true);
      expect(await second.exists(), false);
      expect((await repository.messages(1)).length, 3);
      expect((await repository.usage()).cacheBytes, lessThanOrEqualTo(mib));
    },
  );

  test('rejects oversized attachments and cleans partial downloads', () async {
    await repository.setLimit(1);
    await repository.captureUpdates([
      update(1, 1, photo: true, size: 2 * mib),
      update(1, 2, photo: true, size: 21 * mib),
      update(1, 3, photo: true, size: 1000),
    ]);
    final messages = await repository.messages(1);
    final oversized = MemorySource(2 * mib);
    await expectLater(
      repository.openAttachment(messages[0], oversized),
      throwsA(isA<InboxException>()),
    );
    expect(oversized.downloads, 0);
    await expectLater(
      repository.openAttachment(messages[1], oversized),
      throwsA(isA<InboxException>()),
    );
    await expectLater(
      repository.openAttachment(messages[2], MemorySource(1000, fail: true)),
      throwsA(isA<InboxException>()),
    );
    final files = await root.list(recursive: true).toList();
    expect(
      files.whereType<File>().where((f) => f.path.endsWith('.part')),
      isEmpty,
    );
  });

  test(
    'clear cancels an in-flight download and keeps users, settings, and later messages',
    () async {
      await repository.captureUpdates([update(1, 1, photo: true, size: 1000)]);
      await repository.setLimit(2);
      final source = MemorySource(1000, block: true);
      final pending = repository.openAttachment(
        (await repository.messages(1)).single,
        source,
      );
      final failure = expectLater(pending, throwsA(isA<InboxException>()));
      await source.started.future;
      await repository.clearCache();
      await failure;
      expect(await repository.messages(1), isEmpty);
      expect((await repository.users()).total, 1);
      expect(repository.settings.limitMiB, 2);
      await repository.captureUpdates([update(1, 2)]);
      expect((await repository.messages(1)).single.id, 2);
      expect((await repository.usage()).cacheBytes, lessThan(4096));
    },
  );

  test('clear is serialized with message capture', () async {
    final first = repository.captureUpdates([update(1, 1)]);
    final clear = repository.clearCache();
    final later = repository.captureUpdates([update(1, 2)]);
    await Future.wait([first, clear, later]);
    expect((await repository.messages(1)).map((m) => m.id), [2]);
    expect((await repository.users()).total, 1);
  });

  test(
    'transformer captures unmatched updates and never replaces successful responses',
    () async {
      final transformer = InboxTransformer(() async => repository);
      final response = {
        'ok': true,
        'result': [update(1, 1, text: 'No handler matches this')],
      };
      final result = await transformer.transform(
        (method, [payload]) async => response,
        'getUpdates',
      );
      expect(identical(response, result), true);
      expect(
        (await repository.messages(1)).single.text,
        'No handler matches this',
      );
      final sent = {'ok': true, 'result': message(1, 2, text: 'A reply')};
      await transformer.transform(
        (method, [payload]) async => sent,
        'sendMessage',
      );
      expect((await repository.messages(1)).last.outgoing, true);
      await repository.close();
      expect(
        identical(
          await transformer.transform(
            (method, [payload]) async => sent,
            'sendMessage',
          ),
          sent,
        ),
        true,
      );
      expect(repository.lastError, isNotNull);
      // Reopen for tearDown, since this intentionally exercised a failed store.
      repository = await InboxRepository.open(root.path, 'testbot');
    },
  );

  test(
    'validates cache limits and describes actionable reply failures',
    () async {
      expect(repository.settings.limitMiB, 10);
      await expectLater(repository.setLimit(0), throwsA(isA<InboxException>()));
      await expectLater(
        repository.setLimit(513),
        throwsA(isA<InboxException>()),
      );
      expect(replyError(TelegramException(403)), contains('blocked'));
      expect(
        replyError(
          TelegramException.fromJson({
            'error_code': 429,
            'parameters': {'retry_after': 5},
          }),
        ),
        contains('5 seconds'),
      );
      expect(
        replyError(TimeoutException('Timeout')),
        contains('may already have been delivered'),
      );
    },
  );

  test('restart removes orphaned files and interrupted downloads', () async {
    await repository.captureUpdates([update(1, 1)]);
    final media = Directory('${repository.directory.path}/attachments');
    await File('${media.path}/interrupted.part').writeAsBytes([1, 2, 3]);
    await File('${media.path}/orphan.bin').writeAsBytes([1, 2, 3]);
    await repository.close();
    repository = await InboxRepository.open(root.path, 'testbot');
    expect(await media.list().toList(), isEmpty);
    expect((await repository.messages(1)).single.text, 'Hello');
  });
}
