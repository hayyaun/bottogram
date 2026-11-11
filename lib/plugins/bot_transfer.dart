import 'dart:convert';
import 'dart:io';

import 'admin_ids.dart';
import 'manifest.dart';

/// A plugin bot's portable inputs. The link is local to the QR importer and
/// contains credentials. Keep it out of logs, backups and clipboard history.
class PluginBotTransfer {
  const PluginBotTransfer({
    required this.name,
    required this.token,
    required this.adminIds,
    required this.pluginKey,
    required this.pluginDigest,
    required this.parameters,
    required this.settings,
  });

  static const _prefix = 'bottogram://import/plugin-bot/v1#';
  // ASCII payloads fit a single QR code at error correction level M.
  static const _maxLinkLength = 2300;
  static const _maxJsonBytes = 128 * 1024;
  static final _keyPattern = RegExp(
    r'^[a-z0-9][a-z0-9._-]*@[0-9]+\.[0-9]+\.[0-9]+$',
  );
  static final _digestPattern = RegExp(r'^[0-9a-f]{64}$');
  static final _tokenPattern = RegExp(r'^[0-9]+:[A-Za-z0-9_-]+$');
  static final _payloadPattern = RegExp(r'^[A-Za-z0-9_-]+$');
  static const _invalid = PluginException(
    'This is not a valid Bottogram bot QR code.',
  );
  static const _tooLarge = PluginException(
    'This bot’s configuration is too large for a single QR code.',
  );

  final String name;
  final String token;
  final List<String> adminIds;
  final String pluginKey;
  final String pluginDigest;
  final Map<String, String> parameters;
  final Map<String, Object?> settings;

  String toLink() {
    final bytes = utf8.encode(
      jsonEncode({
        'name': name,
        'token': token,
        'admins': adminIds,
        'plugin': pluginKey,
        'digest': pluginDigest,
        'parameters': parameters,
        'settings': settings,
      }),
    );
    if (bytes.length > _maxJsonBytes) throw _tooLarge;
    final payload = base64UrlEncode(zlib.encode(bytes)).replaceAll('=', '');
    final link = '$_prefix$payload';
    if (link.length > _maxLinkLength) throw _tooLarge;
    return link;
  }

  static PluginBotTransfer fromLink(String link) {
    if (link.length > _maxLinkLength || !link.startsWith(_prefix)) {
      throw _invalid;
    }
    final payload = link.substring(_prefix.length);
    if (!_payloadPattern.hasMatch(payload)) throw _invalid;

    try {
      final bytes = zlib.decode(base64Url.decode(base64Url.normalize(payload)));
      if (bytes.length > _maxJsonBytes) throw _invalid;
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final name = data['name'] as String;
      final token = data['token'] as String;
      final pluginKey = data['plugin'] as String;
      final digest = data['digest'] as String;
      final admins = parseAdminIds(
        (data['admins'] as List).cast<String>().join('\n'),
      );
      if (name.trim().isEmpty ||
          !_tokenPattern.hasMatch(token) ||
          !_keyPattern.hasMatch(pluginKey) ||
          !_digestPattern.hasMatch(digest) ||
          admins == null) {
        throw _invalid;
      }
      return PluginBotTransfer(
        name: name,
        token: token,
        adminIds: List.unmodifiable(admins),
        pluginKey: pluginKey,
        pluginDigest: digest,
        parameters: Map.unmodifiable(
          Map<String, String>.from(data['parameters'] as Map),
        ),
        settings: Map.unmodifiable(
          Map<String, Object?>.from(data['settings'] as Map),
        ),
      );
    } catch (_) {
      // Parser errors can include the decoded JSON and its credentials.
      throw _invalid;
    }
  }
}
