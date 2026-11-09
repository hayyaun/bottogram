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
      attachment:
          j['attachment'] == null
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
    if (text.isEmpty && attachment == null) {
      text =
          j['dice'] != null
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
