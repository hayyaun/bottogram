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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(failure.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(failure.message),
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
          'Code: ${failure.code}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (failure.action == 'editPluginParameters' &&
            onEditParameters != null)
          TextButton.icon(
            onPressed: onEditParameters,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit parameters'),
          ),
        if (failure.action == 'retry' && onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry bot'),
          ),
      ],
    ),
  );
}
