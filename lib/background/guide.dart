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
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.controller.checked && widget.controller.needsGuide)
        Material(
          color: BColors.warningWash,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    backgroundRequirement(widget.controller),
                    style: BottogramDesign.text(13, color: BColors.warning),
                  ),
                  TextButton(
                    onPressed: _show,
                    child: const Text('Read instructions'),
                  ),
                ],
              ),
            ),
          ),
        ),
      Expanded(child: widget.child),
    ],
  );
}

class BackgroundGuide extends StatelessWidget {
  const BackgroundGuide({super.key, required this.controller});
  final BackgroundController controller;
  String _status(bool? value, bool expected) =>
      value == null
          ? 'Not checked'
          : value == expected
          ? 'Ready'
          : 'Needs setup';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final s = controller.snapshot;
      return Scaffold(
        appBar: AppBar(title: const Text('Keep bots running')),
        body: SingleChildScrollView(
          child: BContent(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BHeading(
                  title: 'Allow background activity',
                  subtitle:
                      'Started bots need a connection even when this screen is closed.',
                ),
                const SizedBox(height: 24),
                const Text(
                  'Bottogram keeps a foreground service and a visible notification while bots are started. This uses battery and data. The notification includes Stop bots.',
                ),
                const SizedBox(height: 24),
                BPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Battery optimization · ${_status(s.batteryExempt, true)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'In Android battery settings, show all apps, select Bottogram, and choose Don’t optimize. On devices with additional app battery controls, allow background activity or choose Unrestricted.',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => controller.openSettings(battery: true),
                        child: const Text('Open battery settings'),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Background restrictions · ${_status(s.backgroundRestricted, false)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Open Bottogram’s app settings and check Battery or Background activity. Android settings differ by device.',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => controller.openSettings(),
                        child: const Text('Open app settings'),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Notifications · ${_status(s.notificationsEnabled, true)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Allow notifications so you can see running bots and stop them. If a permission prompt no longer appears, enable notifications in app settings.',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: controller.requestNotifications,
                        child: const Text('Allow notifications'),
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
                  message:
                      s.ready
                          ? 'Background setup is ready. Start a bot to run it. This does not check its API key or network connection.'
                          : backgroundRequirement(controller),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Force-stop, device restart, or Android ending the app process stops bots. Reopen Bottogram and start them again. Saved automation progress is retained. Battery exemption cannot guarantee that every device will keep an app alive.',
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: controller.refresh,
                  child: const Text('Check again'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.ready ? 'Done' : 'Skip for this opening'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
