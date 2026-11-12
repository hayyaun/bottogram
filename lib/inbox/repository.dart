import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:televerse/televerse.dart';

import 'models.dart';
import 'diagnostics.dart';

class DownloadCancellation {
  bool cancelled = false;
  void Function()? abort;
  void check() {
    if (cancelled) throw const InboxException('Attachment download cancelled.');
  }

  void cancel() {
    cancelled = true;
    abort?.call();
  }
}

class RemoteAttachment {
  const RemoteAttachment(this.uri, this.size);
  final Uri uri;
  final int? size;
}

abstract interface class AttachmentSource {
  Future<RemoteAttachment> locate(InboxAttachment attachment);
  Future<void> download(
    RemoteAttachment remote,
    io.File target,
    int maxBytes,
    DownloadCancellation cancellation,
  );
}

class TelegramAttachmentSource implements AttachmentSource {
  TelegramAttachmentSource(this.api, this.token);
  final RawAPI Function() api;
  final String token;

  @override
  Future<RemoteAttachment> locate(InboxAttachment attachment) async {
    final file = await api().getFile(attachment.fileId);
    if (file.filePath == null) {
      throw const InboxException('Telegram could not provide this attachment.');
    }
    return RemoteAttachment(
      Uri.https('api.telegram.org', '/file/bot$token/${file.filePath}'),
      file.fileSize ?? attachment.size,
    );
  }

  @override
  Future<void> download(
    RemoteAttachment remote,
    io.File target,
    int maxBytes,
    DownloadCancellation cancellation,
  ) async {
    final client =
        io.HttpClient()..connectionTimeout = const Duration(seconds: 30);
    cancellation.abort = () => client.close(force: true);
    io.IOSink? sink;
    try {
      cancellation.check();
      final request = await client.getUrl(remote.uri);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw const InboxException(
          'Attachment download failed. Try opening it again.',
        );
      }
      if (response.contentLength > maxBytes) {
        throw const InboxException(
          'Attachment exceeds the available cache budget.',
        );
      }
      sink = target.openWrite();
      var bytes = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        cancellation.check();
        bytes += chunk.length;
        if (bytes > maxBytes) {
          throw const InboxException(
            'Attachment exceeds the available cache budget.',
          );
        }
        sink.add(chunk);
        // Bound the sink's queued buffers as well as the download size.
        await sink.flush();
      }
      cancellation.check();
      if (remote.size != null && bytes != remote.size) {
        throw const InboxException(
          'Attachment download was incomplete. Try again.',
        );
      }
    } finally {
      await sink?.close();
      cancellation.abort = null;
      client.close(force: true);
    }
  }
}

class InboxRepository {
  InboxRepository._(this.directory, this.namespace);
  final io.Directory directory;
  final String namespace;
  static final Map<String, Future<InboxRepository>> _repositories = {};
  static Future<Box<String>>? _registry;
  static const telegramDownloadLimit = 20 * mib;

  static Future<InboxRepository> forToken(String token) =>
      _repositories.putIfAbsent(
        token,
        () => _openToken(token).onError((Object error, StackTrace stack) {
          _repositories.remove(token);
          _registry = null;
          Error.throwWithStackTrace(error, stack);
        }),
      );

  static Future<InboxRepository> _openToken(String token) async {
    final root = io.Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'inbox'),
    );
    await root.create(recursive: true);
    final registry =
        await (_registry ??= Hive.openBox<String>(
          'inbox_registry',
          path: root.path,
        ));
    var namespace = registry.get(token);
    if (namespace == null) {
      final random = Random.secure();
      namespace =
          'b${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 32)}';
      await registry.put(token, namespace);
    }
    return open(root.path, namespace);
  }

  /// Separate new boxes: existing bot adapters and exports are unaffected.
  static Future<InboxRepository> open(String root, String namespace) async {
    final opened = <BoxBase<dynamic>>[];
    Future<T> track<T extends BoxBase<dynamic>>(Future<T> future) async {
      final box = await future;
      opened.add(box);
      return box;
    }

    try {
      final repository = InboxRepository._(
        io.Directory(p.join(root, namespace)),
        namespace,
      );
      await repository.directory.create(recursive: true);
      final path = repository.directory.path;
      repository._users = await track(
        Hive.openLazyBox<String>('${namespace}_users', path: path),
      );
      repository._activity = await track(
        Hive.openLazyBox<int>('${namespace}_activity', path: path),
      );
      repository._messages = await track(
        Hive.openLazyBox<String>('${namespace}_messages', path: path),
      );
      repository._chats = await track(
        Hive.openLazyBox<String>('${namespace}_chats', path: path),
      );
      repository._order = await track(
        Hive.openBox<String>('${namespace}_order', path: path),
      );
      repository._media = await track(
        Hive.openBox<String>('${namespace}_media', path: path),
      );
      repository._settings = await track(
        Hive.openBox<int>('${namespace}_settings', path: path),
      );
      await repository._mediaDirectory.create(recursive: true);
      if (repository._settings.get('dirty', defaultValue: 0) == 1) {
        await repository._repairIndexes();
        await repository._settings.put('dirty', 0);
      }
      await repository._cleanOrphanMedia();
      await repository._enforceLimit();
      return repository;
    } catch (_) {
      for (final box in opened.reversed) {
        await box.close();
      }
      rethrow;
    }
  }

  late final LazyBox<String> _users;
  late final LazyBox<int> _activity;
  late final LazyBox<String> _messages;
  late final LazyBox<String> _chats;
  late final Box<String> _order;
  late final Box<String> _media;
  late final Box<int> _settings;
  final _changes = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  Future<void> _tail = Future.value();
  final Map<String, DownloadCancellation> _cancellations = {};
  final Map<String, Future<io.File>> _downloads = {};
  final Map<String, int> _reservations = {};
  int _generation = 0;
  String? lastError;
  Stream<void> get changes => _changes.stream;
  Stream<String> get errors => _errors.stream;
  int get generation => _generation;
  InboxSettings get settings =>
      InboxSettings(limitMiB: _settings.get('limitMiB', defaultValue: 10)!);
  io.Directory get _mediaDirectory =>
      io.Directory(p.join(directory.path, 'attachments'));
  List<BoxBase<dynamic>> get _cacheBoxes => [_messages, _chats, _order, _media];
  List<BoxBase<dynamic>> get _directoryBoxes => [_users, _activity, _settings];

  Future<T> _serial<T>(Future<T> Function() action) {
    final future = _tail.then((_) => action());
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future;
  }

  void reportCacheFailure() {
    lastError =
        'Inbox storage failed. Some recent messages may not have been saved. '
        'Check free space and inbox settings.';
    InboxDiagnostics.notice.value = InboxStorageProblem.writeFailed;
    if (!_errors.isClosed) _errors.add(lastError!);
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<UserPage> users({int page = 0}) => _serial(() async {
    final total = _activity.length;
    final lastPage = total == 0 ? 0 : (total - 1) ~/ inboxPageSize;
    final current = page.clamp(0, lastPage);
    final result = <KnownUser>[];
    for (
      var offset = current * inboxPageSize;
      offset < min(total, (current + 1) * inboxPageSize);
      offset++
    ) {
      final id = await _activity.getAt(total - 1 - offset);
      final value = id == null ? null : await _users.get(id);
      if (value != null) result.add(KnownUser.decode(value));
    }
    return UserPage(result, total, current);
  });

  Future<List<CachedMessage>> messages(int chatId) => _serial(() async {
    final keys = _chatKeys(await _chats.get(chatId));
    final result = <CachedMessage>[];
    for (final key in keys) {
      final value = await _messages.get(key);
      if (value != null) result.add(CachedMessage.decode(value));
    }
    return result;
  });

  List<String> _chatKeys(String? value) =>
      value == null ? [] : (jsonDecode(value) as List).cast<String>();

  Future<void> captureUpdates(List<dynamic> updates) => _serial(() async {
    await _settings.put('dirty', 1);
    for (final raw in updates) {
      final update = Map<String, dynamic>.from(raw as Map);
      final message = update['message'] ?? update['edited_message'];
      if (message is Map && (message['chat'] as Map?)?['type'] == 'private') {
        final json = Map<String, dynamic>.from(message);
        final identity = (json['from'] as Map?) ?? (json['chat'] as Map);
        await _rememberUser(
          (json['chat'] as Map)['id'] as int,
          identity,
          json['date'] as int,
        );
        await _storeMessage(CachedMessage.fromTelegram(json, outgoing: false));
      }
      final callback = update['callback_query'];
      if (callback is Map && callback['message'] is Map) {
        final chat = (callback['message'] as Map)['chat'] as Map?;
        final from = callback['from'] as Map?;
        if (chat?['type'] == 'private' &&
            from != null &&
            chat?['id'] == from['id']) {
          await _rememberUser(
            chat!['id'] as int,
            from,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }
      }
    }
    await _enforceLimit();
    await _settings.put('dirty', 0);
    _notify();
  });

  Future<void> captureSent(Map<String, dynamic> json) => _serial(() async {
    if ((json['chat'] as Map?)?['type'] != 'private') return;
    await _settings.put('dirty', 1);
    await _storeMessage(CachedMessage.fromTelegram(json, outgoing: true));
    await _enforceLimit();
    await _settings.put('dirty', 0);
    _notify();
  });

  Future<void> _rememberUser(int id, Map identity, int date) async {
    final oldValue = await _users.get(id);
    final old = oldValue == null ? null : KnownUser.decode(oldValue);
    final name = [
      identity['first_name'],
      identity['last_name'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final user = KnownUser(
      id: id,
      name: name.isEmpty ? 'User $id' : name,
      username: identity['username'] as String?,
      lastInteraction: max(date, old?.lastInteraction ?? 0),
    );
    // Write the source record first. Indexes can be rebuilt after interrupted writes.
    await _users.put(id, user.encode());
    await _activity.put(user.activityKey, id);
    if (old != null && old.activityKey != user.activityKey) {
      await _activity.delete(old.activityKey);
    }
  }

  Future<void> _storeMessage(CachedMessage message) async {
    final previous = await _messages.get(message.key);
    if (previous == message.encode()) return;
    if (previous != null) {
      final old = CachedMessage.decode(previous);
      if (old.orderKey != message.orderKey) await _order.delete(old.orderKey);
      if (old.attachment?.fileId != message.attachment?.fileId) {
        await _deleteMedia(message.key);
      }
    }
    await _messages.put(message.key, message.encode());
    await _order.put(message.orderKey, message.key);
    final keys = _chatKeys(await _chats.get(message.chatId));
    keys.remove(message.key);
    keys.add(message.key);
    // Telegram message IDs increase within a private chat, including our replies.
    keys.sort(
      (a, b) =>
          int.parse(a.split('_').last).compareTo(int.parse(b.split('_').last)),
    );
    await _chats.put(message.chatId, jsonEncode(keys));
    while (keys.length > conversationLimit) {
      await _deleteMessage(keys.removeAt(0));
    }
  }

  Future<void> _deleteMessage(String key) async {
    final value = await _messages.get(key);
    if (value == null) return;
    final message = CachedMessage.decode(value);
    await _messages.delete(key);
    await _order.delete(message.orderKey);
    final keys = _chatKeys(await _chats.get(message.chatId))..remove(key);
    if (keys.isEmpty) {
      await _chats.delete(message.chatId);
    } else {
      await _chats.put(message.chatId, jsonEncode(keys));
    }
    _cancellations[key]?.cancel();
    await _deleteMedia(key);
  }

  Future<void> _deleteMedia(String key) async {
    final raw = _media.get(key);
    if (raw == null) return;
    final file = io.File(
      p.join(_mediaDirectory.path, (jsonDecode(raw) as Map)['name'] as String),
    );
    if (await file.exists()) await file.delete();
    await _media.delete(key);
  }

  Future<int> _boxBytes(Iterable<BoxBase<dynamic>> boxes) async {
    var bytes = 0;
    for (final box in boxes) {
      await box.flush();
      if (box.path != null) {
        final file = io.File(box.path!);
        if (await file.exists()) bytes += await file.length();
      }
    }
    return bytes;
  }

  Future<int> _cacheBytes({bool includePartial = false}) async {
    var bytes = await _boxBytes(_cacheBoxes);
    await for (final file in _mediaDirectory.list()) {
      if (file is io.File && (includePartial || !file.path.endsWith('.part'))) {
        bytes += await file.length();
      }
    }
    return bytes;
  }

  Future<InboxUsage> usage() => _serial(
    () async => InboxUsage(
      cacheBytes: await _cacheBytes(includePartial: true),
      directoryBytes: await _boxBytes(_directoryBoxes),
      limitBytes: settings.limitBytes,
      userCount: _users.length,
    ),
  );

  Future<void> _compact() async {
    for (final box in _cacheBoxes) {
      await box.compact();
    }
  }

  Future<void> _enforceLimit({int reserve = 0}) async {
    final target =
        settings.limitBytes -
        _reservations.values.fold(0, (a, b) => a + b) -
        reserve;
    if (target < 0) {
      throw const InboxException('Not enough cache space for this attachment.');
    }
    if (await _cacheBytes() <= target) return;
    final alreadyDirty = _settings.get('dirty', defaultValue: 0) == 1;
    await _settings.put('dirty', 1);
    await _compact();
    var currentBytes = await _cacheBytes();
    while (currentBytes > target) {
      if (_media.isNotEmpty) {
        String? oldestKey;
        var oldestTime = 1 << 62;
        for (final key in _media.keys.cast<String>()) {
          final opened = (jsonDecode(_media.get(key)!) as Map)['opened'] as int;
          if (opened < oldestTime) {
            oldestTime = opened;
            oldestKey = key;
          }
        }
        await _deleteMedia(oldestKey!);
      } else if (_order.isNotEmpty) {
        // Scale the batch to the excess space. Shrinking a large cache must not
        // rewrite the whole file once for every small group of deleted messages.
        final batch = min(
          _order.length,
          max(
            1,
            (_order.length * (currentBytes - target) / currentBytes).ceil(),
          ),
        );
        for (var i = 0; i < batch && _order.isNotEmpty; i++) {
          final orderKey = _order.keyAt(0);
          final key = _order.get(orderKey)!;
          if (_messages.containsKey(key)) {
            await _deleteMessage(key);
          } else {
            await _order.delete(orderKey);
          }
        }
      } else {
        throw const InboxException(
          'Not enough cache space. Increase the cache limit.',
        );
      }
      await _compact();
      currentBytes = await _cacheBytes();
    }
    if (!alreadyDirty) await _settings.put('dirty', 0);
  }

  Future<void> setLimit(int limitMiB) async {
    if (limitMiB < 1 || limitMiB > 512) {
      throw const InboxException('Enter a limit from 1 to 512 MiB.');
    }
    _cancelDownloads();
    await _serial(() async {
      await _settings.put('dirty', 1);
      await _settings.put('limitMiB', limitMiB);
      await _enforceLimit();
      await _settings.put('dirty', 0);
      _notify();
    });
  }

  void _cancelDownloads() {
    _generation++;
    for (final cancellation in _cancellations.values) {
      cancellation.cancel();
    }
    _reservations.clear();
  }

  Future<void> clearCache() async {
    _cancelDownloads();
    await _serial(() async {
      await _settings.put('dirty', 1);
      for (final box in _cacheBoxes) {
        await box.clear();
      }
      await for (final file in _mediaDirectory.list()) {
        if (file is io.File && !file.path.endsWith('.part')) {
          await file.delete();
        }
      }
      lastError = null;
      InboxDiagnostics.notice.value = null;
      await _settings.put('dirty', 0);
      _notify();
    });
  }

  Future<io.File> openAttachment(
    CachedMessage message,
    AttachmentSource source,
  ) => _downloads.putIfAbsent(
    message.key,
    () => _downloadAttachment(message, source).whenComplete(() {
      _downloads.remove(message.key);
    }),
  );

  Future<io.File> _downloadAttachment(
    CachedMessage message,
    AttachmentSource source,
  ) async {
    final attachment = message.attachment;
    if (attachment == null) {
      throw const InboxException('This message has no attachment.');
    }
    if ((attachment.size ?? 0) > telegramDownloadLimit) {
      throw const InboxException('Telegram allows bot downloads up to 20 MiB.');
    }
    final cancellation = DownloadCancellation();
    _cancellations[message.key] = cancellation;
    io.File? partial;
    try {
      final cached = await _serial(() async {
        cancellation.check();
        if (!_messages.containsKey(message.key)) {
          throw const InboxException('This message is no longer cached.');
        }
        final raw = _media.get(message.key);
        if (raw == null) return null;
        final entry = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final file = io.File(
          p.join(_mediaDirectory.path, entry['name'] as String),
        );
        if (!await file.exists()) {
          await _media.delete(message.key);
          return null;
        }
        entry['opened'] = DateTime.now().microsecondsSinceEpoch;
        await _media.put(message.key, jsonEncode(entry));
        await _enforceLimit();
        return await file.exists() ? file : null;
      });
      if (cached != null) return cached;
      final remote = await source.locate(attachment);
      cancellation.check();
      final size = remote.size ?? attachment.size;
      if ((size ?? 0) > telegramDownloadLimit) {
        throw const InboxException(
          'Telegram allows bot downloads up to 20 MiB.',
        );
      }
      if ((size ?? 0) + 4096 > settings.limitBytes) {
        throw const InboxException(
          'Attachment exceeds this bot’s cache limit. Increase the limit in settings.',
        );
      }
      final allowance = await _serial(() async {
        cancellation.check();
        final reserve =
            size == null
                ? min(
                  telegramDownloadLimit,
                  max(
                    0,
                    settings.limitBytes -
                        await _cacheBytes() -
                        4096 -
                        _reservations.values.fold<int>(0, (a, b) => a + b),
                  ),
                )
                : size + 4096;
        if (reserve <= 0) {
          throw const InboxException(
            'Not enough cache space for this attachment.',
          );
        }
        await _enforceLimit(reserve: reserve);
        cancellation.check();
        _reservations[message.key] = reserve;
        return size ?? reserve;
      });
      final extension = p.extension(attachment.name).toLowerCase();
      final safeExtension =
          RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension)
              ? extension
              : '.bin';
      final name = '${message.key}$safeExtension';
      partial = io.File(p.join(_mediaDirectory.path, '$name.part'));
      await source.download(remote, partial, allowance, cancellation);
      cancellation.check();
      if (await partial.length() > allowance) {
        throw const InboxException(
          'Attachment exceeds the available cache budget.',
        );
      }
      return await _serial(() async {
        cancellation.check();
        if (!_messages.containsKey(message.key)) {
          throw const InboxException('This message is no longer cached.');
        }
        final file = await partial!.rename(p.join(_mediaDirectory.path, name));
        await _media.put(
          message.key,
          jsonEncode({
            'name': name,
            'opened': DateTime.now().microsecondsSinceEpoch,
          }),
        );
        _reservations.remove(message.key);
        await _enforceLimit();
        if (!await file.exists()) {
          throw const InboxException('Attachment no longer fits in the cache.');
        }
        _notify();
        return file;
      });
    } on InboxException {
      rethrow;
    } catch (_) {
      throw const InboxException(
        'Attachment could not be downloaded. Check your connection and try again.',
      );
    } finally {
      if (partial != null && await partial.exists()) await partial.delete();
      _reservations.remove(message.key);
      _cancellations.remove(message.key);
    }
  }

  /// Recover derived indexes after a process dies between Hive writes. Values
  /// are read one at a time; conversation bodies never accumulate in memory.
  Future<void> _repairIndexes() async {
    await _activity.clear();
    for (final key in _users.keys) {
      final user = KnownUser.decode((await _users.get(key))!);
      await _activity.put(user.activityKey, user.id);
    }
    await _order.clear();
    await _chats.clear();
    for (final key in _messages.keys.toList()) {
      final message = CachedMessage.decode((await _messages.get(key))!);
      await _order.put(message.orderKey, message.key);
      final keys = _chatKeys(await _chats.get(message.chatId))
        ..add(message.key);
      keys.sort(
        (a, b) => int.parse(
          a.split('_').last,
        ).compareTo(int.parse(b.split('_').last)),
      );
      await _chats.put(message.chatId, jsonEncode(keys));
      while (keys.length > conversationLimit) {
        await _deleteMessage(keys.removeAt(0));
      }
    }
    for (final box in _directoryBoxes) {
      await box.compact();
    }
  }

  Future<void> _cleanOrphanMedia() async {
    for (final key in _media.keys.toList()) {
      if (!_messages.containsKey(key)) await _deleteMedia(key as String);
    }
    final names =
        _media.values
            .map((raw) => (jsonDecode(raw) as Map)['name'] as String)
            .toSet();
    await for (final file in _mediaDirectory.list()) {
      if (file is io.File && !names.contains(p.basename(file.path))) {
        await file.delete();
      }
    }
  }

  Future<void> close() async {
    _cancelDownloads();
    await Future.wait(
      _downloads.values.map((download) async {
        try {
          await download;
        } catch (_) {
          /* Cancellation is expected. */
        }
      }),
    );
    await _serial(() async {
      for (final box in [..._cacheBoxes, ..._directoryBoxes]) {
        await box.close();
      }
      await _changes.close();
      await _errors.close();
    });
  }

  Future<void> sendReply(RawAPI api, int chatId, String text) async {
    if (text.trim().isEmpty || text.runes.length > 4096) {
      throw const InboxException('Replies must contain 1–4096 characters.');
    }
    final sent = await api.sendMessage(ChatID(chatId), text);
    // Also works with an API client without our transformer. Upserts deduplicate.
    try {
      await captureSent(sent.toJson());
    } catch (_) {
      reportCacheFailure();
    }
  }
}
