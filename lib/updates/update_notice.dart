import 'package:bottogram/l10n/strings.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/utils/context.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_updates.dart';

class AppUpdateNotice extends StatelessWidget {
  const AppUpdateNotice({super.key, required this.release});

  final AppRelease release;

  Future<void> _openRelease(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(
        release.page,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Show the same guidance if the system browser fails to open.
    }
    if (!opened && context.mounted) {
      context.showSnackBar(context.strings.appUpdateLinkFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BColors.of(context);
    return BPanel(
      padding: const EdgeInsets.all(14),
      color: colors.subtle,
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.system_update_alt, color: colors.ink),
              const SizedBox(width: 12),
              Flexible(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    context.strings.appUpdateAvailable(
                      context.leftToRightText(release.version),
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: () => _openRelease(context),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(context.strings.downloadAppUpdate),
          ),
        ],
      ),
    );
  }
}

class AppUpdateSettings extends StatelessWidget {
  const AppUpdateSettings({super.key, required this.updates});

  final AppUpdates updates;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final installedVersion = updates.installedVersion;
    final release = updates.available;
    final feedback = updates.feedback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              installedVersion == null
                  ? 'Bottogram'
                  : strings.versionLabel(
                      context.leftToRightText(installedVersion),
                    ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            OutlinedButton.icon(
              onPressed: updates.checking
                  ? null
                  : () => updates.check(manual: true),
              icon: const Icon(Icons.refresh, size: 20),
              label: Text(
                updates.checking
                    ? strings.checkingForAppUpdates
                    : strings.checkForAppUpdates,
              ),
            ),
          ],
        ),
        if (release != null) ...[
          const SizedBox(height: 12),
          AppUpdateNotice(release: release),
        ],
        if (feedback != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: BNotice(
              icon: feedback == AppUpdateFeedback.upToDate
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              message: feedback == AppUpdateFeedback.upToDate
                  ? strings.appUpToDate
                  : strings.appUpdateCheckFailed,
            ),
          ),
        ],
      ],
    );
  }
}
