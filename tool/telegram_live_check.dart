import 'dart:convert';
import 'dart:io';
import 'package:televerse/televerse.dart';

/// Owner-authorized read checks. A private file path is the only CLI argument.
/// Never serialize SDK exceptions: their URLs may contain the bot token.
Future<void> main(List<String> arguments) async {
  Bot? bot;
  final report = <String, dynamic>{'telegram_identity_verified': false};
  try {
    if (arguments.length != 1) {
      throw StateError('A private connection file is required.');
    }
    Map<String, dynamic> credentials;
    try {
      credentials =
          jsonDecode(await File(arguments.single).readAsString())
              as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Private connection data could not be read.');
    }
    bot = Bot(credentials['telegram_token'] as String);
    final me = await bot.api.getMe().timeout(const Duration(seconds: 22));
    report.addAll({
      'telegram_identity_verified': true,
      'bot_id': me.id,
      'bot_username': me.username,
    });
    try {
      await bot.api
          .getChat(
            ID.create(
              int.parse(credentials['admin_telegram_user_id'] as String),
            ),
          )
          .timeout(const Duration(seconds: 15));
      report['admin_chat_available'] = true;
    } catch (error) {
      report['admin_chat_available'] = false;
      report['admin_check_error_type'] = error.runtimeType.toString();
      if (error is TelegramException) {
        report['admin_check_error_code'] = error.code;
      }
    }
  } catch (error) {
    report['error_type'] = error.runtimeType.toString();
    if (error is TelegramException) report['error_code'] = error.code;
    exitCode = 1;
  } finally {
    bot?.api.closeClient();
  }
  await File(
    'build/verification/telegram-live-check.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  stdout.writeln(jsonEncode(report));
}
