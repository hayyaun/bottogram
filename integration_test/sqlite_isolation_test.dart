import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/sqlite_isolation_cases.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'packaged SQLite enforces per-bot isolation and execution budgets',
    (tester) async {
      // This test starts neither the user's application nor its Hive storage.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('SQLite isolation test'))),
        ),
      );
      final root = await Directory.systemTemp.createTemp(
        'bottogram-native-sqlite-',
      );
      try {
        final report = await exerciseSqliteIsolation(
          root: root,
          onCasePassed: (name) => debugPrint('SQLITE_NATIVE_PASS $name'),
        );
        binding.reportData = {'sqliteIsolation': report};
        debugPrint('SQLITE_NATIVE_RESULT ${jsonEncode(report)}');
      } finally {
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
