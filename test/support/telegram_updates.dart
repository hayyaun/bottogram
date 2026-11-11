import 'package:televerse/telegram.dart' show Update;
import 'package:televerse/televerse.dart';

/// Drive registered middleware without starting a background polling loop.
extension FixtureUpdates on Bot<Context> {
  Future<void> dispatch(Update update) async {
    await handle(Context(update, api, botInfo));
  }
}
