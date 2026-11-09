import 'dart:async';

import 'package:flutter/widgets.dart';
import 'platform.dart';

class BackgroundController extends ChangeNotifier with WidgetsBindingObserver {
  BackgroundController(this.platform) {
    snapshot = BackgroundSnapshot(supported: platform.supported);
    WidgetsBinding.instance.addObserver(this);
    platform.onStateChanged = () => unawaited(refresh());
    ready = refresh();
  }
  final BackgroundPlatform platform;
  late final Future<void> ready;
  late BackgroundSnapshot snapshot;
  int opening = 1;
  bool checked = false;
  bool resumed =
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool _leftApp = false;
  bool _settingsTrip = false;
  bool _disposed = false;
  int _read = 0;
  String? actionError;
  bool get needsGuide => snapshot.supported && !snapshot.ready;

  Future<void> refresh() async {
    final request = ++_read;
    BackgroundSnapshot result;
    try {
      result = await platform.readState();
    } catch (_) {
      result = BackgroundSnapshot(
        supported: platform.supported,
        error:
            'Android background settings could not be checked. Reopen settings and try again.',
      );
    }
    if (_disposed || request != _read) return;
    snapshot = result;
    checked = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftApp = true;
      resumed = false;
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      resumed = false;
    } else if (state == AppLifecycleState.resumed) {
      resumed = true;
      if (_leftApp && !_settingsTrip) opening++;
      _leftApp = false;
      _settingsTrip = false;
      unawaited(refresh());
    }
  }

  Future<void> openSettings({bool battery = false}) async {
    _settingsTrip = true;
    actionError = null;
    notifyListeners();
    try {
      final opened =
          battery
              ? await platform.openBatterySettings()
              : await platform.openAppSettings();
      if (!opened) {
        _settingsTrip = false;
        actionError =
            'This settings page is unavailable. Open Android Settings, then Apps, Bottogram, and Battery.';
      }
    } catch (_) {
      _settingsTrip = false;
      actionError =
          'Android settings could not be opened. Open Settings, then Apps and Bottogram.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> requestNotifications() async {
    _settingsTrip = true;
    actionError = null;
    try {
      await platform.requestNotifications();
    } catch (_) {
      actionError =
          'Notification permission could not be requested. Use Open app settings.';
    }
    _settingsTrip = false;
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    platform.onStateChanged = null;
    platform.dispose();
    super.dispose();
  }
}
