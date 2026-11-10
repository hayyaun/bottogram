# Current Bottogram plugin contract

This reference describes the registered manifest v2 / host API v2 capabilities.
It is bundled with the skill so an installed skill can author packages without
a sibling Bottogram checkout. For a different host release, inspect its current
parser or [published guide](https://github.com/hayyaun/bottogram/blob/main/docs/PLUGIN_AUTHORING.md).

## Package envelope

The file is a UTF-8 JSON object, at most 256 KiB. Unknown properties and component
types are rejected. Live packages contain:

```json
{
  "manifestVersion": 2,
  "hostApiMajor": 2,
  "id": "example.status",
  "name": "Service status",
  "version": "1.0.0",
  "executionStatus": "live",
  "setupFields": [],
  "automations": []
}
```

This envelope is incomplete until it contains 1–16 valid automations. Each has
`id`, `trigger`, `actions` and optional `enabledBySetting`. Each trigger has
`type`, `config` and optional `errorMap`. Each of the 1–16 actions also needs a
unique `id` within its automation. Automation IDs are unique within the package.

Allowed optional top-level properties: `description`, `requiresBotFields`,
`settings`, `errorMessages`, `telegram`. Do not add `engine`, arbitrary metadata,
JavaScript or a downloadable executable.

- Plugin IDs: lowercase letters/numbers with dot or hyphen separators, beginning
  with a letter; maximum 100 characters. Versions are numeric `major.minor.patch`
  without prerelease/build suffixes.
- Component/automation identifiers: letter followed by letters, numbers,
  underscores or hyphens; maximum 64 characters.
- Data paths: dot-separated object keys, each beginning with a letter and
  containing letters, numbers or underscores. No JSONPath, arrays or expressions.

## Setup fields and preferences

`setupFields` contains 0–32 objects with required `key`, `label`, `type`,
`required`. Types are `text`, `secret`, `integer`. Optional properties are
`helpText`, `default`, `min`, `max`; numeric bounds apply only to integers.
Secret fields have no default. Other defaults are strings or integers and must
satisfy the field's validation. Values are at most 4096 characters.

Field keys begin with a letter and contain letters, numbers or underscores, up
to 64 characters. Keys must be unique across setup fields and preferences.
`name`, `token`, `botToken`, `adminTelegramUserId` are reserved host fields.

`requiresBotFields` can contain only `"adminTelegramUserId"`; declare it when
using admin notifications. Never duplicate it in `setupFields`.

`settings` contains 0–32 non-secret preferences, each with `key`, `label`, `type`
and a correctly typed `default`. Types are `string`, `boolean`, `integer`,
`number`, `enum`; optional `helpText` is supported. Numeric preferences accept
`min`/`max`; strings accept `minLength`/`maxLength` within 0–4096. An enum has
1–32 `options` objects containing unique string `value` and a `label`.

Only boolean preferences currently control execution, via an automation's
`enabledBySetting`. Other preference types are UI/storage values, not message,
URL, interval or header bindings. There is no settings interpolation syntax.

## HTTP request object

The same request object is used by HTTP actions and polling triggers:

```json
{
  "method": "GET",
  "url": "https://api.example.test/v1/status",
  "headers": {
    "Accept": "application/json",
    "X-Account": {"field": "accountId", "transform": "value"},
    "Origin": {"field": "portalOrigin", "transform": "url.origin"},
    "X-Portal-Host": {"field": "portalOrigin", "transform": "url.authority"}
  },
  "authentication": {"type": "bearer", "secretField": "apiKey"}
}
```

Replace illustrative API URLs and response paths with a verified API contract.
HTTP request keys are only `method`, `url`, `headers`, `authentication`.
Requests are GET-only, with no body. URLs are literal HTTPS URLs, except literal
loopback HTTP hosts (`localhost`, `127.0.0.1`, `::1`). No credentials or fragments
in URLs. There are no setup-field, message-template, environment or secret URL
substitutions. The list-poll lookup below is the sole path-binding mechanism.

`headers` is optional and maps names to literal strings or `{field, transform}`.
Bindings must reference declared required non-secret fields. `value` permits a
text or integer field; `url.origin` and `url.authority` require text containing
an HTTP(S) origin, with no credentials, page path, query or fragment. Authority
includes the port when present. URI parsing performs its normal encoding.

Names are HTTP tokens, maximum 128 characters, case-insensitively unique. Values
are printable ASCII plus horizontal tab, maximum 8192 characters. At most 32
headers including authentication. Transport-managed names such as `Host`,
`Content-Length`, `Connection` and `Transfer-Encoding` are unavailable. Cookie,
Set-Cookie and proxy-session headers are unavailable. `Authorization` cannot be
a public header.

Authentication is optional and references a required secret setup field. Use
either `{ "type": "bearer", "secretField": "apiKey" }` or
`{ "type": "header", "header": "X-API-Key", "secretField": "apiKey" }`.
A bearer declaration cannot also specify `header`. Authentication cannot collide
with a declared public header or use transport/session header names. Never put
the actual credential in a literal header.

Transport timeout is 22 seconds; responses must be HTTP 200 JSON objects up to 1 MiB.
Redirects are refused. The host owns retry classification and capped backoff,
including numeric `Retry-After` handling.

## Registered triggers

### `telegram.command.v2`

```json
{"commands":["status","health"],"chatTypes":["private"],"arguments":"ignore"}
```

Use 1–16 unique commands without `/`, each matching lowercase
`[a-z][a-z0-9_]{0,31}`. A command cannot be registered twice across automations.
Chat types are an explicit nonempty subset of `private`, `group`, `supergroup`,
`channel`. `arguments` must be `ignore`.

Command events contain `id`, `chatId`, `chatType`; v2 removes `arguments`.
No `firstName` or user profile fields are supplied. Commands are not filtered
to the admin automatically. Do not expose private API data through public chat
commands merely because a provider credential is valid.

### `telegram.command.v1`

`config` is `{ "command": "items", "arguments": "page" }` or omits
`arguments`. This registration accepts all chat types. The optional `page` mode
parses one positive page argument (1–10000), defaults to page 1, and puts it in
`event.page`; the host handles invalid arguments. It is useful with fixed
limit/offset HTTP action pagination. It is not a free-form search-input binding.

### `http.poll.v1`

```json
{
  "intervalSeconds": 60,
  "initialSync": "baseline",
  "request": {"method":"GET","url":"https://api.example.test/v1/events"},
  "response": {"itemsPath":"events","itemIdPath":"id","checkpointPath":"sync.checkpoint"},
  "pagination": {"cursorQueryParameter":"cursor","nextPagePath":"sync.nextCursor","hasMorePath":"sync.hasMore"}
}
```

The API must supply an actual checkpoint/cursor contract. Do not infer one from
timestamps or an ordinary offset list. `intervalSeconds` is 30–86400;
`initialSync` is `baseline` or `replay`. Every page in one scan must share its
checkpoint. Checkpoint strings and advancing next cursors are nonempty and at
most 4096 characters. `hasMorePath` resolves to a boolean; pages have at most
100 items. Each item is an object with a stable string/integer ID of at most
256 characters. The host normalizes that ID to `event.id`.

### `http.poll-list.v1`

```json
{
  "intervalSeconds": 60,
  "initialSync": "baseline",
  "request": {"method":"GET","url":"https://api.example.test/v1/updates"},
  "response": {"itemsPath":"items","itemIdPath":"id"},
  "pagination": {"limitQueryParameter":"limit","offsetQueryParameter":"offset","pageSize":100,"maxPages":1000,"pageDelaySeconds":2},
  "filter": {"path":"state","equals":"ready"}
}
```

This scans a current-state offset list. Intervals and initial sync match the
cursor trigger. Page size is 1–100, max pages 1–10000, page delay 1–60 seconds;
limit and offset parameter names must differ. A raw page containing exactly
`pageSize` items continues at `offset + pageSize`; a partial or empty raw page
ends the current scan cycle. Filtering never changes pagination, so a full page
with zero matching items still advances to the next offset. The optional filter
compares one object path with a literal string, boolean or finite number.
Missing filter fields are errors.

An optional `lookup` is `{ "request": REQUEST, "bindings": {"resourceId":"id"} }`.
It supports 1–8 ID bindings from a lookup JSON object. Their values must be
strings matching `[a-zA-Z0-9_-]{1,256}`. The main URL can then use complete path
segments such as `/v1/resources/{resourceId}/updates`. All bindings must be used;
they cannot change the scheme, authority or query. Lookup is cached for that
trigger instance.

Matched events preserve item fields and receive normalized `id`. Polling
automations cannot use reply actions; use the configured admin notification
action for background delivery. Offset continuation is local progress, not a
server-issued cursor or consistent-snapshot guarantee. All pages are revisited.

`baseline` records initial matching IDs without sending history; `replay` sends
initial matching items. List-poll delivery receipts are durable and grow with
observed IDs. A state that appears and disappears between checks can be missed.

## Registered actions

### `http.get-json.v1`

`config` has `request`, `resultKey`, optional `pagination: {"pageSize": 10}`.
Page size is 1–10. Pagination always sends `limit` and `offset`, using
`event.page` or 1; it cannot declare custom pagination parameter names here.
The parsed response object is stored at `event.results.RESULT_KEY` directly,
without a synthetic `body` wrapper. `event.page` and `event.nextPage` are set.

For example, an API object `{ "state": "operational" }` saved under resultKey
`service` can be rendered as `{{event.results.service.state}}`.

### `telegram.reply.v1` / `telegram.notify-admin.v1`

Both accept `text` and optional `list`. Reply requires a command trigger and
sends to that event's chat; admin notification sends to the configured host
admin and requires `requiresBotFields: ["adminTelegramUserId"]`.

`list` is `{ "itemsPath": "results.service.items", "itemText": "{{item.title}}", "emptyText": "No items." }`.
`emptyText` is nonempty and at most 500 characters.
It must resolve to at most 100 items. The host appends rendered items (or empty
text) to the main text; it does not truncate or split oversized messages.

### `telegram.reply.v2`

This accepts `text` and a required `inlineKeyboard`. It requires a
`telegram.command.v2` trigger with exactly `chatTypes: ["private"]`, even when
the text itself contains no sensitive information. Buttons are Mini App buttons:

```json
{
  "text": "Open the portal below.",
  "inlineKeyboard": [[{"text":"Open portal","webApp":{"originField":"portalOrigin","path":"/"}}]]
}
```

There are 1–8 rows of 1–8 buttons; labels are 1–64 characters. Supported button
keys are only `text` and `webApp`. Do not invent callback, URL or expression
buttons in this component.

### Message templates

`text` / `itemText` are nonempty, at most 4096 characters. Only
`{{event.some.path}}` and `{{item.some.path}}` substitutions exist; values must
be string, number or boolean. Missing paths become empty text, not schema
errors. Inspect response fixtures to catch misspelled paths. No indexing,
conditionals, arithmetic, functions or other namespaces are supported.
Rendered Telegram messages must fit 4096 characters. These declarations have
no configurable parse mode or Markdown expression engine.

## Mini App targets and menu

Every `webApp` is `{ "originField": "portalOrigin", "path": "/account" }`.
The field must be a declared required non-secret text setup field. Its configured
value must be an HTTPS origin, not a page URL, credentials, query or fragment.
Paths are literal, start with one `/`, stay on that origin and have no authority,
query, fragment, whitespace, backslash or interpolation.

Optional top-level menu configuration is:

```json
{"telegram":{"menuButton":{"text":"Open portal","webApp":{"originField":"portalOrigin","path":"/"}}}}
```

Opening a page does not authenticate its visitor. The website owns login and
authorization; Telegram identity is not a substitute. Existing buttons may open
their page while Bottogram is stopped; command replies and background alerts
need a running bot. Verify real Telegram login/payment behavior separately when
it is part of the requested integration.

## Plugin-owned error presentation

```json
{
  "errorMessages": {
    "accessDenied": {
      "title": "Service access denied",
      "message": "The service rejected this connection.",
      "help": "Check the saved API key and required permissions.",
      "action": "editPluginParameters"
    }
  }
}
```

On the relevant trigger or action, as a sibling of `config`, add
`"errorMap": { "http.unauthorized": "accessDenied", "http.forbidden": "accessDenied" }`.
Mappings are component-local, have at most 64 entries and must name a declared resource. A catalog has
at most 64 resources, each with required `title` (100 chars) and `message`
(2000 chars), optional `help` (2000 chars), and optional action
`editPluginParameters` or `retry`. Resource IDs start with a letter and allow
letters, numbers, underscores, dots and hyphens, up to 64 characters.

Text is literal, with no interpolation, response body, exception, URL action,
retry policy or severity fields. Recovery actions are initiated by the user.
Common stable host codes include `http.unauthorized`, `http.forbidden`,
`http.rate_limited`, `http.timeout`, `http.request_failed`, `http.invalid_response`,
`http.invalid_headers`, `http.invalid_origin`, `http.credentials_unavailable`,
`poll.invalid_response`, `poll.invalid_progress`, `poll.scan_limit_exceeded`,
`configuration.invalid_public_origin`, `message.invalid_template`,
`message.invalid_list`, `message.too_long`, `message.no_destination` and
`telegram.delivery_unconfirmed`.

Unmapped failures retain sanitized host wording. Plugins cannot hide the host's
delivery-uncertainty notice or change retry/permanence/acknowledgement semantics.
Telegram may have accepted a send whose acknowledgement was lost; retries can
duplicate that message. Do not promise exactly-once delivery.

## Installation and state

Import through **Plugins → Install from file**, inspect capabilities, then
select the installed package when creating a bot. The user supplies the shared
Telegram token/admin and plugin inputs in Bottogram, then explicitly starts it.

An installed ID/version cannot be replaced with different bytes. Give revisions
a new version. Existing bots remain pinned until an explicit reviewed update.
The host compares retained setup/settings semantics and automation execution
definitions before reusing compatible progress. Changed connection parameters
or background behavior need their own state decision; never hand-edit saved
boxes or promise that an arbitrary package edit preserves polling state.

Actions are acknowledged before source progress advances. Stop drains pending
acknowledgements; source progress is scoped by bot instance, package digest and
automation. This is host behavior, not plugin-controlled state serialization.
