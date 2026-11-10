# Plugin runtime

Contract updated 2026-11-10. Verification results below identify the feature
slices they exercised; they do not establish real Telegram
client compatibility for the new Mini App navigation.

## Current HTTP headers and plugin error contract

The current unreleased contract has no legacy decoder for the former implicit
storefront-header property. HTTP execution has no built-in Inshopa header names,
shop registration convention or plugin-specific message catalog. Every current
v2 example declares the headers it needs.

`request.headers` maps validated header names to either literal strings or typed
public-field references. A reference contains `field` and one of the transforms
`value`, `url.origin` or `url.authority`. URI transforms use the supported URI
parser and require a complete HTTP/HTTPS origin without userinfo, page path,
query or fragment. URL transforms use `Uri` encoding. Header values must contain
only printable ASCII or horizontal tab, matching the installed Dart HTTP
transport. For example, the Inshopa package owns this declaration:

```json
{
  "headers": {
    "Origin": {"field": "storefrontUrl", "transform": "url.origin"},
    "X-Storefront-Host": {"field": "storefrontUrl", "transform": "url.authority"}
  },
  "authentication": {"type": "bearer", "secretField": "apiKey"}
}
```

Another plugin can declare different header names without a host change.
Authentication is separate: `type: "bearer"` constructs the bearer header;
`type: "header"` uses a declared `header` name and `secretField`, such as an
`X-Api-Key` credential. Only the authentication path reads secure storage.
Public header bindings must reference declared non-secret fields. Case-insensitive
duplicates, authentication/header collisions, transport-managed headers, malformed
names, line-break injection and oversized values are rejected. Raw configured
values, authenticated request URLs and credentials are not included in failures.

The optional top-level `errorMessages` object defines reusable display resources:
`title`, `message`, optional `help`, and optional `action`. The initial action
names are `editPluginParameters` and `retry`; these request explicit UI actions,
not automatic execution. A trigger/action's sibling `errorMap` maps a stable
host failure code to a resource ID. The resource must exist in that package.

```json
{
  "errorMessages": {
    "shopAccessDenied": {
      "title": "Shop access denied",
      "message": "Inshopa rejected the shop connection.",
      "help": "Check the API key, its permissions and the registered shop address.",
      "action": "editPluginParameters"
    }
  }
}
```

For example, the polling trigger maps `http.unauthorized` and `http.forbidden`
to `shopAccessDenied`, while `poll.scan_limit_exceeded` maps to the package's
`orderScanLimit`. A Mini App reply maps `configuration.invalid_public_origin`
to `shopUrlInvalid`. Both current 0.6.0 definitions keep all shop-specific error
wording in these JSON resources.

The host controls permanence, retry timing, delivery uncertainty and stopping an
automation. Messages cannot override those decisions. Resource text is plain
text without interpolation or executable expressions; it receives no response
body, raw exception, credential, setup value or arbitrary event data. Unmapped
failures use generic host messages. Presentation-only catalog/map changes do not
reset automation progress, whereas actual request/execution changes still need
their own state transition assessment.

The approved one-time offline Hive transition saved exact pre-change data files
outside the repository, rewrote three installed package definitions and added
local 0.6.0. Only the local 0.5.0 setup digest changed; other settings and defaults
were retained, including enabled seller notifications. Two progress records were
copied to the rewritten digest namespace and the originals were retained. There
were no delivery receipts to copy. No bot was restarted. Automated checks and
reopening the normal Linux debug preview verified the transitioned data.

The current local bot remains pinned to 0.5.0. Local 0.6.0 is installed and
available, but no reachable HTTPS shop address has been provided for its Mini App
navigation. Installing a package does not apply it to a bot.

## Current contract verification — 2026-11-10

The pinned SDK was used for these checks:

- `dart analyze lib test`: no issues found.
- `flutter --no-version-check test --no-pub --concurrency=1`: 184 passed and six
  failed out of 190 tests. After correcting two UI cases, one schema fixture and
  one console assertion, the targeted rerun below passed all 23 tests.
- `flutter --no-version-check test --no-pub --concurrency=1 test/ui_test.dart test/plugin_contract_schema_test.dart test/builder_engine_test.dart`:
  23 passed.
- `flutter --no-version-check test --no-pub --concurrency=1 test/bot_templates_test.dart test/inbox_repository_test.dart --name 'task creation, paging, toggle and deletion never affect another user|user pages are ordered, bounded, unique, and ignore group chats'`:
  both native persistence cases passed in isolation with their existing deadlines.

All 190 distinct tests have successful outcomes across the full run and these
reruns; there was no single green full-suite invocation. Logs are
`build/verification/contract-full-test.log`, `contract-corrected-rerun.log` and
`contract-persistence-rerun.log`. A source-coupling audit covered 557 files and
found no Inshopa-specific runtime behavior; the remaining name reference
registers the bundled JSON asset.

The normal Linux debug preview reopened with three saved bots, zero active bots
and four installed packages; every saved package pin resolved. The local bot
remains on 0.5.0 with seller notifications enabled, local 0.6.0 is installed and
no update is queued. A private canonical-JSON comparison against the pre-change
snapshot confirmed every public setup field except the intended digest change
was unchanged, including the exact original shop URL. Public counts and result
flags are recorded in `build/verification/contract-preview-state.json`. Real
Telegram HTTPS navigation, authentication and checkout checks remain outstanding.

## Earlier generic Telegram navigation verification — 2026-11-10

Inshopa 0.6.0 owns its navigation behavior in JSON. The prior host-side package
hash registry and storefront command implementation have been removed. Generic
command aliases/chat filtering, Mini App replies, declarative menus and reviewed
compatible package updates are available to any plugin.

`flutter analyze --no-pub` completed without issues. The complete test suite ran
with `--concurrency=1`: all 172 tests passed. Coverage includes an unrelated event
plugin, schema and URL rejection, Unicode/punycode domains, SDK button/menu
serialization, old pinned catalog behavior, seller pending-action recovery and
delivery receipts, failed update staging/retry, Hive reopening, inactive-session
cleanup before copying, and update review/apply/queue/cancellation UI.

Supported Flutter hot reload loaded the implementation without restarting the
preview. The approved 0.6.0 definition was installed through the same validated
repository API used by file import. Before/after public VM-service checks showed
three saved bots and one active bot with unchanged setup identities, pinned
versions, preferences and running state. No existing bot was automatically
upgraded, stopped or started. This earlier check preceded the breaking
header/error contract above; its package-byte observations are not a current
backward-compatibility guarantee.

These checks do not establish live Telegram website sign-in, account isolation,
or payment-provider return behavior. Those checks and the digital-goods payment
constraint remain documented in [Storefront navigation](STOREFRONT_NAVIGATION.md).

## Boundaries

```mermaid
flowchart TD
  File[JSON package] --> Validator[Manifest and component schemas]
  Validator --> Catalog[Immutable package catalog]
  Catalog --> Form[Common form plus plugin setupFields]
  Form --> Setup[Per-bot settings and secure key references]
  Setup --> Coordinator[BotRuntime lifecycle coordinator]
  Coordinator --> Session[One Televerse session per bot]
  Coordinator --> Runner[One runner per enabled automation]
  Runner --> Trigger[Trigger registry]
  Trigger --> Poll[http.poll.v1]
  Trigger --> List[http.poll-list.v1]
  List --> Lookup[Resource lookup and offset pagination]
  Trigger --> Command[telegram.command.v1 / v2]
  Session --> Command
  Runner --> Actions[Ordered action registry]
  Actions --> HTTP[http.get-json.v1]
  Actions --> Admin[telegram.notify-admin.v1]
  Actions --> Reply[telegram.reply.v1 / v2]
  File --> Menu[Declared Telegram menu button]
  Menu --> Session
  Admin --> Session
  Reply --> Session
  Runner <--> Progress[Per-instance progress and delivery receipts]
  Coordinator --> Lease[ExecutionLease port]
  Lease --> Service[Android foreground service]
  Service --> Engine[Cached Flutter engine and single Dart isolate]
```

The downloaded JSON declares configuration. It cannot supply Dart/JavaScript/native code, executable class names, or arbitrary message destinations. A new component type needs a host implementation and schema registration in `lib/runtime/registry.dart`. Existing registered types can be composed by JSON alone. Commands, text, labels, web destinations and optional menu configuration belong to each package. The host has no plugin-specific ID/version/digest registry or command/route override. See [Storefront navigation](STOREFRONT_NAVIGATION.md).

`AutomationRunner`, component contracts, request/message execution and schema registration are independent of widgets and Android settings. `BotRuntime` adapts existing bot storage and Telegram lifecycle to the core. The Android platform is accessed through the small `ExecutionLease` port.

## Package versions and installation

Version 1 packages remain setup-only. Version 2 requires `manifestVersion: 2`, `hostApiMajor: 2`, `executionStatus: "live"`, and `automations`. The old `engine` property is forbidden in v2. Unknown component types, unknown configuration keys, unresolved credential references, duplicate IDs/commands, and invalid settings references are rejected on import.

Package definitions stay pinned by ID, version and source digest. Installation shows command availability, request URLs, and polling intervals. Bundled definitions seed once; uninstall remains effective across restart. Existing bots never switch package version or begin executing because a new package was installed.

A generic reviewed update checks the target package's schema, retained setup,
and automation execution configuration. Error catalogs and component `errorMap`
presentation metadata are excluded from this comparison. Compatible automations
retain their execution context and progress, including all receipt keys. Their state is
staged in the target package namespace before the existing setup pin is committed;
failure leaves the old pin and source progress intact. The old package and
namespace remain available. A package declaration cannot authorize cross-shop
state reuse or skip the host's compatibility checks. Existing storage schemas
and format versions are unchanged; no schema migration or startup backfill is
used. The explicit one-time offline data transition is recorded above.

Stopped bots apply an approved compatible update immediately. Active bots can
queue the reviewed target for their next normal Start without being stopped.
The queue is in memory for the current app session, is revalidated at application,
and is discarded if Bottogram restarts. Invalid/HTTP Mini App origins reject an
update without modifying the older bot or silently rewriting its configuration.

The common form still asks for name, Telegram bot token and numeric admin ID. The Inshopa plugin adds `apiKey` and the approved `storefrontUrl`. The key selects its one shop; the storefront URL supplies the registration headers. The authenticated `/v1/storefront` lookup provides the shop ID, so no additional shop-ID input is needed.

## Inshopa storefront navigation

The [Inshopa 0.6.0 package](../examples/plugins/inshopa.storefront.bottogram-plugin.json)
declares `/start`, `/shop`, `/orders`, `/help`, and a `/products` compatibility
alias to open the existing HTTPS storefront and `/orders` directly as Telegram
Mini Apps. Its JSON uses generic `telegram.command.v2`, `telegram.reply.v2`, and
the optional `telegram.menuButton` configuration. It does not request a catalog
for these commands. Website authentication and sessions remain in Telegram's
browser and Inshopa; no buyer scope, buyer account API or Inshopa change is added.
Other packages execute their own declarations. Existing pinned bots retain their
version until a compatible reviewed update is selected. Details and outstanding
client checks are in [Storefront navigation](STOREFRONT_NAVIGATION.md).

### Catalog example declaration

[The catalog-and-alert example](../examples/plugins/inshopa.sales.bottogram-plugin.json)
is version 0.5.0, displayed as **Inshopa**. Its public command composes:

```text
/products [page]
  telegram.command.v1
    → http.get-json.v1
        GET https://api.inshopa.ir/v1/storefront/products?limit=10&offset=...
        Authorization: Bearer <secure apiKey>
        Origin: <registered storefront origin>
        X-Storefront-Host: <registered storefront authority>
    → telegram.reply.v1
        reply with product titles to the originating chat
```

This example uses the current explicit header syntax while retaining its catalog behavior. It is not a decoder or compatibility guarantee for an older installed source copy. The generic catalog command is public: no admin-ID filter is applied. `/products` requests page 1, `/products 2` requests page 2. Empty pages are explicit. Ten products per page keep the supported 200-character titles inside Telegram's message limit; this is a list, without checkout, buyer login, or product-detail requests. Command queues are bounded. Overloaded command queues ask the requester to retry.

The public API origin is **https://api.inshopa.ir**, verified from `inshopa/gateway/nginx/templates/gateway.conf.template`. The gateway preserves `/v1` and routes that hostname to Go. Independent anonymous checks returned health HTTP 200 and product-list HTTP 401 `CALLER_UNAUTHORIZED`. The SDK constructs `/v1${path}` against `config.apiOrigin`, so the configured origin has no `/v1` suffix. The local web instance separately uses `http://127.0.0.1:8080` as its private upstream.

The Next.js facade also exists at `/api/v1`: a live anonymous request to `https://inshopa.ir/api/v1/storefront/products` returned JSON `SHOP_NOT_FOUND`. Its current implementation obtains credentials from `apiConfig()`, derives context from the ingress Host, and does not forward an incoming customer Bearer key. The external server-side SDK and Bottogram use `api.inshopa.ir` directly. A customer's own browser-facing facade remains on that customer's website. No proxy or backend changes are included here.

The [local 0.6.0 navigation package](../examples/plugins/inshopa.storefront.local.bottogram-plugin.json) keeps its own `bottogram-plugin-inshopa-local` ID and the existing WSL loopback API destinations. The older [catalog-and-alert example](../examples/plugins/inshopa.sales.local.bottogram-plugin.json) is also expressed with current explicit headers. These files do not redirect a local bot to production or invent an HTTPS storefront. An Android phone's loopback address points to the phone. HTTP API addresses are allowed only for literal loopback hosts (`localhost`, `127.0.0.1`, `::1`); remote URLs require HTTPS. A registered development origin can remain HTTP as API-header data, while Telegram Mini App navigation separately requires HTTPS.

Fresh installations seed the production 0.6.0 package. Current source examples
may retain earlier version labels to exercise their distinct declarations, but
the unreleased contract does not preserve their old bytes or removed syntax.
The existing test catalog received the explicit offline transition described
above; no legacy request adapter is retained. Installing a package and applying
it to a particular bot remain distinct operations.

Reachability and SDK publication do not establish production website-key rollout. The Inshopa release records distinguish locally verified key support from production rollout and real client enrollment. Local-key catalog replies and live Telegram delivery are verified below; registered production-key access remains untested.

## Existing cursor-based trigger

The generic HTTP poll trigger is implemented and tested against fixtures. Its request is a bounded GET; response mapping declares `itemsPath`, `itemIdPath`, `checkpointPath`, `hasMorePath`, `nextPagePath` and the cursor query parameter. Poll intervals range from 30 seconds to one day. `initialSync` explicitly chooses `baseline` or `replay`.

For `baseline`, the initial paginated cycle records current event IDs and the checkpoint without notifying about history. Further cycles deliver events. An API may make bootstrap efficient by returning an empty initial snapshot with its current checkpoint. Checkpoint semantics must be agreed with the API, rather than inferred from timestamps.

Every page must use a stable checkpoint for that synchronization cycle. A page cursor resumes pagination; the committed checkpoint advances only after all pages and actions are acknowledged. A bounded recent-ID set also suppresses duplicate events across overlapping pages. Progress is keyed by bot instance, package digest, and automation ID, with action indexes inside each pending event. Successful HTTP action results are retained so a later failed reply does not cause a fresh catalog fetch during recovery.

State lives in `automation_progress_v1`. Existing bot adapters and stored setup
maps are not converted or backfilled at startup. An explicitly reviewed update
stages compatible progress before changing the selected setup's existing package
pin. Stop drains pending acknowledgements; Delete removes that instance's
progress and receipt entries. No schema migration or startup backfill is used;
the approved one-time offline data transition is described above.

Requests time out after 22 seconds, responses are limited to 1 MiB, each progress record to 2 MiB, and API redirects are refused. Receipt count and total receipt storage grow with observed paid orders. Each bot owns its HTTP client so Stop cancels its requests independently. Retry uses capped backoff and honors numeric `Retry-After`. Authentication/contract failures require attention; credentials and SDK exception URLs are not surfaced in diagnostics.

Telegram delivery is not exactly-once. If the server accepted a message but confirmation or the following durable acknowledgement was lost, a retry can duplicate it. A confirmed action with a durable acknowledgement is not repeated. Outgoing messages use the existing API/inbox transformer path.

## Paid-order polling with the implemented Inshopa contract

Inshopa added the explicitly selected `shop:orders:read` permission to the existing `GET /v1/shops/{shopId}/orders?limit=100&offset=...` summary list. It requires the shop-bound key and registered hostname, without a buyer or seller session. This was verified read-only against `backend/docs/SELLER_API_CLIENTS.md`, the handler and SQL query. The list contains all statuses and is ordered by order creation time. It provides no payment event ID, `paid_at`, API cursor, snapshot boundary, or history/recovery guarantee. Inshopa’s local activation is complete; production was not deployed by this work.

The new generic `http.poll-list.v1` trigger owns HTTP resource lookup, offset pagination and exact-value filtering. The Inshopa JSON declares a lookup to `/v1/storefront`, binds its `id` into the complete `{shopId}` path segment, then filters summaries with `status == paid`. Lookup values cannot populate the scheme, host, query, credentials, or message templates. Both lookup and list requests participate in installer review and required-secret validation. The lifecycle coordinator contains no Inshopa-specific condition.

The first complete scan establishes a client-side baseline of observed paid IDs and sends no historical alerts. Pending orders are not marked as paid; if later observed as paid, they generate an alert even when created long ago. All pages are revisited to avoid a latest-page-only window. A page contains 100 raw summaries; filtering does not change offset advancement or the decision to request the next page. Two seconds separate pages, and a 60-second pause follows a complete scan. The host stops a scan that exceeds the package's 1,000-page limit and reports it explicitly rather than claiming success or silently limiting history.

The runner, not the trigger, records acknowledgements per normalized order ID. List-trigger batches request durable deduplication: one SHA-256-ID receipt is stored per baseline/completed order in the existing progress box, scoped by bot instance, package digest and automation. Receipts survive Stop/Start and disk reopening and are not evicted by the older 2,000-ID recent cache. They consume storage proportional to observed paid orders and are removed with the bot. The original cursor and command components retain their existing bounded recent-cache behavior.

Each action acknowledgement is saved before its delivery receipt. If receipt persistence fails after an acknowledged send, recovery completes the receipt without repeating the action. Local page continuation is saved after processing a page and resumes on restart; it is an offset, not a server-issued cursor or consistent snapshot. Authentication failures stop that automation and show the plugin's mapped guidance or the host's generic fallback. The purchase-notification preference is enabled by default and can be disabled independently of buyer navigation. The `paid-orders` execution configuration is unchanged between the current 0.5.0 and 0.6.0 definitions. Their presentation metadata can differ: local 0.6.0 adds an error catalog and `errorMap` entries absent from local 0.5.0. The generic updater excludes that presentation metadata when comparing execution compatibility, allowing compatible state and receipts to be retained.

This is best-effort observation of current states. A paid state that appears and disappears between requests may be missed. Concurrent list changes and the API’s creation-time ordering do not provide a stable event-log guarantee, and `created_at` is never treated as a payment timestamp. A payment already confirmed by Telegram but lacking a durable acknowledgement can still be duplicated after an ambiguous failure. No Inshopa source, database, migration, service or production configuration was changed by Bottogram.

## Android execution

An explicitly started bot acquires a foreground execution lease. The native service holds the cached engine and a partial wake lock while bots are started. The Activity can detach and reattach without creating another Dart isolate or Hive writer. An ongoing notification opens the app and exposes Stop bots. The last stopped/deleted bot releases the service and wake lock.

The declared `specialUse` foreground subtype describes the app's continuous user-started Telegram automation purpose. It does not claim to be a file-transfer `dataSync`, media player, alarm, VPN, or companion-device service. Google Play distribution would require the applicable foreground-service declaration/review; local API/emulator success does not establish Play approval. See [Android service types](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use) and [Flutter cached engines](https://docs.flutter.dev/add-to-app/android/add-flutter-screen#step-3-optional-use-a-cached-flutterengine).

No boot receiver or automatic bot restart is installed. Force-stop, process death and reboot require reopening the app and explicitly starting bots again; durable progress is retained. Keeping a wake lock and network polling uses battery. Android/OEM process termination and network outages remain possible.

The guide checks actual battery exemption, background restriction and notification state on every opening and settings return. Unknown state is incomplete. Skipping applies only to this opening; the warning stays fixed outside navigation/scrolling. Settings visits recheck state without an immediate duplicate prompt. Only documented Android settings intents are used.

## Verification

Bot cards now open users/inbox for both manual and plugin bots. Each card has a
separate settings gear. Mobile navigation uses a rounded bar with a centered
creation button, available on both tabs. The plugin configuration summary keeps
its read-only values and opens a separate schema-driven parameter editor from
its Edit button. Blank saved-secret inputs retain their secure values; secrets
are never prefilled. Saving changed parameters stages a fresh setup identity and
secure references before replacing the saved setup, preserving plugin preferences.
The old configuration survives a failed staged write. An active bot is stopped
before saving and restarted afterward; a stopped bot stays stopped. Automation
progress is isolated from the previous connection, so Inshopa establishes a new
baseline without sending paid history after connection changes. A no-op save
preserves the existing identity and progress. No Hive schema migration is needed.
Verification: all 65 unit/widget tests passed and analysis reported no issues.
The card navigation test covers both bot types at 390×844, the centered creation
button, the separate editor and empty secret inputs. Secure-write failure and
credential retention/replacement are covered against the actual repository.
Rendered previews are `build/verification/mobile-bot-navigation.png` and
`plugin-parameter-editor.png`; results are in `card-settings-*-final.log`.
The existing Linux preview hot-reloaded successfully without restarting its bots.

Android API 35 emulator integration passed: the Activity closed, process PID 5669 retained the service and partial wake lock, and the Dart isolate recorded 178 timer ticks in 45 seconds. Independent adb observation confirmed `isForeground=true`, service type `0x40000000`, launcher as the resumed Activity, and forced Doze `mState=IDLE` after battery exemption. Explicit Stop released the service. Temporary idle, battery and exemption settings were restored, then the disposable read-only emulator was stopped. This verifies runtime continuity, not live internet/Telegram delivery under every OEM condition.

Reproduce with `integration_test/background_service_test.dart` and `tool/verify_android_background.py` on the task's disposable read-only emulator. The observer refuses writable/personal-device targets and records `build/verification/android-background-observation.json`. No production debug bridge was added.

Order-polling update verification: all 63 unit/widget tests passed and `flutter analyze --no-pub` reported no issues. The normal Android debug APK rebuilt successfully with 0.5.0 and the timer fix below (`build/verification/local-live-apk-build.log`). New checks cover actual HTTP transport against a local contract fixture, lookup/path/secret validation, baseline and late-paid orders, restart behavior beyond 2,000 IDs, acknowledgement-storage failure, page pacing/Stop, and durable receipts after Hive reopening and per-bot deletion. Stop now cancels the polling/backoff timer itself; a regression test checks that no timer remains after Stop. See `build/verification/sales-*`, `flutter-analyze.log` and `flutter-test.log` for logs. The earlier separate API 35 background integration test passed; native background files were unchanged in this slice. Physical-device OEM behavior remains unverified.

Local live checks on 2026-11-09 used an owner-provided registered key against `127.0.0.1:8080`. The actual Dart HTTP/runtime path resolved the bound shop, returned its one product, and completed an empty-order baseline without historical alerts. `tool/inshopa_local_smoke.dart` repeats these read-only checks with a private connection-file path and emits a counts-only report. It does not send Telegram messages or mutate the shop. Reports are in `build/verification/inshopa-local-live-read.json`.

The opt-in `integration_test/inshopa_local_setup_test.dart` then initialized the normal Linux app, installed local package 0.5.0, added a new test bot without changing existing bots, verified secure API-key readback, completed the persisted initial scan and sent an authorized admin connection-test message. The owner confirmed receipt and a subsequent `/products` response from the normal running app. The report `build/verification/inshopa-local-app-setup.json` contains public identity and result flags only. A newly paid order and its alert remain pending: the local shop currently displays a purchase-unavailable notice, confirmed read-only in the storefront and by the owner. Shop activation belongs to Inshopa and was not changed here. These checks do not establish production-key access or Android delivery.

Linux uses the installed `libsecret`/GNOME Keyring service. A missing WSL session bus initially prevented secure storage; the same test passed in a standard `dbus-run-session` with the existing keyring. `tool/run_inshopa_local_preview.sh` accepts a private credentials-file path and runs the opt-in setup followed by normal `flutter run`. Run it within a desktop D-Bus session (for example `dbus-run-session -- bash tool/run_inshopa_local_preview.sh /absolute/private/telegram.json`). It keeps one native app/Hive owner at a time. Any keyring unlock is handled by GNOME's dialog. No plaintext fallback, empty-password keyring, credential-bearing build define or Inshopa-side change was introduced.

The owner-authorized requirements and planned Telegram connection-card context were sent to the Inshopa integration chat on 2026-11-09. Its later handoff confirmed the owner’s minimal existing-list contract, replacing the dedicated feed proposal. Bottogram now consumes that contract; no Inshopa source, database or production configuration was modified here.
