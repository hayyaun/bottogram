import 'package:flutter/widgets.dart';

import '../l10n/strings.dart';

enum InboxStorageProblem {
  unavailable,
  writeFailed;

  String message(BuildContext context) => switch (this) {
    unavailable => context.strings.inboxStorageUnavailable,
    writeFailed => context.strings.inboxStorageWriteFailed,
  };
}

class InboxDiagnostics {
  static final notice = ValueNotifier<InboxStorageProblem?>(null);

  static void reportUnavailable() {
    notice.value = InboxStorageProblem.unavailable;
  }
}
