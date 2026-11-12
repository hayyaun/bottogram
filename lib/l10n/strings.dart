import 'package:flutter/material.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_en.dart';

final _english = AppLocalizationsEn();

extension BottogramStrings on BuildContext {
  AppLocalizations get strings => AppLocalizations.of(this) ?? _english;

  String formatDateAndTime(DateTime value) {
    final labels = MaterialLocalizations.of(this);
    final date = labels.formatCompactDate(value);
    final time = labels.formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: true,
    );
    return '$date $time';
  }

  /// Keeps punctuation in protocol text such as `/start` in reading order.
  String leftToRightText(String value) =>
      Directionality.of(this) == TextDirection.rtl
      ? '\u2066$value\u2069'
      : value;
}
