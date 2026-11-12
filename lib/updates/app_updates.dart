import 'dart:async';

import 'package:bottogram/runtime/http_transport.dart';
import 'package:bottogram/runtime/ports.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

const _repository = 'hayyaun/bottogram';

class AppRelease {
  const AppRelease._(this.version, this.page);

  final String version;
  final Uri page;
}

enum AppUpdateFeedback { upToDate, failed }

class AppUpdates extends ChangeNotifier {
  AppUpdates({JsonTransport? transport, Future<String> Function()? readVersion})
    : _transport = transport ?? BoundedJsonTransport(),
      _readVersion = readVersion ?? _packageVersion;

  static const _automaticInterval = Duration(hours: 12);
  static final _endpoint = Uri.https(
    'api.github.com',
    '/repos/$_repository/releases/latest',
  );
  static final _stableTag = RegExp(
    r'^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$',
  );
  final JsonTransport _transport;
  final Future<String> Function() _readVersion;

  Version? _installed;
  AppRelease? _available;
  AppUpdateFeedback? _feedback;
  DateTime? _lastCheck;
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  bool _checking = false;
  bool _disposed = false;

  String? get installedVersion => _installed?.toString();
  AppRelease? get available => _available;
  AppUpdateFeedback? get feedback => _feedback;
  bool get checking => _checking;

  static Future<String> _packageVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  void start() {
    if (_disposed || _lifecycle != null) return;
    _lifecycle = AppLifecycleListener(onResume: _checkAutomatically);
    _timer = Timer.periodic(_automaticInterval, (_) => _checkAutomatically());
    _checkAutomatically();
  }

  void _checkAutomatically() {
    final lastCheck = _lastCheck;
    if (lastCheck == null ||
        DateTime.now().difference(lastCheck) >= _automaticInterval) {
      unawaited(check());
    }
  }

  Future<void> check({bool manual = false}) async {
    if (_disposed || _checking) return;
    _checking = true;
    _feedback = null;
    _lastCheck = DateTime.now();
    notifyListeners();
    try {
      var installed = _installed;
      if (installed == null) {
        installed = Version.parse((await _readVersion()).split('+').first);
        if (_disposed) return;
        _installed = installed;
        notifyListeners();
      }

      final release = await _transport.get(_endpoint, const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Bottogram',
        'X-GitHub-Api-Version': '2026-03-10',
      });
      if (_disposed) return;
      final tag = release['tag_name'];
      if (tag is! String ||
          !_stableTag.hasMatch(tag) ||
          release['draft'] != false ||
          release['prerelease'] != false) {
        throw const FormatException('Invalid stable release.');
      }
      final version = Version.parse(tag.substring(1));
      _available = version > installed
          ? AppRelease._(
              version.toString(),
              Uri.https('github.com', '/$_repository/releases/tag/$tag'),
            )
          : null;
      if (manual && _available == null) _feedback = AppUpdateFeedback.upToDate;
    } catch (_) {
      // Startup checks are quiet when GitHub or the network is unavailable.
      if (manual && !_disposed) _feedback = AppUpdateFeedback.failed;
    } finally {
      if (!_disposed) {
        _checking = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    _timer?.cancel();
    _transport.close();
    super.dispose();
  }
}
