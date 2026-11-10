import 'dart:io';
import 'dart:ui' as ui;
import 'package:bottogram/builder/engine.dart';
import 'package:bottogram/builder/step_editor.dart';
import 'package:bottogram/builder/text_editor.dart';
import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Telegram editor wraps selections and inserts a selected variable',
    (tester) async {
      final controller = TextEditingController(text: 'Secret');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TelegramTextEditor(
              controller: controller,
              references: const ['user.score'],
            ),
          ),
        ),
      );
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      await tester.tap(find.byTooltip('Spoiler'));
      await tester.pump();
      expect(controller.text, '||Secret||');
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.tap(find.byTooltip('Insert variable or step output'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('user.score'));
      await tester.pumpAndSettle();
      expect(controller.text, '||Secret||{{user.score}}');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('editor validates JSON before committing a request', (
    tester,
  ) async {
    BuilderStep? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: BottogramDesign.theme,
        home: BuilderStepEditor(
          initial: const BuilderStep('http', '', {
            'output': 'lookup',
            'url': 'https://example.com/api',
            'method': 'POST',
            'headers': '{}',
            'body': 'invalid',
          }),
          onSave: (value) async {
            saved = value;
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('Save action'));
    await tester.tap(find.text('Save action'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.textContaining('Invalid JSON.'), findsOneWidget);
  });

  for (final width in [390.0, 1100.0]) {
    for (final kind in ['reply', 'http']) {
      testWidgets('$kind editor fits at $width px', (tester) async {
        if (Platform.environment['CAPTURE_BUILDER_UI'] == '1') {
          await tester.runAsync(() async {
            final sdk = Platform.environment['FLUTTER_ROOT']!;
            for (final entry
                in {
                  'Host Grotesk': 'assets/fonts/HostGrotesk.ttf',
                  'Noto Sans Arabic': 'assets/fonts/NotoSansArabic.ttf',
                  'MaterialIcons':
                      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                }.entries) {
              final loader = FontLoader(entry.key)..addFont(
                Future.value(
                  ByteData.sublistView(await File(entry.value).readAsBytes()),
                ),
              );
              await loader.load();
            }
          });
        }
        await tester.binding.setSurfaceSize(Size(width, 900));
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: BottogramDesign.theme,
            home: RepaintBoundary(
              key: boundary,
              child: BuilderStepEditor(
                initial: BuilderStep(
                  kind,
                  '*Hello {{event.firstName}}*\nYour score: {{user.score}}',
                  {
                    'output': kind == 'http' ? 'lookup' : 'answer',
                    'format': 'MarkdownV2',
                    'url': 'https://api.example.com/users/{{event.userId}}',
                    'method': 'GET',
                  },
                ),
                references: const [
                  'event.firstName',
                  'user.score',
                  'steps.lookup.body.price',
                ],
                onSave: (_) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (Platform.environment['CAPTURE_BUILDER_UI'] == '1') {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('build/builder-ui/$kind-${width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.binding.setSurfaceSize(null);
      });
    }
  }
}
