import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../runtime/failure_presentation.dart';
import '../ui/design.dart';

class PluginFailureNotice extends StatelessWidget {
  const PluginFailureNotice({
    super.key,
    required this.failure,
    this.onEditParameters,
    this.onRetry,
  });

  final FailurePresentation failure;
  final VoidCallback? onEditParameters;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => BPanel(
    color: BColors.of(context).errorWash,
    borderColor: BColors.of(context).error,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: BColors.of(context).error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                failure.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: BColors.of(context).error,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(failure.message),
        if (failure.destination case final String destination) ...[
          const SizedBox(height: 8),
          Text(context.strings.telegramChatId(destination)),
        ],
        if (failure.help != null) ...[
          const SizedBox(height: 8),
          Text(failure.help!),
        ],
        if (failure.hostNotice != null) ...[
          const SizedBox(height: 12),
          BNotice(message: failure.hostNotice!),
        ],
        const SizedBox(height: 12),
        SelectableText(
          context.strings.failureCode(context.leftToRightText(failure.code)),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (failure.action == 'editPluginParameters' &&
            onEditParameters != null)
          TextButton.icon(
            onPressed: onEditParameters,
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.strings.editParameters),
          ),
        if (failure.action == 'retry' && onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(context.strings.retryBot),
          ),
      ],
    ),
  );
}
