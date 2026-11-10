import 'dart:convert';
import 'dart:io';
import 'package:bottogram/builder/database.dart';
import 'package:bottogram/builder/store.dart';
import 'package:bottogram/templates/catalog.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import '../test/bot_templates_test.dart' show TemplateHarness, PriceTransport;
import '../test/plugins_test.dart' show MemoryVault;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('packaged general templates execute with isolated real SQL state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Testing bot templates'))),
      ),
    );
    final root = await Directory.systemTemp.createTemp(
      'bottogram-native-templates-',
    );
    Hive.init(root.path);
    final store = BuilderStore(
      vault: MemoryVault(),
      data: BotDatabases(root: '${root.path}/data'),
    );
    final fixtures = <String, TemplateHarness>{};
    try {
      await store.ready;
      for (final template in BotTemplates.all) {
        final draft = BotTemplates.create(
          template,
          template.defaults(),
          template.sampleRows(),
          '99',
        );
        final id = builderBotId('native-template-${template.id}');
        for (final definition in draft.variables) {
          await store.addDefinition(id, definition);
        }
        final h = TemplateHarness(id, draft, store, PriceTransport());
        fixtures[template.id] = h;
        await h.command('start');
        expect(h.transport.calls, 0);
      }
      final quiz = fixtures['quiz']!;
      await quiz.click('quiz:topic:Everyday knowledge');
      await quiz.click('quiz:A:1');
      await quiz.click('quiz:A:1');
      await quiz.click('quiz:B:2');
      await quiz.click('quiz:C:3');
      expect(quiz.messages.last, contains('Personal best: 3'));
      final tasks = fixtures['tasks']!;
      await tasks.click('task:add');
      await tasks.text('A native task');
      await tasks.click('task:delete:1', user: 2);
      expect(
        (await tasks.query('SELECT count(*) AS n FROM tasks')).single['n'],
        1,
      );
      await tasks.click('task:toggle:1');
      expect((await tasks.query('SELECT done FROM tasks')).single['done'], 1);
      final library = fixtures['library']!;
      await library.click('lib:favorite:1');
      await library.click('lib:favorites', user: 2);
      expect(library.messages.last, contains('No matching'));
      await library.command('search');
      await library.text('WELCOME');
      expect(library.messages.last, contains('Welcome guide'));
      final feedback = fixtures['feedback']!;
      await feedback.click('survey:begin');
      await feedback.click('survey:5:1');
      await feedback.text('Native feedback');
      await feedback.click('survey:4:3');
      await feedback.click('survey:submit');
      await feedback.click('survey:submit');
      expect(
        (await feedback.query(
          'SELECT count(*) AS n FROM survey_submissions',
        )).single['n'],
        1,
      );
      final requests = fixtures['requests']!;
      await requests.click('request:new');
      await requests.text('A native question');
      await requests.text('Some details');
      await requests.click('request:close:1', user: 2);
      expect(
        (await requests.query('SELECT status FROM requests')).single['status'],
        'Open',
      );
      await requests.click('request:reply:1', user: 99);
      await requests.text('A native reply', user: 99);
      expect(
        (await requests.query('SELECT reply FROM requests')).single['reply'],
        'A native reply',
      );
      final registration = fixtures['registration']!;
      await registration.query('UPDATE events SET capacity=1 WHERE id=1');
      await Future.wait([
        for (var user = 1; user <= 5; user++)
          registration.click('reg:join:1', user: user),
      ]);
      expect(
        (await registration.query(
          'SELECT count(*) AS n FROM registrations WHERE event_id=1',
        )).single['n'],
        1,
      );
      final crypto = fixtures['crypto']!;
      await crypto.command('prices');
      expect(crypto.messages.last, contains('Bitcoin'));
      crypto.transport.fail = true;
      await crypto.send(VirtEventType.command, 'prices', allowErrors: true);
      expect(crypto.messages.last, contains('Prices are unavailable'));
      final diagnostics = await store.data.diagnostics(tasks.id);
      binding.reportData = {
        'templates': fixtures.keys.toList(),
        'sqlite': diagnostics,
      };
      debugPrint(
        'TEMPLATES_NATIVE_RESULT ${jsonEncode({'platform': Platform.operatingSystem, ...binding.reportData!})}',
      );
    } finally {
      for (final h in fixtures.values) {
        await h.engine.close();
        h.console.dispose();
      }
      await store.close();
      await Hive.close();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
