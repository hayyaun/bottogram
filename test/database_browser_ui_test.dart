import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bottogram/builder/database_browser_page.dart';
import 'package:bottogram/builder/database_browser_source.dart';
import 'package:bottogram/ui/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class BrowserFixture implements DatabaseBrowserSource {
  final requests = <DatabaseRowsRequest>[];
  final counts = <String>[];
  bool fail = false;
  Completer<DatabaseRowsPage>? pending;
  @override
  Future<List<DatabaseTable>> tables() async {
    if (fail) {
      throw const DatabaseBrowseException('Database is busy. Try again.');
    }
    return const [
      DatabaseTable(name: 'scores'),
      DatabaseTable(name: '_bottogram_values', internal: true),
    ];
  }

  @override
  Future<int> count(String table) async {
    counts.add(table);
    return table == 'scores' ? 125 : 2;
  }

  @override
  Future<DatabaseTableSchema> schema(String table) async =>
      const DatabaseTableSchema(
        columns: [
          DatabaseColumn(name: 'user_id', type: 'INTEGER', primaryKey: 1),
          DatabaseColumn(name: 'name', type: 'TEXT'),
          DatabaseColumn(name: 'score', type: 'INTEGER'),
          DatabaseColumn(name: 'note', type: 'TEXT'),
        ],
        indexes: [
          DatabaseIndex(name: 'scores_score', columns: ['score']),
        ],
      );
  @override
  Future<DatabaseRowsPage> rows(DatabaseRowsRequest request) async {
    requests.add(request);
    if (pending != null) return pending!.future;
    return DatabaseRowsPage(
      columns: const ['user_id', 'name', 'score', 'note'],
      rows: List.generate(
        request.limit,
        (i) => {
          'user_id': request.offset + i + 1,
          'name': i == 0 ? 'Mina' : 'User ${request.offset + i + 1}',
          'score': 10 + i,
          'note': i == 0
              ? null
              : i == 1
              ? ''
              : 'A longer note for inspecting the complete cell value.',
        },
      ),
      hasMore: request.offset + request.limit < 125,
    );
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    Widget page, {
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.light,
    GlobalKey? boundary,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.dark
            ? BottogramDesign.darkTheme
            : BottogramDesign.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(key: boundary, child: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'table list shows lazy counts, internal labels and table search',
    (tester) async {
      final source = BrowserFixture();
      await open(
        tester,
        DatabaseBrowserPage(botName: 'Quiz bot', source: source),
      );
      expect(find.text('scores'), findsOneWidget);
      expect(find.text('125 rows'), findsOneWidget);
      expect(find.text('2 rows · Internal table'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'scores');
      await tester.pumpAndSettle();
      expect(find.text('_bottogram_values'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'scores'));
      await tester.pumpAndSettle();
      expect(find.text('Mina'), findsOneWidget);
      expect(find.byTooltip('Next page'), findsOneWidget);
    },
  );
  testWidgets('pagination, sorting and filtering send bounded page requests', (
    tester,
  ) async {
    final source = BrowserFixture();
    await open(
      tester,
      DatabaseTablePage(
        botName: 'Quiz bot',
        table: const DatabaseTable(name: 'scores'),
        source: source,
      ),
      width: 1100,
    );
    expect(source.requests.single.limit, 50);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(source.requests.last.offset, 50);
    await tester.tap(find.text('name').first);
    await tester.pumpAndSettle();
    expect(source.requests.last.sortColumn, 'name');
    expect(source.requests.last.offset, 0);
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(source.requests.last.filterColumn, 'user_id');
    expect(source.requests.last.filterValue, '12');
    await tester.tap(find.byTooltip('Clear filter'));
    await tester.pumpAndSettle();
    expect(source.requests.last.filterColumn, isNull);
  });
  testWidgets('cell details and table structure distinguish data and schema', (
    tester,
  ) async {
    final source = BrowserFixture();
    await open(
      tester,
      DatabaseTablePage(
        botName: 'Quiz bot',
        table: const DatabaseTable(name: 'scores'),
        source: source,
      ),
      width: 1100,
    );
    expect(find.text('NULL'), findsOneWidget);
    expect(find.text('(empty text)'), findsOneWidget);
    await tester.tap(find.text('Mina'));
    await tester.pumpAndSettle();
    expect(find.text('TEXT · 4 characters'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Table structure'));
    await tester.pumpAndSettle();
    expect(find.text('scores · Structure'), findsOneWidget);
    expect(find.text('scores_score'), findsOneWidget);
  });
  testWidgets(
    'recoverable errors expose retry without stale exception details',
    (tester) async {
      final source = BrowserFixture()..fail = true;
      await open(
        tester,
        DatabaseBrowserPage(botName: 'Quiz bot', source: source),
      );
      expect(find.text('Database is busy. Try again.'), findsOneWidget);
      source.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('scores'), findsOneWidget);
    },
  );
  testWidgets('late page completions cannot overwrite a newer filter result', (
    tester,
  ) async {
    final source = BrowserFixture();
    await open(
      tester,
      DatabaseTablePage(
        botName: 'Quiz bot',
        table: const DatabaseTable(name: 'scores'),
        source: source,
      ),
      width: 1100,
    );
    final blocked = Completer<DatabaseRowsPage>();
    source.pending = blocked;
    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    source.pending = null;
    await tester.tap(find.text('Filter'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '42');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    blocked.complete(
      const DatabaseRowsPage(
        columns: ['name'],
        rows: [
          {'name': 'stale response'},
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('stale response'), findsNothing);
    expect(find.text('Mina'), findsOneWidget);
  });
  for (final width in [390.0, 1100.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('browser renders at $width px in $brightness', (
        tester,
      ) async {
        final boundary = GlobalKey();
        if (Platform.environment['CAPTURE_DATABASE_BROWSER_UI'] == '1') {
          await tester.runAsync(() async {
            final sdk = Platform.environment['FLUTTER_ROOT']!;
            for (final entry in {
              'Host Grotesk': 'assets/fonts/HostGrotesk.ttf',
              'Noto Sans Arabic': 'assets/fonts/NotoSansArabic.ttf',
              'MaterialIcons':
                  '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              final loader = FontLoader(entry.key)
                ..addFont(
                  Future.value(
                    ByteData.sublistView(await File(entry.value).readAsBytes()),
                  ),
                );
              await loader.load();
            }
          });
        }
        await open(
          tester,
          DatabaseTablePage(
            botName: 'Quiz bot',
            table: const DatabaseTable(name: 'scores'),
            source: BrowserFixture(),
          ),
          width: width,
          scale: width == 390 ? 1.3 : 1,
          brightness: brightness,
          boundary: boundary,
        );
        expect(tester.takeException(), isNull);
        if (Platform.environment['CAPTURE_DATABASE_BROWSER_UI'] == '1') {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/database-browser-ui/${width.toInt()}-${brightness.name}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }
  }
}
