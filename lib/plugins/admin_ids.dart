/// Telegram user IDs are positive integers with at most 52 significant bits.
List<String>? parseAdminIds(String? value) {
  final ids = (value ?? '')
      .split(RegExp(r'[,\s]+'))
      .where((id) => id.isNotEmpty)
      .toSet();
  if (ids.isEmpty ||
      ids.any((id) {
        final number = int.tryParse(id);
        return !RegExp(r'^[1-9][0-9]*$').hasMatch(id) ||
            number == null ||
            number > 4503599627370495;
      })) {
    return null;
  }
  return List.unmodifiable(ids);
}

String? validateAdminIds(String? value) => parseAdminIds(value) == null
    ? 'Enter at least one positive numeric Telegram user ID.'
    : null;
