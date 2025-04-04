import 'package:flutter/material.dart';

InputDecoration inputDecorationCommon(BuildContext context) {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Theme.of(context).colorScheme.onSurface.withAlpha(18),
    // fillColor: Theme.of(context).colorScheme.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide.none,
    ),
  );
}
