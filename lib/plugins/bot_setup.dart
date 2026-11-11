import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'admin_ids.dart';

class BotSetup {
  const BotSetup({
    required this.instanceId,
    required this.tokenFingerprint,
    required this.adminIds,
    this.pluginKey,
    this.pluginDigest,
    this.pluginName,
    this.values = const {},
    this.secretFields = const [],
    this.settings = const {},
  });

  final String instanceId;
  final String tokenFingerprint;
  final List<String> adminIds;
  final String? pluginKey;
  final String? pluginDigest;
  final String? pluginName;
  final Map<String, String> values;
  final List<String> secretFields;
  final Map<String, Object?> settings;
  BotSetup withSettings(Map<String, Object?> updated) =>
      copyWith(settings: updated);
  BotSetup copyWith({
    List<String>? adminIds,
    Map<String, String>? values,
    Map<String, Object?>? settings,
  }) => BotSetup(
    instanceId: instanceId,
    tokenFingerprint: tokenFingerprint,
    adminIds: adminIds == null ? this.adminIds : List.unmodifiable(adminIds),
    pluginKey: pluginKey,
    pluginDigest: pluginDigest,
    pluginName: pluginName,
    values: values == null ? this.values : Map.unmodifiable(values),
    secretFields: secretFields,
    settings: settings == null ? this.settings : Map.unmodifiable(settings),
  );
  bool get usesPlugin => pluginKey != null;
  static String fingerprint(String token) =>
      sha256.convert(utf8.encode(token)).toString();
  String secretKey(String field) => 'bottogram.plugin.$instanceId.$field';

  Map<String, dynamic> toMap() => {
    'formatVersion': 1,
    'instanceId': instanceId,
    'tokenFingerprint': tokenFingerprint,
    'adminIds': adminIds,
    'pluginKey': pluginKey,
    'pluginDigest': pluginDigest,
    'pluginName': pluginName,
    'values': values,
    'secretFields': secretFields,
    'settings': settings,
  };

  factory BotSetup.fromMap(Map<dynamic, dynamic> data) {
    if (data['formatVersion'] != 1) {
      throw const FormatException('Unsupported bot settings.');
    }
    final storedAdmins = data['adminIds'];
    final ids = parseAdminIds(
      storedAdmins is List
          ? storedAdmins.cast<String>().join('\n')
          : data['adminTelegramUserId'] as String?,
    );
    if (ids == null) throw const FormatException('Invalid saved admins.');
    return BotSetup(
      instanceId: data['instanceId'] as String,
      tokenFingerprint: data['tokenFingerprint'] as String,
      adminIds: ids,
      pluginKey: data['pluginKey'] as String?,
      pluginDigest: data['pluginDigest'] as String?,
      pluginName: data['pluginName'] as String?,
      values: Map<String, String>.from(data['values'] as Map),
      secretFields: List<String>.from(data['secretFields'] as List),
      settings: Map<String, Object?>.from(data['settings'] as Map? ?? const {}),
    );
  }
}
