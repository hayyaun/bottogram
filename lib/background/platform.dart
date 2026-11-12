import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import '../runtime/ports.dart';

class BackgroundSnapshot {
  const BackgroundSnapshot({
    required this.supported,
    this.batteryExempt,
    this.backgroundRestricted,
    this.notificationsEnabled,
    this.serviceRunning,
    this.error,
  });
  final bool supported;
  final bool? batteryExempt;
  final bool? backgroundRestricted;
  final bool? notificationsEnabled;
  final bool? serviceRunning;
  final String? error;
  bool get ready =>
      supported &&
      batteryExempt == true &&
      backgroundRestricted == false &&
      notificationsEnabled == true;
  factory BackgroundSnapshot.fromMap(Map<Object?, Object?> data) =>
      BackgroundSnapshot(
        supported: true,
        batteryExempt: data['batteryExempt'] as bool?,
        backgroundRestricted: data['backgroundRestricted'] as bool?,
        notificationsEnabled: data['notificationsEnabled'] as bool?,
        serviceRunning: data['serviceRunning'] as bool?,
      );
}

abstract class BackgroundPlatform implements ExecutionLease {
  Future<void> Function()? onStopRequested;
  Future<void> Function()? onServiceEnded;
  void Function()? onStateChanged;
  bool get supported;
  Future<BackgroundSnapshot> readState();
  Future<bool> openBatterySettings();
  Future<bool> openAppSettings();
  Future<void> requestNotifications();
  @override
  Future<void> startService(int active, int total);
  @override
  Future<void> updateService(int active, int total);
  @override
  Future<void> stopService();
  void dispose() {}
  static BackgroundPlatform create() => Platform.isAndroid
      ? AndroidBackgroundPlatform()
      : DesktopBackgroundPlatform();
}

class DesktopBackgroundPlatform extends BackgroundPlatform {
  @override
  bool get supported => false;
  @override
  Future<BackgroundSnapshot> readState() async =>
      const BackgroundSnapshot(supported: false);
  @override
  Future<bool> openBatterySettings() async => false;
  @override
  Future<bool> openAppSettings() async => false;
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<void> startService(int active, int total) async {}
  @override
  Future<void> updateService(int active, int total) async {}
  @override
  Future<void> updateConnectionWarning(int affected) async {}
  @override
  Future<void> stopService() async {}
}

class AndroidBackgroundPlatform extends BackgroundPlatform {
  AndroidBackgroundPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('bottogram/background') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopBots') {
        await onStopRequested?.call();
      } else if (call.method == 'serviceEnded') {
        await onServiceEnded?.call();
      } else if (call.method == 'stateChanged') {
        onStateChanged?.call();
      }
    });
  }
  final MethodChannel _channel;
  @override
  bool get supported => true;
  @override
  Future<BackgroundSnapshot> readState() async {
    final data = await _channel
        .invokeMapMethod<Object?, Object?>('getState')
        .timeout(const Duration(seconds: 5));
    if (data == null) throw PlatformException(code: 'state_unavailable');
    return BackgroundSnapshot.fromMap(data);
  }

  @override
  Future<bool> openBatterySettings() async =>
      await _channel.invokeMethod<bool>('openBatterySettings') ?? false;
  @override
  Future<bool> openAppSettings() async =>
      await _channel.invokeMethod<bool>('openAppSettings') ?? false;
  @override
  Future<void> requestNotifications() =>
      _channel.invokeMethod<void>('requestNotifications');
  @override
  Future<void> startService(int active, int total) async {
    await _channel.invokeMethod<void>('startService', {
      'active': active,
      'total': total,
    });
    // Starting an Android component is not proof it reached the foreground.
    for (var attempt = 0; attempt < 40; attempt++) {
      if ((await readState()).serviceRunning == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw PlatformException(
      code: 'service_not_running',
      message:
          'Android could not start the bot service. Open Bottogram and try again.',
    );
  }

  @override
  Future<void> updateService(int active, int total) => _channel
      .invokeMethod<void>('updateService', {'active': active, 'total': total});
  @override
  Future<void> updateConnectionWarning(int affected) => _channel
      .invokeMethod<void>('updateConnectionWarning', {'affected': affected});
  @override
  Future<void> stopService() => _channel.invokeMethod<void>('stopService');
  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
