/// Parses a public origin supplied through a declared URL-origin binding.
/// Bare authorities default to HTTPS; explicit schemes retain their meaning.
/// Saved values and ordinary text/header-value bindings are never changed.
Uri? parseConfiguredOrigin(String value, {bool requireHttps = false}) {
  if (value.isEmpty ||
      value.length > 2048 ||
      value != value.trim() ||
      value.contains('@') ||
      value.contains('%') ||
      RegExp(r'[\s\\]').hasMatch(value)) {
    return null;
  }
  final address = Uri.tryParse(
    _isBareAuthority(value) ? 'https://$value' : value,
  );
  if (address == null ||
      (requireHttps
          ? address.scheme != 'https'
          : !{'http', 'https'}.contains(address.scheme)) ||
      address.host.isEmpty ||
      address.userInfo.isNotEmpty ||
      address.hasQuery ||
      address.hasFragment ||
      (address.path.isNotEmpty && address.path != '/') ||
      (address.hasPort && (address.port < 1 || address.port > 65535))) {
    return null;
  }
  return address;
}

bool _isBareAuthority(String value) {
  final authority = value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
  if (authority.isEmpty || RegExp(r'[/\?#]').hasMatch(authority)) return false;
  if (authority.startsWith('[')) {
    return RegExp(r'^\[[0-9a-fA-F:.]+\](?::[0-9]+)?$').hasMatch(authority);
  }
  final colon = authority.indexOf(':');
  if (colon < 0) return true;
  final host = authority.substring(0, colon);
  final port = authority.substring(colon + 1);
  // Uri.hasScheme also matches example.test:8443. Recognize domain/IP and
  // localhost ports explicitly, while leaving ambiguous schemes such as
  // custom:443 to the normal scheme validation above.
  return (host.contains('.') || host.toLowerCase() == 'localhost') &&
      RegExp(r'^[0-9]+$').hasMatch(port);
}
