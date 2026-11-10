import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bottogram/pages/create_bot.dart';
import 'package:bottogram/main.dart' show MyApp;
import 'package:bottogram/pages/home.dart';
import 'package:bottogram/pages/bot.dart';
import 'package:bottogram/inbox/users_page.dart';
import 'package:bottogram/widgets/bot_card.dart';
import 'package:bottogram/plugins/parameters_form.dart';
import 'package:bottogram/plugins/manifest.dart';
import 'package:bottogram/plugins/plugins_page.dart';
import 'package:bottogram/plugins/repository.dart';
import 'package:bottogram/plugins/secret_vault.dart';
import 'package:bottogram/plugins/bot_setup.dart';
import 'package:bottogram/plugins/setting.dart';
import 'package:bottogram/plugins/settings_form.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:bottogram/ui/design.dart';
import 'package:bottogram/ui/theme_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart' show ChangeNotifierProvider;
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class MemoryVault implements SecretVault {
  final values = <String, String>{};
  bool failWrite = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('Storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class TestContext extends Fake implements BuildContext {}

Map<String, dynamic> definition() =>
    jsonDecode(
          File(
            'examples/plugins/inshopa.bottogram-plugin.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

PluginManifest package([Map<String, dynamic>? data]) => PluginManifest.parse(
  Uint8List.fromList(utf8.encode(jsonEncode(data ?? definition()))),
);

class MemoryCatalog extends PluginRepository {
  MemoryCatalog() : super(vault: MemoryVault());
  final entries = <PluginManifest>[];
  @override
  Future<void> get ready async {}
  @override
  List<PluginManifest> get installed => List.of(entries);
  @override
  int dependents(String key) => 0;
  @override
  Future<void> install(PluginManifest manifest) async {
    entries.add(manifest);
    notifyListeners();
  }
}

class TestPicker extends FilePickerPlatform {
  TestPicker(this.file);
  final PlatformFile? file;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => file;
}

final class TestPickedFile extends PlatformFile {
  TestPickedFile(List<int> bytes, {this.knownLength = true})
    : bytes = Uint8List.fromList(bytes);
  final Uint8List bytes;
  final bool knownLength;

  @override
  String get name => 'inshopa.bottogram-plugin.json';
  @override
  Uri get uri => Uri.dataFromBytes(bytes);
  @override
  XFile get xFile => XFile.fromData(bytes, name: name);
  @override
  int? lengthSync() => knownLength ? bytes.length : null;
  @override
  Future<int?> length() async => lengthSync();
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MemoryVault vault;
  late PluginRepository repository;
  late BotsCubit bots;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bottogram_plugins_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(VirtBotAdapter());
      Hive.registerAdapter(VirtEventAdapter());
      Hive.registerAdapter(VirtEventTypeAdapter());
      Hive.registerAdapter(VirtActAdapter());
      Hive.registerAdapter(VirtActTypeAdapter());
      Hive.registerAdapter(VirtRMUKeyboardAdapter());
      Hive.registerAdapter(VirtRMUInlineKeyboardAdapter());
      Hive.registerAdapter(KeyValueAdapter());
    }
    vault = MemoryVault();
    repository = PluginRepository(vault: vault, bundledAssets: const []);
    await repository.ready;
    bots = BotsCubit(TestContext(), plugins: repository);
    await bots.ready;
  });

  tearDown(() async {
    await bots.close();
    repository.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'full app starts with the notifying plugin repository and bundled Inshopa',
    (tester) async {
      late PluginRepository appRepository;
      await tester.runAsync(() async {
        await tester.pumpWidget(const MyApp());
        final homeContext = tester.element(find.byType(HomePage));
        await homeContext.read<ThemePreferences>().ready;
        appRepository = homeContext.read<PluginRepository>();
        final appBots = homeContext.read<BotsCubit>();
        await appRepository.ready;
        await appBots.ready;
      });
      await tester.pumpAndSettle();
      expect(find.text('Bottogram'), findsOneWidget);
      expect(
        appRepository.installed.any((p) => p.id == 'bottogram-plugin-inshopa'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  test(
    'template writes during startup persist and survive reopening',
    () async {
      final store = RMUsCubit();
      await Future.wait([
        store.add(
          VirtRMUKeyboard()
            ..name = 'First'
            ..items = ['A', null, 'B'],
        ),
        store.add(
          VirtRMUInlineKeyboard()
            ..name = 'Second'
            ..items = [KeyValue('Go', 'go')],
        ),
      ]);
      expect(store.state.length, 2);
      await store.close();
      await Hive.box<dynamic>(RMUsCubit.boxName).close();
      final reopened = RMUsCubit();
      await reopened.ready;
      expect(reopened.state.map((rmu) => rmu.name), ['First', 'Second']);
      expect((reopened.state.first as VirtRMUKeyboard).items, ['A', null, 'B']);
      await reopened.remove(reopened.state.first);
      expect(Hive.box<dynamic>(RMUsCubit.boxName).length, 1);
      await reopened.reset();
      expect(Hive.box<dynamic>(RMUsCubit.boxName).isEmpty, isTrue);
      await reopened.close();
    },
  );

  test('Inshopa declares only its key and requests the common admin field', () {
    final plugin = package();
    expect(plugin.fields.single.key, 'apiKey');
    expect(plugin.fields.single.type, PluginFieldType.secret);
    expect(plugin.requiresAdmin, isTrue);
    expect(plugin.settings.single.type, PluginSettingType.boolean);
    expect(plugin.settings.single.defaultValue, isTrue);
    expect(plugin.settings.single.label, 'آگاه شدن از آخرین خرید های موفق');
  });

  test(
    'rejects unknown engines, executable properties, shared-field duplicates and secret defaults',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d['engine'] = 'downloaded-code',
        (d) => d['script'] = 'some code',
        (d) => d['executionStatus'] = 'ready',
        (d) => (d['setupFields'] as List).first['key'] = 'adminTelegramUserId',
        (d) =>
            (d['setupFields'] as List).first['default'] =
                'never-package-a-secret',
        (d) => (d['setupFields'] as List).add(
          Map.of((d['setupFields'] as List).first),
        ),
      ]) {
        final data = definition();
        change(data);
        expect(() => package(data), throwsA(isA<PluginException>()));
      }
      expect(
        () => PluginManifest.parse(Uint8List(maxPluginBytes + 1)),
        throwsA(isA<PluginException>()),
      );
      expect(
        () => PluginManifest.parse(Uint8List.fromList([255])),
        throwsA(isA<PluginException>()),
      );
    },
  );

  test(
    'catalog persists and rejects replacements under an installed version',
    () async {
      final plugin = package();
      await repository.install(plugin);
      await expectLater(
        () => repository.install(plugin),
        throwsA(isA<PluginException>()),
      );
      await expectLater(
        () =>
            repository.install(package(definition()..['name'] = 'Replacement')),
        throwsA(isA<PluginException>()),
      );
      await Hive.close();
      final reopened = PluginRepository(vault: vault, bundledAssets: const []);
      await reopened.ready;
      expect(reopened.installed.single.digest, plugin.digest);
      reopened.dispose();
    },
  );

  test(
    'creation persists common settings; secrets stay outside Hive and bots remain isolated',
    () async {
      final plugin = package();
      await repository.install(plugin);
      for (var i = 1; i <= 2; i++) {
        await bots.create(
          name: 'Shop $i',
          token: '$i:testing',
          adminId: '$i',
          plugin: plugin,
          parameters: {'apiKey': 'test-secret-$i'},
        );
      }
      final first = bots.state.first;
      final second = bots.state.last;
      expect(first.events, isEmpty);
      expect(first.setup!.instanceId, isNot(second.setup!.instanceId));
      expect(
        vault.values.values,
        containsAll(['test-secret-1', 'test-secret-2']),
      );
      expect(
        Hive.box<dynamic>('bot_setups_v1').values.toString(),
        isNot(contains('test-secret-')),
      );
      expect(
        (await repository.setupFor(
          first.key,
          first.token,
        ))!.adminTelegramUserId,
        '1',
      );
      await expectLater(first.start(), throwsA(isA<PluginException>()));
      await expectLater(
        repository.uninstall(plugin.storageKey),
        throwsA(isA<PluginException>()),
      );
      await expectLater(
        bots.create(name: 'Duplicate', token: '1:testing', adminId: '1'),
        throwsA(isA<PluginException>()),
      );
    },
  );

  test('failed secure write leaves no bot, key, or pending setup', () async {
    final plugin = package();
    await repository.install(plugin);
    vault.failWrite = true;
    await expectLater(
      bots.create(
        name: 'Shop',
        token: '123:testing',
        adminId: '1',
        plugin: plugin,
        parameters: {'apiKey': 'test-key'},
      ),
      throwsA(isA<PluginException>()),
    );
    expect(bots.state, isEmpty);
    expect(vault.values, isEmpty);
    expect(Hive.box<dynamic>('bot_setups_v1').isEmpty, isTrue);
  });

  test(
    'parameter edits keep secrets private and preserve the committed setup on failure',
    () async {
      final plugin = package();
      await repository.install(plugin);
      await bots.create(
        name: 'Shop',
        token: '123:testing',
        adminId: '1',
        plugin: plugin,
        parameters: {'apiKey': 'original-secret'},
      );
      final bot = bots.state.single;
      final original = bot.setup!;
      await bots.updatePluginParameters(
        bot,
        adminId: '1',
        parameters: {'apiKey': ''},
      );
      expect(bot.setup!.instanceId, original.instanceId);
      vault.failWrite = true;
      await expectLater(
        bots.updatePluginParameters(
          bot,
          adminId: '2',
          parameters: {'apiKey': 'replacement-secret'},
        ),
        throwsA(isA<PluginException>()),
      );
      expect(
        (await repository.setupFor(bot.key, bot.token))!.instanceId,
        original.instanceId,
      );
      expect(await vault.read(original.secretKey('apiKey')), 'original-secret');
      vault.failWrite = false;
      await bots.updatePluginParameters(
        bot,
        adminId: '2',
        parameters: {'apiKey': ''},
      );
      expect(bot.setup!.instanceId, isNot(original.instanceId));
      expect(bot.setup!.adminTelegramUserId, '2');
      expect(
        await vault.read(bot.setup!.secretKey('apiKey')),
        'original-secret',
      );
      await bots.updatePluginParameters(
        bot,
        adminId: '2',
        parameters: {'apiKey': 'replacement-secret'},
      );
      expect(
        await vault.read(bot.setup!.secretKey('apiKey')),
        'replacement-secret',
      );
      expect(vault.values.length, 1);
      expect(
        Hive.box<dynamic>('bot_setups_v1').values.toString(),
        isNot(contains('replacement-secret')),
      );
    },
  );

  testWidgets(
    'all cards open users separately from settings; mobile plus opens creation',
    (tester) async {
      final plugin = package();
      await tester.runAsync(() async {
        await repository.install(plugin);
        await bots.create(
          name: 'Plugin shop',
          token: '1:testing',
          adminId: '1',
          plugin: plugin,
          parameters: {'apiKey': 'saved-test-key'},
        );
        await bots.create(
          name: 'Manual shop',
          token: '2:testing',
          adminId: '1',
        );
      });
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> settle() async {
        await tester.runAsync(() async {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
      }

      final captureKey = GlobalKey();
      if (Platform.environment['CAPTURE_PLUGIN_UI'] == '1') {
        await tester.runAsync(() async {
          for (final family in [
            'Host Grotesk',
            'Noto Sans Arabic',
            'MaterialIcons',
          ]) {
            final path =
                family == 'MaterialIcons'
                    ? '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
                    : 'assets/fonts/${family == 'Host Grotesk' ? 'HostGrotesk' : 'NotoSansArabic'}.ttf';
            final loader = FontLoader(family)..addFont(
              Future.value(
                ByteData.sublistView(await File(path).readAsBytes()),
              ),
            );
            await loader.load();
          }
        });
      }
      Future<void> capture(String name) async {
        if (Platform.environment['CAPTURE_PLUGIN_UI'] != '1') return;
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/verification/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MultiRepositoryProvider(
            providers: [
              ChangeNotifierProvider<PluginRepository>.value(value: repository),
              BlocProvider<BotsCubit>.value(value: bots),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              builder:
                  (_, child) => RepaintBoundary(key: captureKey, child: child!),
              theme: BottogramDesign.theme,
              home: const HomePage(title: 'Bottogram'),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle();
      expect(find.byType(FloatingActionButton), findsNothing);
      await capture('mobile-bot-navigation');
      final plus = find.byTooltip('Create bot');
      expect(plus, findsOneWidget);
      expect(tester.getCenter(plus).dx, closeTo(195, 1));
      await tester.tap(plus);
      await settle();
      expect(find.byType(CreateBotPage), findsOneWidget);
      await tester.pageBack();
      await settle();
      for (final name in ['Plugin shop', 'Manual shop']) {
        await tester.ensureVisible(find.text(name));
        await tester.tap(find.text(name));
        await settle();
        expect(find.byType(InboxUsersPage), findsOneWidget);
        await tester.pageBack();
        await settle();
        final card = find.ancestor(
          of: find.text(name),
          matching: find.byType(BotCard),
        );
        final settings = find.descendant(
          of: card,
          matching: find.byTooltip('Bot settings'),
        );
        await tester.ensureVisible(settings);
        await tester.tap(settings);
        await settle();
        expect(find.byType(BotPage), findsOneWidget);
        expect(find.byType(PluginParametersForm), findsNothing);
        if (name == 'Plugin shop') {
          await tester.tap(find.byTooltip('Edit parameters'));
          await settle();
          expect(find.byType(PluginParametersForm), findsOneWidget);
          await capture('plugin-parameter-editor');
          final keyField = tester.widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Inshopa API key'),
          );
          expect(keyField.controller!.text, isEmpty);
          await tester.pageBack();
          await settle();
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'startup discards abandoned setup and recovers one saved before attachment',
    () async {
      final plugin = package();
      await repository.install(plugin);
      await repository.prepare(
        token: '1:abandoned',
        adminId: '1',
        plugin: plugin,
        parameters: {'apiKey': 'abandoned-test-key'},
      );
      await repository.reconcile({});
      expect(vault.values, isEmpty);
      final prepared = await repository.prepare(
        token: '2:saved',
        adminId: '2',
        plugin: plugin,
        parameters: {'apiKey': 'recoverable-test-key'},
      );
      final key = await Hive.box<VirtBot>(
        'botsbox',
      ).add(VirtBot('Saved', '2:saved', addSamples: false));
      await repository.reconcile({key: '2:saved'});
      expect(
        (await repository.setupFor(key, '2:saved'))!.instanceId,
        prepared.instanceId,
      );
      expect(vault.values.values, contains('recoverable-test-key'));
      expect(
        Hive.box<dynamic>(
          'bot_setups_v1',
        ).containsKey('pending:${prepared.instanceId}'),
        isFalse,
      );
    },
  );

  test(
    'legacy records remain manual; new manual admin and edits survive reopening',
    () async {
      final old = VirtBot('Legacy', '1:legacy');
      final key = await Hive.box<VirtBot>('botsbox').add(old);
      expect(await repository.setupFor(key, old.token), isNull);
      await bots.create(name: 'Manual', token: '2:manual', adminId: '123');
      final created = bots.state.single;
      expect(created.setup!.usesPlugin, isFalse);
      expect(created.events, hasLength(3));
      created.name = 'Renamed';
      await created.save();
      await Hive.close();
      final reloadedRepository = PluginRepository(
        vault: vault,
        bundledAssets: const [],
      );
      final box = await Hive.openBox<VirtBot>('botsbox');
      expect(box.values.last.name, 'Renamed');
      expect(
        (await reloadedRepository.setupFor(
          box.values.last.key,
          '2:manual',
        ))!.adminTelegramUserId,
        '123',
      );
      reloadedRepository.dispose();
    },
  );

  test(
    'deleting a plugin bot removes its secrets and releases the pinned package',
    () async {
      final plugin = package();
      await repository.install(plugin);
      await bots.create(
        name: 'Shop',
        token: '1:testing',
        adminId: '1',
        plugin: plugin,
        parameters: {'apiKey': 'delete-test-key'},
      );
      await bots.remove(bots.state.single);
      expect(vault.values, isEmpty);
      await repository.uninstall(plugin.storageKey);
      expect(repository.installed, isEmpty);
    },
  );

  testWidgets(
    'one creation form adds only plugin fields and preserves common inputs when switching',
    (tester) async {
      final catalog = MemoryCatalog()..entries.add(package());
      addTearDown(catalog.dispose);
      final other =
          definition()
            ..['id'] = 'another-plugin'
            ..['name'] = 'Other';
      other['setupFields'] = [
        {'key': 'region', 'label': 'Region', 'type': 'text', 'required': true},
      ];
      catalog.entries.add(package(other));
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundaryKey = GlobalKey();
      if (Platform.environment['CAPTURE_PLUGIN_UI'] == '1') {
        await tester.runAsync(() async {
          final sdk = Platform.environment['FLUTTER_ROOT']!;
          for (final entry
              in {
                'Host Grotesk': 'HostGrotesk.ttf',
                'Noto Sans Arabic': 'NotoSansArabic.ttf',
                'MaterialIcons': 'MaterialIcons-Regular.otf',
              }.entries) {
            final data =
                await File(
                  entry.key == 'MaterialIcons'
                      ? '$sdk/bin/cache/artifacts/material_fonts/${entry.value}'
                      : 'assets/fonts/${entry.value}',
                ).readAsBytes();
            final loader = FontLoader(entry.key)
              ..addFont(Future.value(ByteData.sublistView(data)));
            await loader.load();
          }
        });
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: BottogramDesign.theme,
            home: CreateBotPage(bots: bots, plugins: catalog),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        if (Platform.environment['CAPTURE_PLUGIN_UI'] != '1') return;
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/verification').create(recursive: true);
          await File(
            'build/verification/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('create-bot-manual');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Bot name'),
        'My shop',
      );
      expect(find.text('Inshopa API key'), findsNothing);
      await tester.ensureVisible(find.text('Manual'));
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inshopa · 0.2.0').last);
      await tester.pumpAndSettle();
      expect(find.text('Inshopa API key'), findsOneWidget);
      expect(find.text('Admin Telegram ID'), findsOneWidget);
      expect(find.text('Shop ID'), findsNothing);
      await capture('create-bot-inshopa');
      await tester.tap(find.text('Inshopa · 0.2.0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other · 0.2.0').last);
      await tester.pumpAndSettle();
      expect(find.text('Inshopa API key'), findsNothing);
      expect(find.text('Region'), findsOneWidget);
      expect(find.text('My shop'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'file import requires review and then adds the package to the catalog',
    (tester) async {
      final catalog = MemoryCatalog();
      final previousPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = TestPicker(
        TestPickedFile(utf8.encode(jsonEncode(definition()))),
      );
      addTearDown(() {
        FilePickerPlatform.instance = previousPicker;
        catalog.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(home: PluginsPage(repository: catalog)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Install from file'));
      await tester.pumpAndSettle();
      expect(find.text('Install Inshopa?'), findsOneWidget);
      expect(catalog.installed, isEmpty);
      await tester.tap(find.text('Install').last);
      await tester.pumpAndSettle();
      expect(catalog.installed.single.id, 'bottogram-plugin-inshopa');
      expect(find.textContaining('Version 0.2.0 · Setup only'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('canceling plugin file import leaves the catalog unchanged', (
    tester,
  ) async {
    final catalog = MemoryCatalog();
    final previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = TestPicker(null);
    addTearDown(() {
      FilePickerPlatform.instance = previousPicker;
      catalog.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: PluginsPage(repository: catalog)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install from file'));
    await tester.pumpAndSettle();
    expect(catalog.installed, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final knownLength in [true, false]) {
    testWidgets(
      'plugin import limits oversized files with ${knownLength ? 'known' : 'unknown'} length',
      (tester) async {
        final catalog = MemoryCatalog();
        final previousPicker = FilePickerPlatform.instance;
        FilePickerPlatform.instance = TestPicker(
          TestPickedFile(
            Uint8List(maxPluginBytes + 1),
            knownLength: knownLength,
          ),
        );
        addTearDown(() {
          FilePickerPlatform.instance = previousPicker;
          catalog.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(home: PluginsPage(repository: catalog)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Install from file'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            knownLength
                ? 'Choose a readable JSON plugin file up to 256 KiB.'
                : 'The plugin file exceeds 256 KiB.',
          ),
          findsOneWidget,
        );
        expect(catalog.installed, isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'bundled Inshopa appears without import, seeds once, and respects ordinary uninstall',
    () async {
      final bundled = PluginRepository(vault: vault);
      await bundled.ready;
      expect(bundled.installed.map((p) => p.id).toSet(), {
        'bottogram-plugin-inshopa',
      });
      expect(bundled.installed.single.version, '0.7.1');
      expect(bundled.installed.single.executable, isTrue);
      final reopened = PluginRepository(vault: vault);
      await reopened.ready;
      expect(reopened.installed, hasLength(1));
      for (final plugin in reopened.installed) {
        await reopened.uninstall(plugin.storageKey);
      }
      final afterUninstall = PluginRepository(vault: vault);
      await afterUninstall.ready;
      expect(afterUninstall.installed, isEmpty);
      bundled.dispose();
      reopened.dispose();
      afterUninstall.dispose();
    },
  );

  test(
    'bundling preserves existing versions and different bytes under the bundled version',
    () async {
      final old = package(definition()..['version'] = '0.1.0');
      final local = package(
        (jsonDecode(
                File(
                  'examples/plugins/inshopa.storefront.bottogram-plugin.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)
          ..['name'] = 'Locally installed definition',
      );
      await repository.install(old);
      await repository.install(local);
      final bundled = PluginRepository(vault: vault);
      await bundled.ready;
      expect(bundled.installed, hasLength(2));
      expect(
        bundled.installed.map((p) => p.digest),
        containsAll([old.digest, local.digest]),
      );
      bundled.dispose();
    },
  );

  Map<String, dynamic> mixedSettings() =>
      definition()
        ..['settings'] = [
          {
            'key': 'enabled',
            'label': 'Enabled',
            'type': 'boolean',
            'default': true,
          },
          {
            'key': 'prefix',
            'label': 'Prefix',
            'type': 'string',
            'default': 'Shop',
            'minLength': 1,
            'maxLength': 20,
          },
          {
            'key': 'count',
            'label': 'Count',
            'type': 'integer',
            'default': 2,
            'min': 1,
            'max': 10,
          },
          {
            'key': 'ratio',
            'label': 'Ratio',
            'type': 'number',
            'default': 1.5,
            'min': 0,
            'max': 2,
          },
          {
            'key': 'mode',
            'label': 'Mode',
            'type': 'enum',
            'default': 'normal',
            'options': [
              {'value': 'normal', 'label': 'Normal'},
              {'value': 'fast', 'label': 'Fast'},
            ],
          },
        ];

  test(
    'typed settings support text, booleans, bounded numbers and enum choices',
    () {
      final manifest = package(mixedSettings());
      final defaults = manifest.settingValues(const {});
      expect(defaults, {
        'enabled': true,
        'prefix': 'Shop',
        'count': 2,
        'ratio': 1.5,
        'mode': 'normal',
      });
      expect(manifest.settings[2].validate(11), isNotNull);
      expect(manifest.settings[3].validate(double.infinity), isNotNull);
      expect(manifest.settings[4].validate('missing'), isNotNull);
      expect(
        () => manifest.settingValues({'enabled': 'true'}),
        throwsA(isA<PluginException>()),
      );
      expect(
        () => manifest.settingValues({'unknown': false}),
        throwsA(isA<PluginException>()),
      );
    },
  );

  test(
    'setting schema rejects invalid types, defaults, collisions and bounds',
    () {
      for (final setting in [
        {
          'key': 'enabled',
          'label': 'Enabled',
          'type': 'boolean',
          'default': 'true',
        },
        {
          'key': 'enabled',
          'label': 'Enabled',
          'type': 'secret',
          'default': 'credential',
        },
        {
          'key': 'apiKey',
          'label': 'Duplicate',
          'type': 'string',
          'default': '',
        },
        {'key': 'enabled', 'label': 'Enabled', 'type': 'boolean'},
        {'key': 'count', 'label': 'Count', 'type': 'integer', 'default': 1.5},
        {
          'key': 'count',
          'label': 'Count',
          'type': 'integer',
          'default': 1,
          'min': 2,
          'max': 1,
        },
        {
          'key': 'text',
          'label': 'Text',
          'type': 'string',
          'default': '',
          'minLength': 1,
        },
        {
          'key': 'choice',
          'label': 'Choice',
          'type': 'enum',
          'default': 'other',
          'options': [
            {'value': 'one', 'label': 'One'},
          ],
        },
      ]) {
        expect(
          () => package(definition()..['settings'] = [setting]),
          throwsA(isA<PluginException>()),
        );
      }
      final duplicate = definition();
      (duplicate['settings'] as List).add(
        Map.of((duplicate['settings'] as List).single),
      );
      expect(() => package(duplicate), throwsA(isA<PluginException>()));
    },
  );

  test(
    'notification settings persist per bot without changing keys or other bots',
    () async {
      final plugin = package();
      await repository.install(plugin);
      for (var i = 1; i <= 2; i++) {
        await bots.create(
          name: 'Shop $i',
          token: '$i:settings',
          adminId: '$i',
          plugin: plugin,
          parameters: {'apiKey': 'setting-test-key-$i'},
        );
      }
      final first = bots.state.first;
      final second = bots.state.last;
      const preference = 'notifyNewSuccessfulPurchases';
      expect(first.setup!.settings[preference], isTrue);
      final keys = Map.of(vault.values);
      await bots.updatePluginSettings(first, {preference: false});
      expect(first.setup!.settings[preference], isFalse);
      expect(second.setup!.settings[preference], isTrue);
      expect(vault.values, keys);
      await expectLater(
        bots.updatePluginSettings(first, {preference: 'false'}),
        throwsA(isA<PluginException>()),
      );
      expect(
        (await repository.setupFor(
          first.key,
          first.token,
        ))!.settings[preference],
        isFalse,
      );
      final key = first.key;
      await Hive.close();
      final reopened = PluginRepository(vault: vault, bundledAssets: const []);
      expect(
        (await reopened.setupFor(key, first.token))!.settings[preference],
        isFalse,
      );
      reopened.dispose();
    },
  );

  test(
    'older setup records use declared defaults without a backfill',
    () async {
      final plugin = package();
      await repository.install(plugin);
      await bots.create(
        name: 'Shop',
        token: '1:legacy-settings',
        adminId: '1',
        plugin: plugin,
        parameters: {'apiKey': 'legacy-setting-test-key'},
      );
      final bot = bots.state.single;
      final raw = Map<dynamic, dynamic>.of(
        Hive.box<dynamic>('bot_setups_v1').get(bot.key) as Map,
      )..remove('settings');
      await Hive.box<dynamic>('bot_setups_v1').put(bot.key, raw);
      final setup = await repository.setupFor(bot.key, bot.token);
      expect(setup!.settings, isEmpty);
      expect(
        plugin.settingValues(setup.settings)['notifyNewSuccessfulPurchases'],
        isTrue,
      );
      expect(
        (Hive.box<dynamic>('bot_setups_v1').get(bot.key) as Map).containsKey(
          'settings',
        ),
        isFalse,
      );
      expect(BotSetup.fromMap(raw).settings, isEmpty);
    },
  );

  testWidgets('generic settings editor validates and saves typed values', (
    tester,
  ) async {
    final manifest = package(mixedSettings());
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PluginSettingsForm(
              definitions: manifest.settings,
              values: manifest.settingValues(const {}),
              onSave: (values) async {
                saved = values;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prefix'),
      'Seller',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Count'), '99');
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('Maximum: 10.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Count'), '3');
    await tester.ensureVisible(find.text('Normal'));
    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fast').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(saved, {
      'enabled': false,
      'prefix': 'Seller',
      'count': 3,
      'ratio': 1.5,
      'mode': 'fast',
    });
    expect(find.text('Settings saved.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
