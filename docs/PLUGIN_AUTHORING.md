# Build a Bottogram plugin

A Bottogram plugin is one UTF-8 `.bottogram-plugin.json` file. It declares inputs,
preferences and automations made from capabilities already installed in Bottogram.
You can create a command bot, an API-backed list, a notification integration or
links to an existing website without adding service-specific code to the app.

This guide describes the current live contract: `manifestVersion: 2` and
`hostApiMajor: 2`. Use a Bottogram build that implements this contract; changing
version numbers in JSON cannot add capabilities to an older app. The pre-release
contract can change. Use current definitions; do not copy removed properties such
as `engine` or `storefrontUrlField`.

## Let an agent build it

Give this command to Codex in the project where you want the skill installed.
The current Skills CLI requires Node.js **22.20.0 or later**, with npm available:

```sh
npx skills add hayyaun/bottogram --skill bottogram-plugin-builder --agent codex --yes
```

For another coding agent, replace `codex` with its supported CLI identifier, or
omit `--agent codex --yes` to choose interactively. The command installs the
[Bottogram plugin-builder skill](../skills/bottogram-plugin-builder/SKILL.md);
it does not install a Bottogram plugin or create a bot by itself. After installing
the skill, ask the agent what you want built. For example:

```text
Use the bottogram-plugin-builder skill to make a plugin for my event service.
Add a private /portal command that opens my HTTPS event website, and optional
admin alerts when the documented events API reports a new ready event.
Here are the API docs and an anonymized JSON response: …
Deliver the .bottogram-plugin.json file, explain the requested credentials and
permissions, and show how to install and test it in Bottogram.
```

Provide the service's real API documentation and response shapes. Enter real bot
tokens and API keys in Bottogram, rather than putting them in the prompt or JSON.
The skill teaches the agent to use the supported contract, validate the result
and identify any missing host capability instead of inventing a component.

The GitHub command reads published repository contents. To try unpublished skill
changes from a local Bottogram checkout, run this from that checkout instead:

```sh
npx skills add . --skill bottogram-plugin-builder --agent codex --yes
```

## Make your first plugin

Save this complete file as `welcome.bottogram-plugin.json`. It needs no external
API or extra setup fields:

```json
{
  "manifestVersion": 2,
  "hostApiMajor": 2,
  "id": "example.welcome",
  "name": "Welcome bot",
  "version": "1.0.0",
  "executionStatus": "live",
  "description": "A private hello command built entirely from plugin JSON.",
  "setupFields": [],
  "automations": [
    {
      "id": "hello",
      "trigger": {
        "type": "telegram.command.v2",
        "config": {
          "commands": ["hello"],
          "chatTypes": ["private"],
          "arguments": "ignore"
        }
      },
      "actions": [
        {
          "id": "greet",
          "type": "telegram.reply.v1",
          "config": {
            "text": "Hello. This reply comes from your Bottogram plugin."
          }
        }
      ]
    }
  ]
}
```

1. Open **Plugins → Install from file** and choose the JSON file.
2. Review its identity and capabilities, then select **Install**.
3. Create a bot and choose **Welcome bot**. Enter the common bot name, Telegram
   bot token and numeric admin ID. The package does not contain these values.
4. Open the bot in Telegram, send `/start`, and start the bot in Bottogram.
5. Send `/hello` in a private chat. Stop the bot when testing is finished.

Installation only adds the package to the catalog. It does not start a bot or
switch existing bots to that package. Bots must be running to process new
commands and send notifications. A Mini App button already delivered to Telegram
can still open its website while Bottogram is stopped.

## Define identity and inputs

Required top-level properties are `manifestVersion`, `hostApiMajor`, `id`, `name`,
`version`, `executionStatus`, `setupFields` and `automations`.

- `id` is a stable lowercase identifier, such as `example.event-portal`. Use
  letters, digits and dot/hyphen separators; keep it within 100 characters.
- `version` is `major.minor.patch`, such as `1.0.0`, without a suffix.
- `name` is the displayed name, at most 100 characters. Optional `description`
  is at most 500 characters.
- Optional `requiresBotFields` accepts `"adminIds"`. Existing packages may use
  `"adminTelegramUserId"` for the same shared admin list. Include
  it when an automation uses `telegram.notify-admin.v1`.
- Optional `settings`, `errorMessages` and `telegram` add the facilities described
  below. Unknown properties are rejected.

`setupFields` declares at most 32 connection inputs. Each field has `key`, `label`,
`type` and a boolean `required`; optional properties are `helpText`, `default`,
`min` and `max`:

```json
[
  {
    "key": "portalOrigin",
    "label": "Portal URL",
    "type": "text",
    "required": true,
    "helpText": "The HTTPS website origin, for example https://events.example.com"
  },
  {
    "key": "accountId",
    "label": "Account identifier",
    "type": "text",
    "required": true
  },
  {
    "key": "apiKey",
    "label": "Event API key",
    "type": "secret",
    "required": true
  }
]
```

Supported field types are `text`, `secret` and `integer`. Integer fields can set
integer `min`/`max`. Public defaults are strings or integers and must satisfy the
field validation. Secret defaults are forbidden. Values are limited to 4,096
characters; field labels to 100 and help text to 300.

Field keys start with a letter and contain letters, digits or underscores, up to
64 characters. Keys must be unique across fields and settings. Do not redeclare
`name`, `token`, `botToken`, `adminIds` or `adminTelegramUserId`; those belong to the common
bot form. A required text field is not automatically a URL field: the relevant
header or Mini App capability validates its configured value when used.

### Editable preferences

Use `settings` for nonsecret preferences, not credentials:

```json
[
  {
    "key": "alertsEnabled",
    "label": "Notify about ready events",
    "type": "boolean",
    "default": true
  }
]
```

Every setting needs a typed `default`. Supported types are `string`, `boolean`,
`integer`, `number` and `enum`. Strings accept `minLength`/`maxLength`; numeric
types accept `min`/`max`; enums require an `options` array of distinct
`{"value": "normal", "label": "Normal"}` objects. There are at most 32 settings
and at most 32 options per enum. Preferences are saved separately for each bot.

Set an automation's `enabledBySetting` to a boolean setting key to enable or
disable that whole automation. This is the standard runtime's current setting
binding. Other preference types do not become template variables, HTTP fields
or component configuration automatically.

## Compose supported capabilities

Each automation has a unique `id`, one `trigger`, a nonempty `actions` array and
optional `enabledBySetting`. Each action also has an `id`, unique within that
automation. A component contains `type`, `config` and optional `errorMap`.
Trigger components have no separate `id`. Identifiers start with a letter and
can contain letters, digits, underscores and hyphens, up to 64 characters.

There can be 1–16 automations and 1–16 actions per automation. Actions run in
array order. A JSON file cannot register its own component type.

### Telegram commands and messages

- `telegram.command.v2`: `commands` is 1–16 distinct aliases, `chatTypes` is a
  nonempty list drawn from `private`, `group`, `supergroup`, `channel`, and
  `arguments` must be `"ignore"`. Commands contain lowercase letters, digits
  and underscores, start with a letter and are at most 32 characters. Command
  aliases cannot be reused by another automation in the same package.
- `telegram.command.v1`: `command` is one command name. Optional
  `arguments: "page"` accepts `/items` or `/items 2` and produces a page number
  from 1 to 10,000. This version has no configurable chat-type filter.
- `telegram.reply.v1`: replies to the command's chat with `text` and an optional
  `list`. It requires either command-trigger version.
- `telegram.notify-admin.v1`: uses the same message configuration but sends to
  all configured admins. It requires `requiresBotFields: ["adminIds"]`.
  A confirmed send is recorded per recipient so retrying an order skips admins
  who already received it.
- `telegram.reply.v2`: sends text plus a Mini App keyboard. It requires a
  `telegram.command.v2` trigger whose only chat type is `private`.

Command events contain `id`, `chatId`, `chatType` and, unless ignored, `arguments`.
Do not assume they expose user profiles, message text or arbitrary Telegram
update fields. The paged v1 trigger adds `page` and `nextPage`.

Message `text` supports scalar substitutions such as `{{event.id}}`.
An optional `list` declares `itemsPath`, `itemText` and literal `emptyText`:

```json
{
  "text": "Available events",
  "list": {
    "itemsPath": "results.events.items",
    "itemText": "• {{item.title}}",
    "emptyText": "No events found."
  }
}
```

`itemsPath` above starts at the event; `item` refers to the current list element.
Paths use object keys separated by dots. There are no array-index expressions,
functions, conditions, `settings`/`fields`/`secrets` namespaces or JavaScript.
Missing values render as empty text; object/array substitutions fail. Messages
are plain text, and the final message must fit Telegram's 4,096-character limit.
`emptyText` must be nonempty and at most 500 characters. Lists may contain at
most 100 items; design pagination to keep the actual output
within the message limit rather than relying on truncation.

### HTTP requests

Plugin HTTP components currently perform **GET requests only**. This is separate
from Bottogram's manual bot builder, which has other action capabilities.

A request has `method: "GET"`, a fixed `url`, optional `headers` and optional
`authentication`. Use HTTPS. HTTP is accepted only for literal loopback hosts
`localhost`, `127.0.0.1` and `::1`; a phone's loopback points to the phone.
URLs cannot contain credentials, fragments or `{{…}}` templates. A setup field
cannot replace the API hostname or URL. Only the list poller's explicit lookup
can bind complete path segments, as described below.

Public header values are literals or declared field bindings:

```json
{
  "method": "GET",
  "url": "https://api.events.example.com/v1/events",
  "headers": {
    "Accept": "application/json",
    "X-Account": {"field": "accountId", "transform": "value"},
    "X-Portal-Origin": {"field": "portalOrigin", "transform": "url.origin"},
    "X-Portal-Host": {"field": "portalOrigin", "transform": "url.authority"}
  },
  "authentication": {
    "type": "header",
    "header": "X-Event-Key",
    "secretField": "apiKey"
  }
}
```

This fragment assumes the three setup fields shown earlier and a real API that
uses those headers. Replace the example endpoint with its documented URL.
`value` takes a required public text/integer field. `url.origin` and
`url.authority` require a required text field containing an HTTP(S) origin:
scheme and hostname, optional port, no page path except `/`, credentials, query
or fragment. `url.origin` yields scheme plus authority; `url.authority` yields
host plus port where applicable. Dart's `Uri` performs URI normalization/encoding.
When a user omits the scheme, a hostname such as `events.example.com` resolves
as `https://events.example.com`; a numeric port and trailing root slash are
accepted. This rule applies only to declared origin bindings. Saved inputs,
ordinary text bindings, credentials and fixed API URLs are not rewritten.

Keep API registration and website navigation in separate setup fields when they
represent different origins. Bind request headers to the API's registered origin
and Mini App links to the public website origin. An API origin is not the API
server URL: the endpoint remains the literal `request.url`. For a local HTTP
registration, enter `http://` explicitly and retain its registered port, if any.
Defaulting a missing scheme to HTTPS does not provision TLS or change the API's
registration.

For bearer authentication, replace the authentication object with:

```json
{"type": "bearer", "secretField": "apiKey"}
```

The stored key must be a required `secret` field; Bottogram adds `Bearer `.
Custom-header authentication sends the stored value as that header's value.
Do not place a real credential in a header literal, a URL, a default or a message.

Header names are case-insensitive and must not collide. There are at most 32
headers including authentication; names are limited to 128 characters and values
to 8,192 printable ASCII characters plus horizontal tab. Transport headers such
as `Host`, `Content-Length` and `Connection`, plus cookie/proxy-session headers,
are reserved. Public `Authorization` headers are forbidden; use authentication.
The complete validation rules are in [http_headers.dart](../lib/runtime/http_headers.dart).

`http.get-json.v1` is an action with `request` and `resultKey`. Requests must return
HTTP 200 with a JSON object, not an array or another success status. It stores
that object at `event.results.<resultKey>` for later actions. Optional
`pagination: {"pageSize": 10}` accepts page sizes 1–10 and adds `limit`/`offset`
from the event's page number. For example, `resultKey: "events"` makes the
response's `items` available as `results.events.items` in the message-list example.

### Shared actions

A live manifest can declare up to 64 actions in the top-level `sharedActions`
array. Each uses the same `id`, `type`, `config` and optional `errorMap` as
an inline action.

```json
{
  "sharedActions": [
    {
      "id": "send-help",
      "type": "telegram.reply.v1",
      "config": {"text": "Send /help to see available commands."}
    }
  ]
}
```

In an automation's `actions` list, use `{"ref": "send-help"}`. To give the
occurrence a different ID, use `{"ref": "send-help", "id": "show-help"}`.
Inline actions and references can appear in the same list. Each occurrence
must have a unique ID within its automation and must meet that automation's
trigger and configuration rules. References reuse the full definition.

### Shared buttons and keyboard rows

Declare reusable definitions by ID in `sharedButtons` and
`sharedKeyboardRows`, with up to 64 entries in each map.

```json
{
  "sharedButtons": {
    "my-orders": {
      "text": "My orders",
      "webApp": {"originField": "storefrontUrl", "path": "/orders"}
    }
  },
  "sharedKeyboardRows": {
    "orders-and-support": [
      {"ref": "my-orders"},
      {"text": "Support", "callback": "support"}
    ]
  }
}
```

In `telegram.present.v1`, both `keyboard` and `list.keyboard` can use a row
reference such as `[{"ref": "orders-and-support"}]` or a button reference
such as `[[{"ref": "my-orders"}]]`. The same syntax works in
`telegram.reply.v2`'s `inlineKeyboard` for Mini App buttons. A named row
can contain inline buttons and button references. Each expanded keyboard
must follow the limits and destination rules of the action that uses it.

### Shared presentation lists

In a live manifest, use `sharedLists` to define up to 64 named list
configurations. Set `config.list` in a `telegram.present.v1` action to
`{"ref": "catalog-products"}` to use the definition below.

```json
{
  "sharedLists": {
    "catalog-products": {
      "itemsPath": "results.catalog.items",
      "data": {"title": {"text": "{{item.title}}", "maxLength": 44}},
      "keyboard": [[{"text": "{{item.title}}", "callback": "product:{{item.id}}"}]],
      "emptyText": "No products on this page."
    }
  }
}
```

The shared definition uses the same fields as an inline list, including
optional `lookup` and shared button or row references in `keyboard`. The
action still controls its own message lines and widget layout. A list
reference takes only `ref`; define another list when its content needs
to differ.

### Scheduled API notifications

Poll triggers use an interval from 30 to 86,400 seconds and explicitly choose
`initialSync: "baseline"` or `"replay"`. Baseline acknowledges the initial scan
without sending historical notifications. Replay processes the initial items.

`http.poll-list.v1` supports a paged current-state list. This is a trigger
configuration for a service returning `{"events": [{"id": "evt-1", "state":
"ready", "title": "Doors open"}]}`:

```json
{
  "intervalSeconds": 60,
  "initialSync": "baseline",
  "request": {
    "method": "GET",
    "url": "https://api.events.example.com/v1/events",
    "authentication": {"type": "bearer", "secretField": "apiKey"}
  },
  "response": {"itemsPath": "events", "itemIdPath": "id"},
  "pagination": {
    "limitQueryParameter": "limit",
    "offsetQueryParameter": "offset",
    "pageSize": 100,
    "maxPages": 1000,
    "pageDelaySeconds": 2
  },
  "filter": {"path": "state", "equals": "ready"}
}
```

Declare the required secret field and compose this trigger with
`telegram.notify-admin.v1`, for example `text: "Ready event: {{event.title}}"`.
Scheduled triggers cannot use reply actions or derive a message destination
from an API item; notification messages go to the configured admin.
Its optional filter uses exact equality against a string, boolean or finite
number, and the filter field must exist on each raw item. An item's ID is a
nonempty string/integer of at most 256 characters;
Bottogram exposes the normalized string as `event.id`.

Page size is 1–100, `maxPages` is 1–10,000, and page delay is 1–60 seconds.
Pagination advances using the raw list size before filtering. A full raw page
causes another request; the API must return a short/empty final page. Exceeding
the declared scan limit stops the automation with an error.

An optional `lookup` can fetch a resource ID before scanning:

```json
{
  "lookup": {
    "request": {"method": "GET", "url": "https://api.events.example.com/v1/account"},
    "bindings": {"accountId": "id"}
  },
  "request": {
    "method": "GET",
    "url": "https://api.events.example.com/v1/accounts/{accountId}/events"
  }
}
```

This is a fragment to merge into the list-poll configuration. Each request needs
its own authentication/headers when the API requires them. Lookup bindings must
read string IDs consisting of letters, digits, underscores or hyphens, up to
256 characters. There are at most eight bindings, and each must fill a complete
path segment. They cannot populate a scheme, host, query or a message variable.

`http.poll.v1` instead consumes an API with its own synchronization checkpoint.
Its `response` declares `itemsPath`, `itemIdPath`, `checkpointPath`; its
`pagination` declares `cursorQueryParameter`, `nextPagePath`, `hasMorePath`.
The checkpoint must be a nonempty string, and every page in one cycle must keep
the same checkpoint. The API supplies a boolean `hasMore` and, when true, a new
nonempty next-page string. Cursor/checkpoint strings are at most 4,096 characters,
and a response page contains at most 100 items. Confirm those semantics with
the API author; do not
invent a cursor by treating a timestamp as a checkpoint.

## Open an existing website in Telegram

Declare the website origin as a required text field, then use an origin-field
reference and a literal same-origin path:

```json
{
  "text": "Open your event portal.",
  "inlineKeyboard": [
    [
      {"text": "Open portal", "webApp": {"originField": "portalOrigin", "path": "/"}},
      {"text": "My tickets", "webApp": {"originField": "portalOrigin", "path": "/tickets"}}
    ]
  ]
}
```

Use that as a `telegram.reply.v2` configuration with a private
`telegram.command.v2` trigger. Labels are 1–64 characters; keyboards support
1–8 rows of 1–8 buttons. Paths begin with `/`, cannot begin with `//`, and cannot
contain a query, fragment, whitespace, backslash or template. The configured
origin must be HTTPS, without credentials, a page path, query or fragment.
Origin values and declared paths are each limited to 2,048 characters.
A scheme-less hostname uses HTTPS automatically, including in an existing saved
setup. An explicitly entered HTTP origin still fails the Mini App check.

Optional top-level `telegram` config declares a menu button, a native command
list, or both:

```json
{
  "commands": [
    {"command": "hello", "description": "Show the welcome message"}
  ],
  "menuButton": {
    "text": "Event portal",
    "webApp": {"originField": "portalOrigin", "path": "/"}
  }
}
```

`commands` contains 1–100 unique command/description objects. Names have no `/`
and use lowercase letters, digits or underscores (1–32 characters); each must
also be handled by a declared `telegram.command.v2` trigger that includes private
chats. Descriptions are nonblank plain text, 1–256 characters, without control
characters. Publish the main commands here; aliases can remain in triggers.
Bottogram uses Telegram's supported
[`setMyCommands`](https://core.telegram.org/bots/api#setmycommands) API with the
all-private-chats scope and the default language. Telegram can still prefer an
existing language-specific or narrower-scope command list; this declaration
does not delete those overrides. It replaces the default private command list
when the bot starts. Omit `commands` to leave it untouched. Menu and command synchronization
are independent; a failed synchronization does not stop message automations.

The website owns its authentication and sessions. A Telegram identity does not
automatically authenticate a website account. Do not route website passwords,
one-time sign-in codes or browser sessions through the bot. Verify login,
account switching and payment-return behavior in real Telegram clients; do not
assume cookies are shared with an external browser. Telegram's applicable
[payment rules](https://core.telegram.org/bots/payments-stars), including Stars
for digital goods sold inside Telegram, still apply.

## Give your integration useful errors

Define reusable top-level `errorMessages`, then map host codes on the component
that can fail. `errorMap` is beside `config`, not inside it:

```json
{
  "errorMessages": {
    "eventAccessDenied": {
      "title": "Event access denied",
      "message": "The event service rejected this connection.",
      "help": "Check the API key and its account permissions.",
      "action": "editPluginParameters"
    }
  }
}
```

```json
{
  "id": "load-events",
  "type": "http.get-json.v1",
  "errorMap": {
    "http.unauthorized": "eventAccessDenied",
    "http.forbidden": "eventAccessDenied"
  },
  "config": {
    "request": {
      "method": "GET",
      "url": "https://api.events.example.com/v1/events",
      "authentication": {"type": "bearer", "secretField": "apiKey"}
    },
    "resultKey": "events"
  }
}
```

These are fragments of one package; the resource and required `apiKey` field
must exist in that package. Resources require `title` and `message`; optional
`help` explains recovery. Optional `action` is `editPluginParameters` or `retry`,
which displays a user-initiated host action. A package does not execute recovery
code. At most 64 resources/mappings are accepted; titles are at most 100
characters, message/help text at most 2,000 each. Error text is literal plain
text without interpolation, response bodies or exception data.

Useful host codes include `http.unauthorized`, `http.forbidden`,
`http.rate_limited`, `http.timeout`, `http.invalid_response`,
`http.request_failed`, `http.invalid_headers`, `http.invalid_origin`,
`http.credentials_unavailable`, `poll.invalid_response`,
`poll.scan_limit_exceeded`, `message.invalid_list`, `message.too_long`,
`configuration.invalid_public_origin` and `telegram.delivery_unconfirmed`.

Mappings are component-local. They change presentation, never retry policy,
permanence or acknowledgements. Unmapped failures retain sanitized host text.
The host's delivery-uncertainty notice cannot be replaced by a plugin resource.

## Recovery, limits and package updates

Requests time out after 22 seconds, responses are bounded to 1 MiB, redirects are
not followed, and progress records are limited to 2 MiB. Transient failures use
capped backoff; numeric `Retry-After` values are honored. Authentication and
contract failures can stop an automation until the configuration is corrected.

The runner saves each action acknowledgement before advancing the source
checkpoint. List polling keeps durable receipts for baseline/completed IDs;
cursor polling and commands use a bounded recent-ID cache. State is isolated by
bot instance, package digest and automation ID. List receipts grow with observed
IDs and are removed with the bot.

This does not provide exactly-once delivery: if Telegram accepted a message but
confirmation or its durable acknowledgement was lost, retrying can duplicate
it. A current-state offset list is also not a durable event log. Changes between
requests or shifting pages can cause missed observations. Document the service's
actual guarantees and give distinct events distinct stable IDs.

Installed versions are immutable and bots pin the package's source digest.
Increase `version` whenever you distribute changed bytes under the same ID.
After installing a compatible release, choose **Update available** on the
existing bot, then review and approve the version change.

The reviewed updater can preserve compatible configuration and unchanged
background execution definitions, including progress and receipts. Error
catalogs/maps are presentation metadata, excluded from execution comparison.
Changed setup semantics, setting defaults or background automations require a
separately designed transition; do not promise automatic state reuse. Navigation
commands may be replaced by the reviewed update path. Approving an update
pauses a running bot and restarts it after the new version is applied.
Invalid Mini App origins reject the update without rewriting saved values.

See [runtime and recovery details](PLUGIN_RUNTIME.md) for implementation notes.

## Validate and share

Before sharing a package:

- Parse the complete file through the current `PluginManifest` or import it in
  Bottogram. A JSON syntax check alone does not validate component contracts.
- Confirm all requested URLs, API permissions, response paths and stable IDs
  against actual service documentation and anonymized fixtures.
- Test command chat restrictions, empty/large lists, invalid credentials, rate
  limits, Stop/Start, initial baseline/replay, and any reviewed update you claim
  to support. Test website behavior in Telegram separately from API fixtures.
- Keep tokens, API keys, buyer data and local application exports out of the
  package, screenshots, logs and repository. Share the definition and setup
  instructions, not a configured bot or its secure-storage contents.

For a Bottogram source checkout, use the pinned Flutter/Dart toolchain and install
dependencies as documented in the [README](../README.md#development), then run
the validator against your package:

```sh
dart run tool/validate_plugin.dart path/to/example.bottogram-plugin.json
```

The validator uses the same `PluginManifest` parser as the app. It checks the
package without contacting its API or starting a bot. The first Dart invocation
may prepare the project's declared native build hooks, so the source checkout
still needs its documented development toolchain. An agent without that checkout
can generate the package from the skill reference, but should distinguish a JSON
syntax check from a schema-validated package and complete import validation in
Bottogram.

Focused host contract checks are:

```sh
flutter test --no-pub test/plugins_test.dart test/plugin_contract_schema_test.dart test/http_headers_test.dart test/plugin_error_contract_test.dart test/telegram_plugin_capabilities_test.dart
```

The parser, registrations and validators are the source of truth:
[manifest](../lib/plugins/manifest.dart), [components](../lib/runtime/registry.dart),
[headers](../lib/runtime/http_headers.dart), [errors](../lib/runtime/failure_presentation.dart)
and [Telegram links](../lib/runtime/telegram_config.dart).
The [example packages](../examples/plugins) show full API/navigation/polling
compositions; service-specific names, endpoints and rules stay in those files.

If a request needs a webhook server, an unsupported HTTP method, a new kind of
Telegram interaction, arbitrary code, or another unregistered capability, a JSON
package cannot add it. Describe the missing general capability and implement it
in the host with schema validation and appropriate checks, then compose it in
the plugin. Do not add branches for a particular plugin ID, service or template.

## Interactive Telegram menus, widgets and channel posts

A plugin can use a command menu with `telegram.menuButton: {"type": "commands"}`.
Publish buyer-facing commands in `telegram.commands`. If the plugin requires the
shared admin ID, `telegram.adminCommands` adds entries to that person's private
menu. Match those entries with `audience: "admin"` routes so Telegram sender IDs
are checked when a command or button is used.

- `telegram.interaction.v1` accepts private-chat command, inline callback, and
  HTML widget routes. Each route declares `kind`, `name`, and `argument`
  (`none`, `page`, or `uuid`). Argument-bearing callbacks use `name:value`.
  Commands can require a literal argument `prefix`, such as a deep-link prefix.
  Set `failureText` to a short recovery message in the plugin's language.
- `telegram.present.v1` renders bounded message lines and inline actions. A
  `widget` declares HTML and a mapping from scalar values to chat data. A
  paginated list can render both widget rows and text keyboard rows. Telegram
  limits widget state to 1 KiB and accepts these widgets in private chats.
  Provide a plain-text command for clients that cannot display them.
- `http.get-json.v1` can bind event values to complete URL path segments.
  Pagination with `pageSize` and `itemsPath` fetches one extra result and exposes
  `items`, `page`, `previous`, and `next` under the action's result key.
- For Telegram broadcasts, declare a `telegramChats` setup field with allowed
  `chatTypes`, using `channel`, `group`, or `supergroup`. The field accepts up
  to twelve negative numeric IDs separated by commas or line breaks. Reference
  it with `channelField` in the final `telegram.present.v1` action of a
  `http.poll-list.v1` automation. To attach a `photo`, use a required public
  HTTPS origin field and a bounded resource ID. Each chat gets a separate
  baseline, retry schedule and delivery receipts. Channels require the bot's
  post permission, and groups require permission to send the configured content.
- `telegram.status.v1` can report the current destination posting permissions and a
  boolean plugin setting from an admin-only interaction.

See the [Inshopa 0.8.8 package](../examples/plugins/inshopa.storefront.0.8.8.bottogram-plugin.json)
for complete declarations, including a Telegram deep link generated from the
bot's username and a same-origin Mini App button with a bound path segment.

To show photos in a widget list, declare the photo source under
`widget.thumbnails.photo` and put the literal `/*widget-rows*/[]` in the
widget script as an array expression. Bottogram fills the array from the
`list.data` bindings and adds a resized JPEG data URL as `thumbnail` when
available. Set `widget.thumbnails.allowWebp` to `true` to also allow WebP
when choosing a quality and resolution that fit the widget limit. With WebP
enabled, Bottogram can use images up to 128 px and include row values in
`chat_data` when they fit its byte limit. To look up extra fields per row,
declare `list.lookup` with a GET
`request`, URL path `parameter` and `itemIdPath`. Its response is available
under `item.detail`. An optional `minimum` computes the lowest nonnegative
number in a response list. Bottogram packs up to ten rows, keeps them available
when photos fail and sends a new widget on page navigation.
