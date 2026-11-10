import 'package:televerse/televerse.dart';
import 'package:televerse/telegram.dart';

import '../plugins/manifest.dart';
import 'registry.dart';

/// Host-owned chat navigation, independent of API automation and its receipts.
/// Only the public storefront origin is accepted; web sessions stay in Telegram.
class StorefrontPresentation {
  const StorefrontPresentation({
    required this.originField,
    required this.replacedAutomationIds,
  });

  final String originField;
  final Set<String> replacedAutomationIds;
  static const commands = ['start', 'shop', 'orders', 'help', 'products'];
  static const description =
      'Open the shop and your orders in Telegram. Sign in and check out on the shop website.';

  Iterable<AutomationDefinition> automationsFor(PluginManifest manifest) =>
      manifest.automations.where(
        (definition) => !replacedAutomationIds.contains(definition.id),
      );

  Uri? origin(Map<String, String> fields) {
    final value = fields[originField] ?? '';
    final uri = Uri.tryParse(value);
    if (value != value.trim() ||
        value.contains(RegExp(r'[\s\\]')) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.authority.contains(RegExp(r'[@%]')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return Uri.parse(uri.origin);
  }

  void register(Bot bot, Map<String, String> fields) {
    final shop = origin(fields);
    for (final command in commands) {
      bot.command(command, (context) async {
        try {
          if (context.chat?.type != ChatType.private) {
            await context.reply(
              'Open a private chat with this bot to visit the shop.',
            );
            return;
          }
          if (shop == null) {
            await context.reply(
              'The shop link is unavailable. The seller needs to configure the shop’s HTTPS address.',
            );
            return;
          }
          final orders = shop.replace(path: '/orders').toString();
          final keyboard = InlineKeyboard(
            inlineKeyboard: [
              [
                if (command != 'orders')
                  InlineKeyboardButton(
                    text: 'Open shop',
                    webApp: WebAppInfo(url: shop.toString()),
                  ),
                InlineKeyboardButton(
                  text: 'My orders',
                  webApp: WebAppInfo(url: orders),
                ),
              ],
            ],
          );
          await context.reply(
            command == 'help'
                ? 'Open the shop to browse and buy. Open My orders to see your purchases. '
                      'Sign in on the shop website if asked. Never send passwords or sign-in codes in this chat.'
                : command == 'orders'
                ? 'View your orders on the shop website. Sign in there if asked.'
                : 'Visit the shop or view your orders. Sign in on the shop website if asked.',
            replyMarkup: keyboard,
          );
        } catch (_) {
          // Do not pass SDK errors (which may include bot tokens) to logging
          // or the shared polling error handler and stop unrelated seller alerts.
        }
      });
    }
  }

  /// Menu setup is optional. Its failure must not stop replies or seller alerts.
  Future<bool> synchronizeMenu(Bot bot, Map<String, String> fields) async {
    final shop = origin(fields);
    if (shop == null) return false;
    try {
      return await bot.api
          .setChatMenuButton(
            MenuButton.webApp(
              text: 'Open shop',
              webApp: WebAppInfo(url: shop.toString()),
            ),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return false;
    }
  }
}
