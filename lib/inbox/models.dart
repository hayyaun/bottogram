import 'dart:convert';

const inboxPageSize = 25;
const conversationLimit = 20;
const mib = 1024 * 1024;

class InboxSettings {
  const InboxSettings({this.limitMiB = 10});
  final int limitMiB;
  int get limitBytes => limitMiB * mib;
}

class KnownUser {
  const KnownUser({
    required this.id,
    required this.name,
    this.username,
    required this.lastInteraction,
  });
  final int id;
  final String name;
  final String? username;
  final int lastInteraction;
  String get activityKey =>
      '${lastInteraction.toString().padLeft(20, '0')}_$id';
  String encode() => jsonEncode({
    'id': id,
    'name': name,
    'username': username,
    'lastInteraction': lastInteraction,
  });
  factory KnownUser.decode(String value) {
    final j = jsonDecode(value) as Map<String, dynamic>;
    return KnownUser(
      id: j['id'] as int,
      name: j['name'] as String,
      username: j['username'] as String?,
      lastInteraction: j['lastInteraction'] as int,
    );
  }
}

class InboxAttachment {
  const InboxAttachment({
    required this.fileId,
    required this.kind,
    required this.name,
    this.size,
    this.mimeType,
  });
  final String fileId;
  final String kind;
  final String name;
  final int? size;
  final String? mimeType;
  bool get isImage => kind == 'photo';
  Map<String, dynamic> toJson() => {
    'fileId': fileId,
    'kind': kind,
    'name': name,
    'size': size,
    'mimeType': mimeType,
  };
  factory InboxAttachment.fromJson(Map<String, dynamic> j) => InboxAttachment(
    fileId: j['fileId'] as String,
    kind: j['kind'] as String,
    name: j['name'] as String,
    size: j['size'] as int?,
    mimeType: j['mimeType'] as String?,
  );
}

class CachedMessage {
  const CachedMessage({
    required this.id,
    required this.chatId,
    required this.date,
    required this.outgoing,
    required this.text,
    this.attachment,
    this.edited = false,
  });
  final int id;
  final int chatId;
  final int date;
  final bool outgoing;
  final String text;
  final bool edited;
  final InboxAttachment? attachment;
  String get key => '${chatId}_$id';
  String get orderKey => '${date.toString().padLeft(20, '0')}_$key';
  String encode() => jsonEncode({
    'id': id,
    'chatId': chatId,
    'date': date,
    'outgoing': outgoing,
    'text': text,
    'edited': edited,
    'attachment': attachment?.toJson(),
  });
  factory CachedMessage.decode(String value) {
    final j = jsonDecode(value) as Map<String, dynamic>;
    return CachedMessage(
      id: j['id'] as int,
      chatId: j['chatId'] as int,
      date: j['date'] as int,
      outgoing: j['outgoing'] as bool,
      text: j['text'] as String,
      edited: j['edited'] as bool,
      attachment: j['attachment'] == null
          ? null
          : InboxAttachment.fromJson(
              Map<String, dynamic>.from(j['attachment'] as Map),
            ),
    );
  }
  factory CachedMessage.fromTelegram(
    Map<String, dynamic> j, {
    required bool outgoing,
  }) {
    InboxAttachment? attachment;
    const extensions = {
      'photo': 'jpg',
      'voice': 'ogg',
      'audio': 'mp3',
      'video': 'mp4',
      'video_note': 'mp4',
      'animation': 'mp4',
      'document': 'bin',
    };
    for (final entry in extensions.entries) {
      dynamic data = j[entry.key];
      if (data is List) data = data.isEmpty ? null : data.last;
      if (data is Map && data['file_id'] is String) {
        attachment = InboxAttachment(
          fileId: data['file_id'] as String,
          kind: entry.key,
          name: data['file_name'] as String? ?? '${entry.key}.${entry.value}',
          size: data['file_size'] as int?,
          mimeType: data['mime_type'] as String?,
        );
        break;
      }
    }
    var text = (j['text'] ?? j['caption'] ?? '') as String;
    if (text.isEmpty && j['rich_message'] is Map) {
      final rich = j['rich_message'] as Map;
      final excerpt = _richExcerpt(rich['blocks']);
      text = excerpt.isEmpty ? 'Rich message' : excerpt;
    }
    if (text.isEmpty && attachment == null) {
      text = j['dice'] != null
          ? 'Dice: ${(j['dice'] as Map)['value']}'
          : j['sticker'] != null
          ? 'Sticker ${(j['sticker'] as Map)['emoji'] ?? ''}'
          : j['contact'] != null
          ? 'Contact'
          : j['location'] != null
          ? 'Location'
          : j['poll'] != null
          ? 'Poll: ${(j['poll'] as Map)['question']}'
          : 'Unsupported message';
    }
    return CachedMessage(
      id: j['message_id'] as int,
      chatId: (j['chat'] as Map)['id'] as int,
      date: j['date'] as int,
      outgoing: outgoing,
      text: text,
      edited: j['edit_date'] != null,
      attachment: attachment,
    );
  }
}

/// Keep an inbox-readable excerpt of Telegram's documented rich block fields.
String _richExcerpt(Object? blocks) {
  final lines = <String>[];
  var budget = 4096;
  String inline(Object? value, [int depth = 0]) {
    if (depth > 8 || budget <= 0) return '';
    if (value is String) {
      final result = value.length > budget ? value.substring(0, budget) : value;
      budget -= result.length;
      return result;
    }
    if (value is List) {
      final text = StringBuffer();
      for (final part in value.take(100)) {
        text.write(inline(part, depth + 1));
      }
      return text.toString();
    }
    if (value is Map) {
      return inline(value['text'] ?? value['alternative_text'], depth + 1);
    }
    return '';
  }

  void add(String text) {
    if (text.trim().isNotEmpty) lines.add(text);
  }

  void visit(Object? values, int depth) {
    if (values is! List || depth > 8) return;
    for (final block in values.take(100)) {
      if (budget <= 0 || lines.length >= 100) return;
      if (block is! Map) continue;
      add(inline(block['text'] ?? block['summary']));
      if (block['caption'] is Map) add(inline(block['caption']));
      visit(block['blocks'], depth + 1);
      final items = block['items'];
      if (block['type'] == 'list' && items is List) {
        for (final item in items.take(50)) {
          if (item is Map) visit(item['blocks'], depth + 1);
        }
      }
      final rows = block['cells'];
      if (block['type'] == 'table' && rows is List) {
        for (final row in rows.take(50)) {
          if (row is List && budget > 0) {
            add(row.take(8).map((cell) => inline(cell)).join(' · '));
          }
        }
      }
    }
  }

  visit(blocks, 0);
  return lines.join('\n');
}

class UserPage {
  const UserPage(this.users, this.total, this.page);
  final List<KnownUser> users;
  final int total;
  final int page;
  bool get hasNext => (page + 1) * inboxPageSize < total;
}

class InboxUsage {
  const InboxUsage({
    required this.cacheBytes,
    required this.directoryBytes,
    required this.limitBytes,
    required this.userCount,
  });
  final int cacheBytes;
  final int directoryBytes;
  final int limitBytes;
  final int userCount;
}

class InboxException implements Exception {
  const InboxException(this.message);
  final String message;
  @override
  String toString() => message;
}
