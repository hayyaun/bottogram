extension StringEllipsize on String {
  String ellipsize([int maxLength = 8]) {
    return length > maxLength ? '${substring(0, maxLength)}…' : this;
  }
}
