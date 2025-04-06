// ignore_for_file: use_build_context_synchronously

import 'package:bottogram/store/bots.dart';
import 'package:bottogram/utils/list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

class ShareDialog extends StatefulWidget {
  const ShareDialog({super.key});

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  List<int> items = [];

  @override
  Widget build(BuildContext context) {
    final bots = context.read<BotsCubit>().state;
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Select Bots'),
          IconButton(
            onPressed: () async {
              items = bots.asMap().entries.mapToList((entry) => entry.key);
              setState(() {});
            },
            icon: Icon(Icons.select_all),
          ),
        ],
      ),
      content: Wrap(
        spacing: 8,
        children: bots.mapToList((bot) {
          final index = bots.indexOf(bot);
          final selected = items.contains(index);
          return ChoiceChip(
            label: Text(bot.name),
            selected: selected,
            onSelected: (active) {
              if (active) {
                items.add(index);
              } else {
                items.remove(index);
              }
              setState(() {});
            },
            checkmarkColor: Theme.of(context).colorScheme.onSurface,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.onSurface.withAlpha(18),
            selectedColor: Theme.of(context).colorScheme.primary,
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            side: BorderSide.none,
          );
        }),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(); // Close the dialog
          },
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            if (items.isEmpty) return;
            final result = await context.read<BotsCubit>().share(items);
            if (result?.status == ShareResultStatus.success) {} // TODO
            context.read<BotsCubit>().update();
            Navigator.of(context).pop(); // Close the dialog
          },
          child: Text('Add'),
        ),
      ],
    );
  }
}
