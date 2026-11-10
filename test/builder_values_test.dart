import 'package:bottogram/builder/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final values = <String, dynamic>{
    'user': {'score': 12, 'name': 'A_[B].'},
    'steps': {
      'lookup': {
        'body': {
          'items': [
            {'price': 42},
          ],
        },
      },
    },
  };
  test(
    'named outputs support nested objects, list indices and typed JSON bindings',
    () {
      expect(
        BuilderValues.text(
          'Price: {{steps.lookup.body.items.0.price}}',
          values,
        ),
        'Price: 42',
      );
      expect(
        BuilderValues.json(
          '{"score":"{{user.score}}","label":"Score {{user.score}}"}',
          values,
        ),
        {'score': 12, 'label': 'Score 12'},
      );
    },
  );
  test(
    'missing and non-scalar values are errors, never silent empty strings',
    () {
      expect(
        () => BuilderValues.text('{{user.missing}}', values),
        throwsA(isA<BuilderFailure>()),
      );
      expect(
        () => BuilderValues.text('{{steps.lookup.body}}', values),
        throwsA(isA<BuilderFailure>()),
      );
      expect(
        () => BuilderValues.text('{{steps.lookup.body.items.2.price}}', values),
        throwsA(isA<BuilderFailure>()),
      );
    },
  );
  test('dynamic content is escaped for its MarkdownV2 context', () {
    expect(
      BuilderValues.text('*{{user.name}}*', values, markdown: true),
      r'*A\_\[B\]\.*',
    );
    expect(
      BuilderValues.text('`{{user.name}}`', values, markdown: true),
      '`A_[B].`',
    );
    expect(
      BuilderValues.text('```\n{{user.name}}\n```', values, markdown: true),
      '```\nA_[B].\n```',
    );
  });
  test(
    'malformed references fail and braces in actual values remain literal',
    () {
      expect(
        () => BuilderValues.text('{{bad-path}}', values),
        throwsA(isA<BuilderFailure>()),
      );
      expect(
        BuilderValues.text('{{event.text}}', {
          'event': {'text': '{{literal}}'},
        }),
        '{{literal}}',
      );
    },
  );
}
