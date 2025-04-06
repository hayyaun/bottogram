import 'package:bottogram/utils/context.dart';
import 'package:flutter/material.dart';

InputDecoration inputDecorationCommon(BuildContext context) {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: context.colors.onSurface.withAlpha(18),
    // fillColor: context.colors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide.none,
    ),
  );
}
