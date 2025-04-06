import 'package:flutter/material.dart';

extension ContextUtils on BuildContext {
  void showSnackBar(String message, [int seconds = 2]) {
    final snackBar = SnackBar(
      content: Text(message),
      duration: Duration(seconds: seconds),
      behavior: SnackBarBehavior.floating,
    );

    ScaffoldMessenger.of(this).showSnackBar(snackBar);
  }

  ColorScheme get colors => Theme.of(this).colorScheme;
}
