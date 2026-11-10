# Storefront navigation

Implemented 2026-11-10. Bottogram opens the existing Inshopa storefront directly
in Telegram's web view. There is no Inshopa source, API, page, authentication,
database, or configuration change.

## Chat behavior

- `/start` and `/shop`: a short reply with **Open shop** and **My orders**.
- `/orders`: a short reply with **My orders**, opening the existing `/orders` page.
- `/help`: brief website sign-in guidance and the same navigation buttons.
- `/products`, including the previous page argument, is a shop-launcher alias.
  It no longer fetches or duplicates products in chat.
- Groups receive a request to use a private chat, without Mini App buttons.

The supported Televerse `InlineKeyboardButton.webApp`, `WebAppInfo`, and
`MenuButton.webApp` APIs supply the launchers. A default **Open shop** menu button
is synchronized when a supported bot starts. Failure to configure that optional
menu does not stop chat replies or paid-order alerts. Command reply failures do
not reach the shared polling error handler or expose SDK exception URLs.

Already-sent Mini App buttons and a configured menu launch the hosted website
without a fresh reply from Bottogram. They still need Telegram, the website, and
a working connection. New command replies and seller alerts require the bot to
be running. Stopping or deleting a bot does not revoke previously sent website
buttons or the configured Telegram menu.

## Supported packages and saved state

`lib/plugins/bundled_presentations.dart` is the explicit host presentation registry.
It binds exact SHA-256 source digests of the shipped Inshopa 0.5.0 production/local
sales packages and the earlier 0.4.0 production/0.3.0 local catalog packages to a
generic `StorefrontPresentation`. The lifecycle coordinator uses the presentation
interface without product-specific conditions. Package authors cannot activate
this binding by copying an ID or version. Modified imports are not silently
reinterpreted; future supported packages require an explicit registry entry.

The presentation registers navigation commands instead of starting the original
`products` automation. Every other automation definition is used unchanged.
Catalog-only packages do not acquire alerts; version 0.2.0 stays setup-only.
No installed package bytes or setup records are changed, and no package upgrade
or database migration is performed. The existing instance ID, token fingerprint,
package key and digest, secret references, admin ID, storefront, preferences and
API destinations are preserved.

Paid-order progress continues under the original
`instanceId:manifestDigest:paid-orders` key. Its baseline, pending event/action
index, page continuation and durable delivery receipts are retained. The original
preference controls whether its runner starts. No new baseline is introduced.
The current-state polling and ambiguous-delivery limitations described in
[Plugin runtime](PLUGIN_RUNTIME.md) still apply.

Host changes take effect on the next normal Start for a bot. Flutter hot reload
keeps existing sessions and their already-registered handlers alive; it does not
retroactively install startup handlers. Do not hot restart or stop active bots
solely to activate this presentation when their running state must be preserved.

## Website and privacy boundary

Only the existing public `storefrontUrl` field is read by the presentation. It
must be an HTTPS origin, optionally with a root slash and port, without userinfo,
query, fragment, or a page path. Invalid values produce a generic unavailable-link
reply without echoing the configured value. They do not disable seller alerts.
The two URLs are that origin and the same origin with `/orders`. Bottogram makes
no HTTP request to those page URLs and adds no credentials or buyer identifiers.

Telegram hosts the buyer's browser environment. Inshopa handles its existing
login flow, cookies, session validity, cart and checkout. Telegram identity is
not an authenticated Inshopa account. This feature implements no OTP/password
collection, account linking, page proxy, wrapper, session relay, Telegram Login,
`sendData`, or `answerWebAppQuery` flow. It does not fetch order history with the
seller key and requires no `storefront:buyer` permission. Existing seller scopes
remain necessary for the unchanged shop lookup and paid-order polling.

The existing inbox still retains ordinary private Telegram messages and user
identities, including text a buyer voluntarily sends. Existing seller order
events and outgoing admin summaries can also be retained. The guarantee is that
website authentication and session data do not pass through this feature, not
that Bottogram stores no buyer-related information of any kind.

No persistence or cookie sharing with an external browser is assumed. Existing
shop, domain, authentication and purchase restrictions remain enforced by the
website; this feature provides no bypass. Prior buttons cannot be recalled just
by changing a storefront setting, and a failed menu update can leave the old
Telegram menu in place.

## Verification and remaining client checks

Automated tests use the installed Televerse SDK against a loopback Bot API fixture
and the real lifecycle coordinator with an isolated progress store. They cover
all commands, direct URL/button serialization, group behavior, untrusted package
isolation, invalid origins, ignored Web App data, failed menu/reply delivery,
disabled alerts, preserved setup/secret references, prior delivery receipts,
and recovery of pending and already-acknowledged seller actions. They do not use
real bot tokens, buyer sessions or a live payment provider.

Real Telegram client verification remains outstanding: fresh/existing website
login and cross-host handoff, return to `/orders`, custom shop domains, reopening,
logout and account switching, payment success/cancel/failure and return, and
website operation with Bottogram stopped. Browser isolation across accounts on a
shared device is not established by these tests. A client failure must be reported
before proposing Inshopa changes or a workaround.

Telegram requires Stars for digital goods/services sold inside Mini Apps; loading
an existing website does not remove that requirement. An existing external
checkout must not be presented as universally suitable for digital shops.

Official references:

- [Mini App launchers](https://core.telegram.org/bots/webapps)
- [InlineKeyboardButton](https://core.telegram.org/bots/api#inlinekeyboardbutton)
- [Bot menu](https://core.telegram.org/bots/api#setchatmenubutton)
- [Digital goods payment requirements](https://core.telegram.org/bots/payments-stars#q-i-run-my-own-website-to-process-sales-does-this-mean-i-dont-have-to-use-telegram-stars)

Recorded local verification, 2026-11-10:

- `flutter analyze --no-pub`: no issues.
- The default concurrent full test run completed with 155 passes and three
  SQLite worker/test timeouts in the existing storage/inspector tests.
- A serial rerun of those two files together with storefront presentation,
  order polling, automation runtime, lifecycle, plugins and inbox SDK tests:
  all 60 tests passed, including the six new presentation/preservation tests.
- Supported Flutter hot reload succeeded. A before/after snapshot through Dart's
  public VM service confirmed that the three saved bots, setup identities and
  preferences, and the single active bot stayed unchanged; the new presentation
  class was loaded. No live bot was stopped or restarted for this verification.
