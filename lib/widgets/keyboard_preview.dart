import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';

class KeyboardPreview extends StatelessWidget {
  const KeyboardPreview({super.key, required this.rows});
  final List<List<Widget>> rows;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(
      color: BColors.subtle,
      borderRadius: BottogramDesign.controlRadius,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Preview · tap a button to remove it',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (row.isEmpty) return const SizedBox(height: 8);
                if (constraints.maxWidth / row.length >= 80) {
                  return Row(
                    spacing: 8,
                    children: [for (final key in row) Expanded(child: key)],
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 8,
                    children: [
                      for (final key in row) SizedBox(width: 112, child: key),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}

class KeyboardPreviewKey extends StatelessWidget {
  const KeyboardPreviewKey({
    super.key,
    required this.label,
    required this.onRemove,
    this.detail,
  });
  final String label;
  final String? detail;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Remove $label${detail == null ? '' : '\n$detail'}',
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(backgroundColor: BColors.surface),
      onPressed: onRemove,
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
