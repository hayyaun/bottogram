# Bottogram: improvement ideas and plugin proposal

Recorded: 2026-11-09 (Asia/Tehran).

This document preserves the project review, confirmed plugin requirements, and remaining design proposals. It is not implementation approval or a claim of device-tested behavior. The per-bot inbox is being implemented in another chat; check its final state before scheduling overlapping work. No application code or Inshopa configuration was changed for this review.

## Current structure

Bottogram is a Flutter/Dart application. Cubits manage the bot and keyboard lists, Hive stores local configuration, and Televerse runs Telegram polling inside the application. There is no separate Bottogram server runtime in this repository.

- `lib/pages/`: bot, event, action, and template screens.
- `lib/widgets/`: bot cards and keyboard/markup editors.
- `lib/store/`: `BotsCubit` and `RMUsCubit`, including persistence/import/export operations.
- `lib/units/virt_bot.dart`: bot definition, Telegram runtime, and start/stop behavior in one object.
- `lib/units/virt_event.dart`: command, text, callback, and inline-query triggers; each runs an ordered action list.
- `lib/units/virt_act.dart`: text replies and dice actions.
- `lib/units/virt_rmu.dart`: reply keyboards, inline keyboards, and saved keyboard definitions.
- `lib/inbox/`: work in progress for bounded message storage and inbox capture.

The current template feature shares keyboards, rather than complete bot definitions.

## Existing findings to verify and address

These findings come from source inspection, including the installed Hive implementation. They have not been reproduced on a device. Concurrent work may change them.

1. **Persist edits and imports.** `BotsCubit.update()` only emits a copied list. Editing bot names, triggers, actions, and keyboards reaches this method without saving the changed bot to Hive. `import()` similarly adds imported bots to UI state without writing them to the main bot box. Verify all changes after closing and reopening storage/application state.
2. **Initialize the markup editor.** `RMUEditor.current` is a `late` field initialized only when the action already has markup. Rendering a new action without markup reads the uninitialized field.
3. **Apply edited triggers to the runtime.** Changing or deleting an event changes the definition without replacing its registered Televerse matcher. Saving configuration and applying it to a running bot need explicit, consistent semantics.
4. **Repair export.** `BotsCubit.share()` adds existing `HiveObject` instances to a second box. Hive 2.2.3 rejects storing the same instance in different boxes. Export also does not await each add. Use independently serialized definitions and verify export/import round trips.
5. **Separate template copies.** Both markup `copy()` methods reuse the original mutable `items` list; inline-button records are mutable too. An independent copy needs independent mutable children. Define linked-template behavior separately if desired.
6. **Replace obsolete coverage.** The existing counter smoke test does not describe Bottogram's UI. Add relevant coverage when fixing persistence, editor, and runtime behavior; the inbox work separately plans its own tests.

Sources: [bot storage](../lib/store/bots.dart), [markup editor](../lib/widgets/rmu_editor.dart), [bot runtime](../lib/units/virt_bot.dart), [event editor](../lib/pages/event.dart), [markup definitions](../lib/units/virt_rmu.dart), [current smoke test](../test/widget_test.dart).

## Product ideas

### 1. Human takeover per conversation

Allow the admin to take over a conversation, pause automatic replies for that conversation, and explicitly resume automation. This avoids conflicting manual and automatic answers. Define whether takeover expires and how that expiry is shown.

Track “needs attention” explicitly. Neither a read message nor an automatic reply proves that the customer's issue is resolved. Keep Telegram online status separate from observed interaction activity.

### 2. Simulator and button validation

Let users type commands, click generated keyboards, preview responses, and see which event/actions run without sending Telegram messages. Use the local execution model rather than starting another Telegram polling consumer.

Validate broken button targets, duplicate/conflicting triggers, and action compatibility. The current event enum includes inline queries, while the action model only provides ordinary replies/dice; exposing an option does not establish a complete supported workflow.

### 3. Complete bot templates

Offer editable starting points for FAQ, contact/support, and product menus, including events, actions, and keyboards together. Keep installed plugins distinct from copied templates: templates are editable definitions; plugins can supply managed integration behavior.

### 4. Simple conversational steps

Support small flows such as “ask name → ask request → confirm.” Store variables and current steps per bot/conversation, with cancellation and expiry. This enables forms and lead collection, at the cost of persistent session state and more complex runtime/testing behavior.

### 5. More useful replies

Add selected media/document actions, formatting previews, and escaped variables such as the user's first name. Each new action needs appropriate configuration, validation, and understandable failures. Avoid making every Telegram API method a separate UI control.

### 6. Honest health and diagnostics

Show starting, running, reconnecting, stopped, and failed states, plus recent successful polling and useful errors. Validate tokens through `getMe`; inspect webhook conflicts through `getWebhookInfo`. A local active flag is not evidence of continuous connectivity or successful message delivery.

### 7. Shareable definitions and protected backups

🛡️ Make shareable templates omit tokens by default and keep full credential-bearing backups separate. This reduces accidental credential disclosure; recipients must configure their own tokens, and full backups need protected handling.

Use a versioned interchange format and validate it before replacing local definitions. Preserve independent copies and predictable duplicate handling.

### 8. Clearer internal boundaries

Gradually separate bot definitions, storage operations, and Telegram execution. Retain Cubit and Hive unless a concrete requirement justifies replacing them. These boundaries support reliable saving, the simulator, runtime reconfiguration, and plugins without requiring a wholesale rewrite.

### Suggested sequence

Finish the separately authorized inbox work. Address the relevant persistence/editor/runtime issues, then prioritize human takeover and the simulator. Complete templates and richer actions can follow. Plugin foundations should be designed around a concrete first integration rather than a speculative general-purpose execution platform.

## New direction: installed plugins

The detailed architecture, current installation/form implementation, future runtime phases, and acceptance checks are in [Plugin implementation plan](PLUGIN_IMPLEMENTATION_PLAN.md). JSON installation and the shared form are approved; live Inshopa connection remains deferred. Confirmed requirements below remain authoritative.

### Confirmed experience

The user requested a plugin named `bottogram-plugin-inshopa`. After installation, creating a bot must offer manual configuration or an installed plugin. Each plugin declares its own initial input parameters, and choosing it during bot creation displays those parameters. The first Inshopa feature is notifying the seller about successful sales only.

Confirmed setup flow, with the additional Telegram prerequisite noted explicitly:

1. 🟣 Install a plugin package in Bottogram.
2. 🟣 Create a bot and choose Manual or one of the installed plugins.
3. 🟣 Provide common bot details: name, Telegram bot token, and numeric admin Telegram ID.
4. Bottogram renders the selected plugin's declared input fields rather than showing a hardcoded form shared by all plugins.
5. 🟣 For Inshopa, enter only the shop's API key as an additional plugin field. Obtain the common admin ID from UserInfo. The key identifies exactly one shop; no shop ID input or shop selector is required.
6. 🟣 Start the newly configured bot in Telegram once so it can send private messages to the admin. Starting UserInfo only does not establish a conversation with this bot.
7. 🟣 Open Bottogram and start the configured bot. Its future local plugin polls the API and sends alerts from the phone while the bot runs, including the requested background mode once [that task](BACKGROUND_EXECUTION_TASK.md) is implemented and verified.

Manual configuration remains available. A plugin's installation is global to the app, but its selected version, settings, secrets, and delivery state belong to each bot instance. Multiple bots using one plugin must remain independent.

### Plugin-defined creation parameters

Plugin-specific parameters are part of the plugin's contract. **The Inshopa API key is the only additional input parameter of `bottogram-plugin-inshopa`**. The numeric admin ID is a common bot field, as subsequently confirmed by the user. Each API key belongs to exactly one shop.

The host has a versioned setup-field schema with stable keys, labels, `text`/`secret`/`integer` types, required flags, help text, and validated nonsecret defaults/bounds. The numeric Telegram admin ID is validated as a shared bot field. The accepted setup-only format is documented in the implementation plan.

Inshopa declares one additional field; its shared admin dependency is listed separately for clarity:

- `apiKey`: the shop's Inshopa API key; secret input, saved with that bot's plugin configuration and excluded from ordinary exports/logs. Inshopa derives the single authorized shop from this key.
- Shared field `adminTelegramUserId`: the admin's own positive numeric Telegram user ID; include UserInfo help and preserve it exactly. Plugins reference this common field instead of redeclaring it.

Bot name, Telegram token, and admin ID are common bot fields. Do not request a separate `shopId` or display a shop selector: the API key determines the target. Returned shop identity/name can be used internally. API URL and polling interval are not additional required creation fields.

Switching plugin selection must display and validate the new plugin's fields and must not copy one plugin's secrets into another plugin's configuration. Form generation and runtime reading must use the same schema/field keys. Validation must not make real API purchases or send sale alerts as a side effect.

### What “installable” means on the current stack

The inspected SDK is Flutter 3.29.1 with Dart 3.7.0. Ordinary Flutter packages/plugins are app build dependencies, not an end-user runtime package installer. Flutter's Android deferred components download parts of the same app build; they do not provide an independently extensible third-party Dart plugin system.

There are two practical designs to consider:

- **Compiled extensions:** implement a typed Dart plugin interface and bundle implementations when building Bottogram. This allows custom Dart logic, but adding an implementation requires distributing an updated app. Enabling a bundled extension is not equivalent to installing a new independent plugin.
- **Installable declarative packages:** build a versioned connector/action host into Bottogram, then install validated manifests, settings definitions, templates, and assets. New packages can use existing host capabilities without rebuilding Bottogram. A new native capability still requires an app update. These packages do not execute arbitrary downloaded Dart source.

The user selected JSON file installation for v1. 🛡️ Its constrained declarative model limits arbitrary-code/credential access and avoids an additional execution runtime; the tradeoff is that plugins can express only supported host capabilities. The current slice installs setup-only packages; live execution remains future work.

Arbitrary executable third-party plugins require a separate runtime, compatibility, distribution, and isolation design. No interpreter, undocumented loader, or runtime code-loading workaround is proposed or approved here.

### Minimum host responsibilities

- Maintain a registry with stable plugin IDs, versions, a manifest format version, and compatible host API versions.
- Validate packages before installation; reject unknown required capabilities and incompatible versions. Installation must not execute scripts or contain bot/service credentials.
- Generate setup/settings UI from supported field types. Keep secret values outside exported plugin manifests and ordinary templates.
- Provide explicit capabilities for supported operations, such as an authenticated connector, message rendering/sending, bounded local state, and connection status. Constrain network destinations and recipient access through the host/connector contract.
- Keep the bot token and raw storage handles behind host APIs when they are not required by the plugin's declared behavior.
- Maintain one Telegram update consumer per bot. Plugins attach to host dispatch; they do not start independent `getUpdates` loops.
- Track per-bot plugin identity/version separately from package installation. Preserve existing manual bot definitions and configuration exports.
- Define disable, uninstall, upgrade, missing-plugin, and incompatible-version behavior. Do not silently convert a plugin bot into a manual bot or discard its settings.
- Own local plugin start/stop, cancellation, reconnect/backoff, and per-bot task cleanup. Stop new polling/sends when the bot or its actual runtime stops; UI minimization alone must not stop the requested future background runner. Do not allow overlapping poll loops for the same bot.

## First integration: bottogram-plugin-inshopa

### Background execution task added later

The user subsequently requested continuous operation for user-started bots while the UI is in the background, a battery-exemption guide once on every app opening until actual exemption, and a pinned warning with guide/system-settings actions. The complete task and acceptance checks are in [Background execution and battery setup](BACKGROUND_EXECUTION_TASK.md). This supersedes the earlier foreground-only proposal; implementation and device verification remain pending, and live Inshopa API integration remains deferred.

### Verified Inshopa building blocks

The source inspected at `/home/garfield/projects/inshopa` already contains:

- Accepted-payment handling that records an owner-addressed `order_paid` notification in the same transaction as accepting the payment: `backend/internal/app/commerce_payments.go`, accepted-disposition branch.
- Deduplication with `order-paid:<order_id>` and `ON CONFLICT(user_id,event_key) DO NOTHING`: `backend/internal/database/queries/runtime/commerce.sql`.
- Owner-only notification history with shop filtering and descending cursor pagination: `backend/internal/app/notifications.go` and `backend/internal/database/queries/runtime/notification_reads.sql`.
- A durable worker with job leasing/retries and an existing Web Push delivery path: `backend/internal/app/worker.go` and `backend/internal/app/push.go`.

No Telegram/Bottogram delivery path or seller-scoped plugin credential was found in the inspected implementation. The user subsequently confirmed that API keys are planned but are not ready yet, and clarified that each key will belong to exactly one shop. This is a confirmed future API requirement, not verified implemented behavior. The plugin will use that forthcoming API, not the internal BFF/service credential or a new server-side Telegram sender. Existing internal notification routes are not automatically the contract for this integration.

These are source findings, not verification of production configuration, delivery, or current provider reachability. Some planning text still describes older Push scope, while current source contains Push delivery; do not infer absence of implementation from that older wording.

### Confirmed execution boundary and first feature

The user explicitly selected phone-side polling and sending. The first proposal limited this to an open app; the later [background execution task](BACKGROUND_EXECUTION_TASK.md) extends the required runtime to user-started bots while the UI is in the background. The future Inshopa runner requests successful sales using that shop's API key and notifies only the configured admin. There is no Inshopa-side Telegram sender, bot-token upload, Telegram pairing service, or notification-delivery worker in this scope. Real API execution and background support are still pending, and battery exemption is not an unconditional delivery guarantee.

Inshopa still serves the authenticated API reads; moving scheduling and Telegram sending to the phone does not eliminate that read load. Request frequency, incremental queries, bounded pages, and backoff determine that load. Do not poll full order history repeatedly or fetch the same pages in overlapping tasks.

The future API must define which sales are successful and enforce the API key's single-shop scope on the server. The existing accepted `order_paid` source is a relevant implementation reference; an order being created or a browser returning from payment is not by itself proof of a successful sale. The plugin must use the API's authoritative success semantics.

Send only to `adminTelegramUserId` in a private Telegram chat. This is a user-supplied destination, not proof that this Telegram account owns an Inshopa shop; API authorization comes from the customer's key. No server-side account-linking ceremony is required by the selected design. Do not add buyer messages, broadcasts, order management, payment mutations, AI replies, or other integrations in this first slice.

A minimal message can identify the shop and sale/order and link to the seller dashboard if the future API supplies those values. Message contents remain to be finalized; do not assume totals or product lists are already provided.

### Local polling and delivery behavior

1. Load the selected bot's plugin version, API key, admin ID, and bounded local progress state.
2. Validate configuration and establish the bot's local runtime. Give a clear error for an invalid/revoked API key, invalid token, or unreachable/blocked admin chat. A syntactically valid numeric ID alone does not prove Telegram can deliver to it.
3. Request a bounded page of successful sales through the forthcoming documented API. Send the API key only to the configured/approved Inshopa API origin, never to Telegram or plugin distribution endpoints.
4. Identify previously unnotified sales by stable API-provided IDs and persisted progress. Preserve API pagination/cursor semantics; do not invent routes, headers, response fields, or a cursor contract before the API exists.
5. Send notifications to the configured admin through the phone's Telegram client/API instance. Record confirmed successful sends locally; API read success is not Telegram send success.
6. Serialize polling and delivery per bot. Respect server rate limits and network/Telegram errors with bounded retries and backoff; do not advance delivery progress past failed/unsent sales or drop unprocessed pages. A scan checkpoint may advance only when its unsent page is durably saved with it, as specified in the implementation plan.
7. Wait for the agreed interval while the app/bot remains active. Stop local tasks when it stops; resume from persisted progress the next time it runs, subject to the agreed catch-up policy.

Keep delivery progress independent of dashboard read/unread state. Viewing a sale in Inshopa must not hide it from the plugin; a Telegram send must not silently mark dashboard notifications read.

If the API exposes only the latest N sales without pagination or a durable incremental cursor, more than N new sales while the app is closed can leave older unseen sales unavailable to this polling flow. Document that bound or provide a suitable paginated/incremental API; do not claim every sale is covered by an unpaginated latest-list request.

Persist successful delivery receipts where supported. A crash after Telegram accepts a message but before saving the receipt can cause a retry duplicate: local deduplication does not guarantee exactly-once delivery across that network boundary. A successful API response also does not prove the admin read the message.

### Confirmed decisions

- Choose Manual or an installed plugin when creating a bot.
- Each plugin declares the initial parameters shown for that selection.
- Plugins can also declare typed, editable per-bot settings separately from creation inputs. Inshopa declares a purchase-notification boolean enabled by default; live alerts remain deferred, including first-sync/history policy.
- Inshopa is bundled with Bottogram and available without importing a file. Independently installed JSON packages remain supported. No other default plugins or special uninstall restriction is selected.
- Bot name, Telegram token and admin ID are common creation fields. Inshopa adds only its shop API key.
- Each Inshopa API key belongs to exactly one shop. The plugin does not require a separate shop ID input or shop selector.
- The user obtains their own numeric ID from UserInfo and enters it during creation.
- Poll successful sales and send Telegram alerts from the phone for explicitly running bots. The later background-execution requirement supersedes the initial foreground-only proposal; see [the task](BACKGROUND_EXECUTION_TASK.md). Real API/runtime work remains deferred.
- Shop-scoped Inshopa API keys/API access are forthcoming, not implemented or verified by this review.
- Seller/admin alerts only for the first Inshopa feature.

The earlier server-sender and authenticated account-pairing proposals are superseded for this feature and must not be treated as selected architecture.

### Remaining runtime decisions

- The user selected independently installed JSON files for v1; the Android APK add-on alternative is not selected. Installation and the creation form are authorized, while live Inshopa connection is deferred.
- Finalize the plugin field/manifest contract, supported host capabilities, and local secret/progress storage.
- Confirm the forthcoming API's authentication, success semantics, stable identifiers, pagination/incremental filtering, key scope, rate limits, and available message data. Do not invent an endpoint or ship a BFF credential as a substitute.
- Define polling interval/backoff and first-run/reopen catch-up behavior, including whether initial setup announces existing recent sales or only subsequent ones.
- Implement the requested [background runtime and battery-setup experience](BACKGROUND_EXECUTION_TASK.md), including supported Android execution, truthful status, and handling of in-flight work across UI lifecycle changes. The earlier “no background service requested” premise is superseded.
- Finalize message contents and any shop identity metadata returned by the future API; a user-entered shop ID or shop selection is not needed.

Potential persistence/API changes in either project require a concrete implementation proposal. No database migration file should be written or generated before the user approves its exact schema/data approach under their migration rules.

## External references

- [Flutter: using packages](https://docs.flutter.dev/packages-and-plugins/using-packages).
- [Flutter: deferred components](https://docs.flutter.dev/perf/deferred-components) — components belong to the app build; this is not arbitrary third-party Dart installation.
- [Telegram: how bots differ from users](https://core.telegram.org/bots#how-are-bots-different-from-users) — the admin must message/start the configured bot before it can initiate private alerts to them.
- [Telegram Bot API](https://core.telegram.org/bots/api) — authentication, update handling, sends, errors, and rate-limit response parameters.
- [Android: foreground services](https://developer.android.com/develop/background-work/services/fgs) — background behavior has platform requirements and limitations.
- [HiveObject](https://pub.dev/documentation/hive/latest/hive/HiveObject-class.html) — explicit persistence through `save()`.
