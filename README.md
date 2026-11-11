<div align="center">

![Bottogram — Telegram bots, on your own device](docs/assets/banner.svg)

**A visual Telegram bot builder for Android, Windows, macOS, and Linux.**

Create commands, install plugins, and manage conversations on your device.

[![Build test artifacts](https://github.com/hayyaun/bottogram/actions/workflows/build.yml/badge.svg)](https://github.com/hayyaun/bottogram/actions/workflows/build.yml)
![Flutter 3.47.9](https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter&logoColor=white)
![Android 7.0+](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)
![Status: experimental](https://img.shields.io/badge/status-experimental-8B5CF6)

**[Project website](https://bottogram.hayyaun.ir/)** · **[Download latest release](https://github.com/hayyaun/bottogram/releases/latest)** · [Quick start](#quick-start) · [Plugin guide](docs/PLUGIN_AUTHORING.md)

</div>

Bottogram runs Telegram bots on your Android, Windows, macOS or Linux device, without
a separate Bottogram server. Use it to:

- Build commands, replies, buttons and API actions with a visual editor.
- Store variables and structured data in each bot's own SQLite database.
- Install JSON plugins with generated setup forms and editable preferences.
- Read conversations, reply manually and open attachments from the inbox.

**Experimental:** real-device verification is still in progress; see the
[roadmap](docs/REMAINING_WORK.md).

## Downloads

Download a package and `SHA256SUMS.txt` from
[GitHub Releases](https://github.com/hayyaun/bottogram/releases).

- **Android:** `bottogram-android-release.apk` — install the APK.
- **Windows x64:** run `bottogram-windows-x64-setup.exe` to install for your user,
  or extract `bottogram-windows-x64.zip` and run `bottogram.exe` beside its DLLs
  and data. Both include the required Visual C++ runtime DLLs.
- **macOS 13+:** `bottogram-macos-universal.zip` — extract the ZIP for Intel or Apple
  Silicon. This test build is ad-hoc signed and is not Apple-notarized.
- **Linux x86_64:** `bottogram-linux-x86_64.AppImage.tar.gz` — extract the tarball and run its
  AppImage. Plugin API keys need a desktop keyring.

Development builds are also available from successful
[GitHub Actions runs](https://github.com/hayyaun/bottogram/actions/workflows/build.yml);
those artifacts require sign-in and expire after 14 days.
See [build requirements](docs/BUILD_ARTIFACTS.md),
[Android updates](docs/ANDROID_SIGNING.md), and
[macOS signing and Keychain](docs/MACOS_BUILD.md) before replacing an installation;
uninstalling removes local data.

## Quick start

1. Create a bot with [@BotFather](https://t.me/BotFather) and keep its token private.
2. Choose **Create bot** in Bottogram, or the centered **+** on mobile.
3. Enter a name, token, and the numeric Telegram IDs of your admins. Choose
   **Manual**, a template, or a plugin, then complete any extra setup fields.
4. Open your bot in Telegram and send `/start` so it can message your account.
5. Start it in Bottogram. On Android, follow **Keep bots running** to configure
   background execution and notifications.

Tap a bot card for its users and inbox; use its **Settings** gear for configuration.

Bots need a network connection and a running Bottogram process. Android's
foreground service keeps bots running when the activity closes. Its ongoing
notification shows active and total bots. After a device restart, force-stop,
or process termination, reopen Bottogram to resume the bots you left enabled.
Keep local data and exports private: they can contain bot tokens and conversations.

## Plugins

Open **Plugins → Install from file** to import a `.bottogram-plugin.json` package.
Review its capabilities and API destinations, then create a bot with that plugin.
Packages declare configuration and automations; they do not execute arbitrary code.
Installing a package does not start a bot or update existing bots automatically.

To build your own integration, read the [plugin-authoring guide](docs/PLUGIN_AUTHORING.md),
or give your coding agent this command. It requires **Node.js 22.20+ and npm**:

```sh
npx skills add hayyaun/bottogram --skill bottogram-plugin-builder --agent codex --yes
```

Then ask the agent to use `bottogram-plugin-builder`, describe the plugin you want,
and provide the service's API documentation. The command installs the agent skill;
the agent then creates the package. Other agents and installation options are
covered in the guide.

The bundled **Inshopa** integration opens shop/order pages as Telegram Mini Apps
and sends paid-order alerts to all configured admins. It uses a shop's registered
HTTPS origin and API key. See [storefront setup and behavior](docs/STOREFRONT_NAVIGATION.md),
[example packages](examples/plugins) and [runtime/recovery details](docs/PLUGIN_RUNTIME.md).

## Development

Use **Flutter 3.47.9 / Dart 3.13.7**. Android builds use **JDK 17** and support
**API 24+** devices. Install native tools for your target platform; tests and builds
also need a C compiler for bundled SQLite.

```sh
git clone https://github.com/hayyaun/bottogram.git
cd bottogram
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter devices
```

Choose a listed device and run `flutter run -d DEVICE_ID`. Live Telegram/shop tests
are opt-in; ordinary tests do not require real tokens or API keys.

For implementation details, see the [action builder](docs/ACTION_BUILDER.md),
[plugin runtime](docs/PLUGIN_RUNTIME.md), [SQLite packaging](native/sqlite/README.md)
and [native build setup](docs/BUILD_ARTIFACTS.md).

## Contributing

Issues and focused pull requests are welcome. Include your platform, reproduction
steps and expected behavior. Discuss new host capabilities before implementing them.
Never include tokens, API keys, private exports or customer data in reports or logs.
