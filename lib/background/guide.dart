import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import '../ui/design.dart';
import 'controller.dart';

String backgroundRequirement(BackgroundController controller) {
  final s = controller.snapshot;
  if (s.error != null) return 'Background settings could not be checked.';
  if (s.batteryExempt != true) {
    return 'Battery optimization can interrupt your bots.';
  }
  if (s.backgroundRestricted != false) {
    return 'Android restricts background activity.';
  }
  if (s.notificationsEnabled != true) {
    return 'Enable notifications to see and stop running bots.';
  }
  return 'Background setup is ready.';
}

class BackgroundSetupHost extends StatefulWidget {
  const BackgroundSetupHost({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
  });
  final BackgroundController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  State<BackgroundSetupHost> createState() => _BackgroundSetupHostState();
}

class _BackgroundSetupHostState extends State<BackgroundSetupHost> {
  int _shownOpening = 0;
  bool _guideOpen = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant BackgroundSetupHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = widget.controller;
      if (c.checked &&
          c.resumed &&
          c.needsGuide &&
          _shownOpening != c.opening) {
        _shownOpening = c.opening;
        if (!_guideOpen) _show();
      }
      setState(() {});
    });
  }

  Future<void> _show() async {
    final navigator = widget.navigatorKey.currentState;
    if (_guideOpen || navigator == null) return;
    _shownOpening = widget.controller.opening;
    _guideOpen = true;
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => BackgroundGuide(controller: widget.controller),
        ),
      );
    } finally {
      _guideOpen = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class BackgroundGuide extends StatelessWidget {
  const BackgroundGuide({super.key, required this.controller});
  final BackgroundController controller;
  String _status(BuildContext context, bool? value, bool expected) =>
      value == null
      ? context.strings.backgroundNotChecked
      : value == expected
      ? context.strings.backgroundReady
      : context.strings.backgroundNeedsSetup;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final s = controller.snapshot;
      return Scaffold(
        appBar: AppBar(title: Text(context.strings.keepBotsRunning)),
        body: SingleChildScrollView(
          child: BContent(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BHeading(
                  title: context.strings.allowBackgroundActivity,
                  subtitle: context.strings.startedBotsNeedAConnectionEven,
                ),
                const SizedBox(height: 24),
                Text(context.strings.bottogramKeepsRunningBotsInA),
                const SizedBox(height: 24),
                BPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.strings.batteryOptimizationStatus(
                          _status(context, s.batteryExempt, true),
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(context.strings.inAndroidBatterySettingsShowAll),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => controller.openSettings(battery: true),
                        child: Text(context.strings.openBatterySettings),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.strings.backgroundRestrictionsStatus(
                          _status(context, s.backgroundRestricted, false),
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(context.strings.openBottogramSAppSettingsAnd),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => controller.openSettings(),
                        child: Text(context.strings.openAppSettings),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.strings.notificationsStatus(
                          _status(context, s.notificationsEnabled, true),
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(context.strings.allowNotificationsSoYouCanSee),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: controller.requestNotifications,
                        child: Text(context.strings.allowNotifications),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (s.error != null) BNotice(message: s.error!, error: true),
                if (controller.actionError != null)
                  BNotice(message: controller.actionError!, error: true),
                const SizedBox(height: 16),
                BNotice(
                  message: s.ready
                      ? context.strings.backgroundSetupIsReadyStartA
                      : backgroundRequirement(controller),
                ),
                const SizedBox(height: 20),
                Text(context.strings.ifAndroidEndsBottogramOrYour),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: controller.refresh,
                  child: Text(context.strings.checkAgain),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    s.ready
                        ? context.strings.done
                        : context.strings.skipForThisOpening,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
