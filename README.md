# bottogram

A new Flutter project.

## Plugins and bot creation

JSON file installation, bundled plugins, and the shared creation form are implemented.
Inshopa is included by default. Version 2 plugins can execute registered triggers and actions.
The bundled Inshopa 0.5.0 plugin provides `/products` to all users and paid-order
alerts to the configured admin using Inshopa’s existing order-summary API.

- Inshopa appears in **Plugins** and the creation dropdown without a file import.
- 🟣 Tap any bot card to open its users and inbox. Use the card's **Bot settings**
  gear for configuration; this works the same for manual and plugin bots.
- 🟣 On mobile, the centered **+** in the rounded bottom navigation opens bot creation.
- 🟣 For additional packages, open **Plugins** using the puzzle icon, choose
  **Install from file**, and review a `.bottogram-plugin.json` package.
- 🟣 Create a bot with its name, Telegram token, and your numeric admin ID from
  UserInfo. Select **Manual** or an installed plugin in the same form.
- The plugin adds **Inshopa API key** and **Storefront URL**. The key identifies one shop;
  there is no shop ID input. Keys are saved in platform secure storage.
- Already installed [Inshopa setup packages](examples/plugins/inshopa.bottogram-plugin.json)
  at version 0.2.0 remain **Setup only**. Existing bots are never automatically upgraded.
- 🟣 Select **Inshopa · 0.5.0**, enter its key and registered storefront origin,
  then start the new bot. Anyone can send `/products` or `/products 2` to see
  catalog pages. It calls `https://api.inshopa.ir/v1/storefront/products`.
  The key must be registered in that environment and its backend must support
  website-key access. Local-key catalog replies and Telegram delivery are verified;
  registered production-key access has not been verified in this project.
- 🟣 In Inshopa’s **Shop Settings → API Keys**, explicitly enable `shop:orders:read`
  alongside `storefront:read` for paid-order alerts. No buyer or seller session is needed.
- For the local WSL backend, the optional [0.5.0 development package](examples/plugins/inshopa.sales.local.bottogram-plugin.json)
  uses `127.0.0.1:8080` and can be imported separately for the Linux preview.
  Linux secure storage also requires a running, unlocked desktop keyring and D-Bus
  session. The opt-in [local preview launcher](tool/run_inshopa_local_preview.sh)
  configures a test bot through the app's normal services, sends a connection test,
  then opens the normal app with hot reload. Its only argument is a private JSON
  connection-file path; credentials must never be passed as command-line values.
- 🟣 Use **Bot settings** to edit its schema-defined **Plugin settings**, then save.
  Inshopa's purchase-notification switch defaults to enabled. This preference is
  separate from the creation API key. The initial complete scan skips paid history;
  subsequent scans notify the admin once per newly observed paid order.
- 🟣 In bot settings, choose **Edit parameters** on the plugin summary card to
  edit the admin ID and plugin inputs on a separate page. Leave a saved secret
  blank to keep it. Saving changed parameters restarts a running bot, preserves
  its plugin preferences, and resets automation progress. For Inshopa the first
  scan of the updated connection establishes a new baseline without old alerts.
- Order polling resolves the shop ID with `/v1/storefront`, scans 100 summaries per
  page with two seconds between pages, then waits 60 seconds before the next scan.
  It catches delayed payments on older orders by revisiting the full list. This
  current-state API cannot guarantee that every payment transition is observed.
- Settings support strings, booleans, bounded integers/numbers, and enum choices.
  Each bot keeps its own values. Bundled versions seed once without overwriting
  installed definitions; an ordinary uninstall persists across restart.
- Installed versions are immutable and retained while referenced by bots.
  🟣 Delete the dependent bots before uninstalling a referenced version.

Android now requires **6.0 / API 23 or later**, as approved for secure storage.
Device-bound secure-storage files are excluded from automatic backups; restoring
on another device requires re-entering plugin keys. Existing bot Hive adapters
remain unchanged; common admin/plugin settings use separate versioned boxes.
Legacy Hive configuration import/export covers manual bot definitions only;
plugin-bot export is explicitly unavailable rather than silently losing settings.

See the [implementation plan](docs/PLUGIN_IMPLEMENTATION_PLAN.md) for the accepted
setup-only history. See [Plugin runtime](docs/PLUGIN_RUNTIME.md) for executable
manifests, architecture, recovery behavior and deployment requirements. The new
Inshopa permission is activated locally; production rollout remains with Inshopa.

## Background execution on Android

Started bots use a foreground service with an ongoing notification and **Stop bots**.
The UI and service share one cached Flutter engine. Stop/Delete release execution
when no bots remain. Background setup is checked on every opening.

- 🟣 Follow **Keep bots running** to allow battery/background activity and notifications.
  Skipping lasts only for this opening; **Read instructions** remains pinned until setup is ready.
- 🟣 After force-stop, process death or reboot, reopen Bottogram and start bots again.
  Automation checkpoints remain saved. Background operation uses battery and data;
  Android/OEM termination and network loss can still interrupt it.

## Local bot inbox

The inbox runs on the phone alongside the bot. No hosting account is needed.

- 🟣 Open a bot and select the people icon to browse known users, 25 per page,
  ordered by their latest incoming message or private-chat button interaction.
- 🟣 Open a user to review up to 20 retained messages and reply as the bot.
  Automatic responses appear in the same conversation. Photos open in the app;
  other attachments use the phone's registered viewer or player.
- 🟣 Open Inbox settings to change that bot's message-cache limit (1–512 MiB,
  default 10 MiB) or clear its messages and downloaded attachments.

Attachments download only when tapped. The limit includes message storage and
downloaded files; least-recently-opened attachments are evicted before old
messages. The minimal user directory and settings are retained separately and
their storage is shown in settings. Writes and compaction can briefly need extra
disk space. Each conversation and its in-memory view stay limited to 20 messages.

Collection begins when the updated bot runs. It does not recover older consumed
Telegram messages or indicate whether a user is online. Clearing or eviction is
permanent for message content. The existing polling runtime must remain active;
this feature does not add a background service. Telegram keeps undelivered updates
for at most 24 hours. Configuration exports do not include conversations.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## ADB WSL Issue Fix

1. Phone: Revoke - Connect USB
1. Windows: taskkill /F /IM adb.exe && adb devices && adb tcpip 5555
1. WSL: adb connect

if the above didn't work... please forcefully disconnect 5037

1. netstat -ano | findstr :5037
1. taskkill /PID <PID> /F
