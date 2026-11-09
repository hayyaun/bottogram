import 'package:flutter/foundation.dart';

class InboxDiagnostics {
  static final notice = ValueNotifier<String?>(null);
  static String? get error => notice.value;
  static void reportUnavailable() {
    notice.value =
        'Inbox storage could not be opened. Check free space and try again.';
  }
}
