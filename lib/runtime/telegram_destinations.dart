const telegramDestinationChatTypes = {'channel', 'group', 'supergroup'};
const maxTelegramDestinations = 12;

List<String>? parseTelegramDestinations(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return const [];
  final unique = <String>{};
  for (final item in trimmed.split(RegExp(r'[\s,،]+'))) {
    final id = int.tryParse(item);
    if (id == null ||
        !RegExp(r'^-[1-9][0-9]{0,15}$').hasMatch(item) ||
        id < -4503599627370495) {
      return null;
    }
    unique.add(item);
    if (unique.length > maxTelegramDestinations) return null;
  }
  return unique.toList(growable: false);
}
