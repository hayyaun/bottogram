<div align="center">

![Bottogram — Telegram bots, on your own device](docs/assets/banner.svg)

**Build a Telegram bot. Keep it on your device.**

Create replies, install integrations, and answer conversations from one app.

[![Build test artifacts](https://github.com/hayyaun/bottogram/actions/workflows/build.yml/badge.svg)](https://github.com/hayyaun/bottogram/actions/workflows/build.yml)
![Flutter 3.47.9](https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter&logoColor=white)
![Android 7.0+](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)
![Status: experimental](https://img.shields.io/badge/status-experimental-8B5CF6)

[Try a build](#try-a-build) · [Get started](#get-started) · [Plugins](#plugins) · [Development](#development) · [Roadmap](docs/REMAINING_WORK.md)

</div>

---

Bottogram is a Flutter app that runs Telegram bots locally. Configure a bot by
hand or choose an installed plugin, start it, and let your device handle Telegram
updates and API requests. Bot execution does not need a separate Bottogram server.
Your device still needs a network connection to Telegram and any connected service.

> **Work in progress.** Test builds are available through GitHub Actions once a
> successful build completes. Public releases are deferred while the Inshopa
> integration and real-device verification develop. See the [current roadmap](docs/REMAINING_WORK.md).

## What you can do

- **Build without writing code.** Configure command, text, callback and inline-query
  events, polling timers, connected actions, external JSON API calls, persistent
  variables, SQL and Telegram messages with a MarkdownV2 editor. See the
  [action builder](docs/ACTION_BUILDER.md).
- **Install integrations.** Import a declarative JSON plugin and fill in its
  generated setup form. Plugin versions stay pinned to the bots that use them.
- **Answer from the inbox.** Open a bot's users, read retained conversations,
  reply manually, and open attachments on demand.
- **Keep started bots running on Android.** A foreground service, ongoing Stop
  notification, and battery-settings guide support execution while the UI is away.
- **Use your desktop too.** Windows and Linux builds run bots while the application
  remains running. They share the same configuration and plugin concepts.

## Try a build

Open [GitHub Actions](https://github.com/hayyaun/bottogram/actions/workflows/build.yml),
choose a successful run, and download its artifact. GitHub may ask you to sign in.

- **Android:** `bottogram-android-release` — a universal, optimized release-mode APK.
- **Windows x64:** `bottogram-windows-x64` — extract the complete ZIP and run
  `bottogram.exe` alongside its DLLs and data.
- **Linux x86_64:** `bottogram-linux-x86_64` — extract the AppImage tarball and run
  the included executable. A desktop keyring is needed for plugin API keys.

These are testing artifacts, retained for 14 days, without store publishing or
GitHub Releases. Trusted Android builds use a dedicated, permanent app-signing
key for updates across GitHub downloads. PR validation artifacts use a separate
temporary certificate. Older debug-signed installations cannot be updated
directly to this new identity; uninstalling them removes local data. See
[Android signing](docs/ANDROID_SIGNING.md) and [build details](docs/BUILD_ARTIFACTS.md).

## Get started

1. Create a Telegram bot with [@BotFather](https://t.me/BotFather) and keep its token private.
2. In Bottogram, choose **Create bot** — the centered **+** on mobile.
3. Enter a name, the bot token, and your numeric Telegram admin ID. Choose
   **Manual** or a plugin; its additional fields appear in the same form.
4. Open your bot in Telegram and send `/start`, so it can message your account.
5. Start the bot in Bottogram. On Android, follow **Keep bots running** to check
   battery/background and notification settings.

Tap a bot card to open its **users and inbox**. The card's **Settings** gear opens
configuration. Plugin setup values have a separate **Edit parameters** page;
leaving a saved API key blank keeps its current value.

## Plugins

Plugins are `.bottogram-plugin.json` files containing validated configuration,
fields, and automations. The host executes registered **triggers → actions**;
packages do not download or execute arbitrary Dart code. Adding a new host
capability requires an application update.

To install an additional package, open **Plugins → Install from file** and review
its declared API destinations and capabilities before installing it.

### First integration: Inshopa

The bundled **Inshopa 0.6.0** plugin connects one shop using its API key and
registered storefront URL. A separate shop ID is not required.

- `/start` and `/shop` open the existing shop and its `/orders` page as Telegram
  Mini Apps. `/orders` opens order history; `/help` gives brief sign-in guidance.
- `/products` remains an alias for opening the shop, without fetching a catalog.
- Buttons load the shop website directly in Telegram's web view. The website
  handles sign-in and checkout; Bottogram does not receive website passwords,
  sign-in codes, or sessions.
- Paid-order polling sends alerts only to the configured admin.
- The first complete scan establishes a baseline without historical alerts.
- Purchase alerts can be disabled in that bot's plugin preferences.

Opening pages needs no buyer API permission. The existing alert automation still
uses `storefront:read` to identify the shop and `shop:orders:read` for order alerts.
The storefront must have a usable HTTPS origin; local HTTP origins cannot launch
Mini Apps. Login continuity and payment return behavior still need real Telegram
client verification. Digital goods sold inside Telegram require Telegram Stars;
the existing external checkout is not a universal digital-goods solution.

Commands, text, button labels, page paths and menu configuration all belong to
the plugin JSON. Bottogram provides the same validated command, reply and Mini App
capabilities to every plugin; executable host code has no Inshopa ID/hash mapping.
Older installed packages remain immutable and pinned until a reviewed update is
selected. Compatible updates retain the bot identity, configuration, credentials
and unchanged seller-alert progress, including pending actions and delivery
receipts. The old package and source progress remain intact.

A stopped bot can apply a reviewed update immediately. An active bot can queue it
for its next normal Start without being stopped. That selection is session-only:
restarting Bottogram discards the queue and requires review again. An HTTP or
otherwise invalid Mini App origin rejects the update without changing the old
bot. Existing HTTP development settings are never silently rewritten. See
[storefront navigation](docs/STOREFRONT_NAVIGATION.md).

**Verification so far:** the local catalog command and admin connection message
were confirmed end to end. A newly paid order alert, production-key access, and
physical-device delivery remain unverified. Current-state order polling is
best effort; it is not a durable payment event feed.

See [plugin architecture and recovery behavior](docs/PLUGIN_RUNTIME.md),
[example packages](examples/plugins), and the [remaining integration work](docs/REMAINING_WORK.md).

## Runtime and local data

- Bots run on your device. Android/OEM termination and network outages can
  interrupt them; battery exemption does not guarantee delivery.
- After Android force-stop, process death, or reboot, reopen Bottogram and start
  the bots again. Saved automation progress remains available.
- Plugin API keys use platform secure storage. Bot tokens are part of local bot
  configuration; treat application data and configuration exports as private.
- The inbox keeps up to 20 messages per conversation and has a configurable
  cache limit. Clearing or evicting messages removes their local content.
- Manual bot definitions support configuration sharing. Plugin-bot exports are
  not implemented. Credentials and conversation histories are not plugin packages.

## Development

The build toolchain uses **Flutter 3.47.9**, **Dart 3.13.7**, and **JDK 17**.
Android requires **API 24+**; native build tools are needed for desktop targets.

```sh
git clone https://github.com/hayyaun/bottogram.git
cd bottogram
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

Choose a configured target, then run `flutter run -d <device-id>`. For native
SDK requirements and test packaging, see [Build artifacts](docs/BUILD_ARTIFACTS.md).
Live Inshopa and Android background integration tests are separate, opt-in checks;
ordinary CI does not require real Telegram tokens or shop keys.

The project uses Cubit for UI state, Hive for app configuration, a separate
SQLite database per bot for creator-managed data, Televerse for Telegram, and a
host-side automation registry for plugins. Native SQLite is compiled from pinned
upstream source through Dart build hooks; a C compiler is required for tests and
builds. See [SQLite source and security packaging](native/sqlite/README.md).

Hive serializers in `lib/units/*.adapter.dart` use the public `TypeAdapter` API
and are maintained explicitly. Keep existing type/field IDs stable and extend
the legacy-record and round-trip tests whenever the stored model changes.
Adapter code generation is no longer a build prerequisite.

## Contributing

Issues and focused pull requests are welcome. Describe the problem, platform,
steps to reproduce, and expected behavior. Discuss larger plugin capabilities
before implementing them so they fit the host's declarative architecture.

Never include bot tokens, API keys, private exports, or customer data in an issue,
pull request, screenshot, or build log.

Start with the [roadmap](docs/REMAINING_WORK.md) and [runtime documentation](docs/PLUGIN_RUNTIME.md).
