import 'package:bottogram/plugins/failure_notice.dart';
import 'package:bottogram/runtime/failure_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'plugin error presentation keeps host notice and actions user initiated',
    (tester) async {
      var retries = 0;
      var edits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PluginFailureNotice(
              failure: const FailurePresentation(
                code: 'telegram.delivery_unconfirmed',
                title: 'Event reminder delivery unclear',
                message: 'The reminder service did not confirm delivery.',
                help: 'Check the conversation before trying again.',
                action: 'retry',
                hostNotice:
                    'Telegram may already have delivered this message. Retrying can send it again.',
              ),
              onRetry: () => retries++,
              onEditParameters: () => edits++,
            ),
          ),
        ),
      );
      expect(find.text('Event reminder delivery unclear'), findsOneWidget);
      expect(
        find.textContaining('Code: telegram.delivery_unconfirmed'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Retrying can send it again.'),
        findsOneWidget,
      );
      expect(find.text('Edit parameters'), findsNothing);
      expect(retries, 0);
      await tester.tap(find.text('Retry bot'));
      expect(retries, 1);
      expect(edits, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PluginFailureNotice(
              failure: const FailurePresentation(
                code: 'http.forbidden',
                title: 'Event access denied',
                message: 'Check this connection.',
                action: 'editPluginParameters',
              ),
              onEditParameters: () => edits++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit parameters'));
      expect(edits, 1);
      expect(find.text('Retry bot'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
