# Action builder

Manual bots can connect actions through named outputs, call external JSON APIs,
use persistent variables and run SQL against their own database. The existing
command, text, callback-query and inline-query events remain available. A polling
timer can run a chain immediately on Start and then at a chosen interval.

The **Store** includes seven general bot templates built from the same events
and actions. See [setup, editable samples and template behavior](BOT_TEMPLATES.md).
The general builder also supports literal prefix/any-text matching with
**event.input**, and **Render list** outputs **text**, **keyboard** and **count**
for formatting SQL/API arrays. Bind **steps.list.keyboard** through the next
message action's **Keyboard output reference**.

## Build a chain

Open a bot's settings, choose an event and add an action. Each action has a unique
output name. Actions run in their displayed order; the up arrow changes that
order. Renaming an output or moving its consumer before its producer requires
updating the affected references.

For example:

1. Add **Call external API**, name its output `lookup`, and enter the API URL.
2. Add **Send text** with `Price: {{steps.lookup.body.price}}`.
3. Optionally add **Edit message text** with target message ID
   `{{steps.answer.messageId}}`, where `answer` is the preceding text action's
   output name.

API requests support GET, POST, PUT, PATCH and DELETE, JSON headers and JSON
bodies. A URL's host is fixed; bindings in path and query components are encoded
as component values. Saved bearer credentials come from **Variables and API
credentials** and remain in platform secure storage. Credentials, arbitrary
response bodies and parameter values are not written to the execution console.
An HTTP redirect is reported as a failure instead of following it.

## Reuse an action

Open an action and choose **Save to action library** in the toolbar. Name it
and choose **Save and link** to replace that event's action with a reference.
In any manual bot, open an event, choose **Add action**, and select the entry
under **Action library**.

Editing a shared action changes its settings for all linked events. Each event
keeps its own output name, and removing the action from an event removes that
link. When the action uses earlier outputs, variables, credentials or callback
events, configure those dependencies in each destination bot. A bot backup
contains editable copies of its linked actions, independent of the library.

## Reuse lists and button rows

In **Render list**, use **Save list to library** or **Choose saved list**.
Linked lists share item formatting, rich layout, and row buttons. Each
event selects its own **Items reference** and output name. **Make local
copy** detaches the list layout so you can edit it independently.

In a keyboard editor, save an existing row, create a **New shared row**,
or **Choose saved row**. You can also use inline rows in the item buttons
and footer of **Render list**. Editing a shared row updates every action
that links to it. Add the appropriate callback handler in each bot when a
row uses dynamic callback data. Bot backups carry copies of all linked pieces.

## References and types

- `{{event.text}}`, `{{event.firstName}}`, `{{event.username}}`
- `{{event.userId}}`, `{{event.chatId}}`, `{{event.messageId}}`
- `{{event.arguments.0}}` for a command's first argument and
  `{{event.argumentsText}}` for the full text after the command
- `{{event.inputParts.0}}` and `{{event.inputParts.1}}` for a matching suffix
  split by the optional separator on a **Starts with** trigger
- `{{event.callbackData}}` and `{{event.query}}`
- `{{user.score}}` or `{{bot.total}}` for declared variables
- `{{steps.lookup.body.items.0.price}}` for a JSON response field
- `{{steps.query.rows.0.score}}` for a SQL result field
- `{{steps.sent.messageId}}` and `{{steps.sent.chatId}}` for a sent message

The value picker lists common event fields, declared variables and earlier step
outputs. Enter a more specific response path when an API returns nested data.
Missing or null fields fail the action with the missing path in the console;
they are not silently substituted with empty text.

In a JSON payload, an entire string reference preserves the original JSON type:
`{"amount":"{{steps.lookup.body.price}}"}` sends a number when `price` is numeric.
Mixed text such as `"Price: {{steps.lookup.body.price}}"` remains a string.
Text fields require scalar values; select an individual field from objects or
arrays.

## Telegram actions and formatting

Actions include text, dice, editing text or inline buttons, acknowledging button
clicks, answering an inline query, photo, video, document, audio, voice, animation,
sticker, deleting a message and pinning a message. Telegram permissions and its
method-specific limits still apply. Media accepts a Telegram file ID or an
HTTP(S) URL. Generic actions cannot read local filesystem paths.

Blank targets use the triggering conversation and message. Polling events have
no conversation or user, so sending a message from a timer requires an explicit
chat target. User variables also require an event with a Telegram user.

New text actions can use the Telegram MarkdownV2 source editor. Its toolbar
inserts bold, italic, underline, strikethrough, spoiler, inline code, code blocks,
links, mentions, quotes and expandable quotes. More formatting includes custom
emoji syntax; Telegram's eligibility requirements still apply. Literal
MarkdownV2 punctuation must be escaped. Variable insertions are escaped for
normal text, code or link-target context automatically. Existing plain-text
actions retain plain text until their format is changed.

Button notifications should precede slow API calls because Telegram callback
queries expire. Inline answers currently return one configurable article result
with personal caching disabled.

### Rich messages

In **Send text** or **Edit message text**, open **Rich message** to supply
structured blocks. When blocks are provided, Telegram displays them in place of
the plain message field. Bindings are inserted as literal text.

```json
[
  {"type":"heading","text":"Order summary"},
  {"type":"table","rows":[["Item","Quantity"],["{{steps.lookup.body.name}}",2]]},
  {"type":"details","summary":"Notes","blocks":[{"type":"paragraph","text":"Packed for delivery."}]},
  {"type":"buttons","buttons":[{"text":"Refresh","callback_data":"refresh"}]}
]
```

Text blocks are `heading`, `paragraph` and `footer`. Use `list` with
`items`, `table` with `rows` (first row is the header), or `details` with
`summary` and `blocks`. A `photo` takes a public HTTPS `url`; a `collage`
takes HTTPS `urls`. A `buttons` block accepts up to eight buttons with a text
label and either `url` or `callback_data`. Standard keyboards are also supported.

To reuse an existing rich layout, put an output reference such as
`"{{steps.list.rich}}"` in the blocks field. The rich list renderers in the
built-in templates expose this output alongside their text, keyboard and count.

For a temporary private chat preview, enter a **Draft ID** such as
`{{event.updateId}}` and use a `thinking` block while waiting for real work.
Repeated drafts with the same ID update the preview. A later Send action without
a Draft ID posts the finished reply. Drafts expire and are not saved to the inbox.

### Interactive lists

In **Render list**, turn on **Place buttons next to each item** to show each
item's controls next to its text in a rich message. Bind the renderer's
`"{{steps.list.rich}}"` to **Rich blocks** and `{{steps.list.keyboard}}` to
**Keyboard output reference** for the footer. Use **Edit message text** instead
of sending another message when a callback should update the current view.

Buttons in the per-item and footer arrays can include `style` with the value
`primary`, `success` or `danger`, and a `when` condition with the same
`left`, `operator` and `right` fields as an action condition. This example
shows a Next button only when the page result has a next page.

```json
[[
  {
    "text": "Next",
    "callback_data": "page:{{steps.page.rows.0.next}}",
    "when": {"left": "{{steps.page.rows.0.hasNext}}", "operator": "equals", "right": 1}
  }
]]
```

### Telegram widgets

Under **Telegram widget** in **Send text**, supply self-contained HTML and
optional JSON chat data. The HTML is fixed when sent. Widget chat data is
limited to 1024 UTF-8 bytes and is visible only in the chat where the widget
was sent. Set a caption so older clients can show how to reach the text view.
To reuse a list as widget data, set **Data for each item** in **Render list**
and bind its `items` output into the widget's JSON.

Enable **Allow widget requests** on the message and **Accept widget requests**
on a matching callback event. Call `TelegramWidget.request(data)` in a widget
button's click handler. The same **Answer button click** action sends the
widget's answer. Use **Edit message text** with new widget chat data to update
the widget. The widget can redraw on `chatDataChanged`.

The builder accepts widget requests from original widgets in private chats.
Use the Telegram widget profile to check supported HTML, CSS, and JavaScript.
[Telegram Widgets](https://core.telegram.org/bots/widgets)

## Variables, conditions and SQL

Declare text, number or boolean variables under **Variables and API credentials**.
Choose per-user scope or whole-bot scope, then update them with **Set variable**
or **Increment variable**. Defaults do not allocate a database row per user.
Resetting a value to its default removes the stored override. Deleting a variable
removes its saved values for this bot's users.

An action can have a condition or the chain can use **Check condition**. Available
comparisons are equality, inequality, contains, greater and less. A failed check
stops the rest of that chain. An individual action with a false condition is
skipped. **Wait** supports up to 60 seconds and is cancelled when the bot stops.

**Run SQL** executes one statement against this bot's SQLite file. Values are
bound separately as a JSON array, never interpolated into SQL source:

The app packages a pinned SQLite core using the official source-build hook.
Every connection must pass functional authorizer, progress-handler and resource
limit checks before SQL is accepted. A build without these checks fails closed;
the app never substitutes a system SQLite library. See
[native source provenance and packaging](../native/sqlite/README.md).

```sql
SELECT score FROM scores WHERE user_id = ?
```

```json
["{{event.userId}}"]
```

Use separate actions to create a table, write records and query them. Each SQL
action owns its transaction; a failed or oversized statement is rolled back.
Outputs include `rows`, `columns`, `affectedRows` and the connection's latest
`lastInsertRowId`. Alias duplicate result column names before binding them.

The connection's SQLite authorizer denies attaching or detaching files, PRAGMA,
extensions, virtual and temporary tables, transaction control and access to the
reserved `_bottogram_values` table. An allowlist covers common SQL functions;
unsupported functions and some advanced SQLite operations are rejected. A
progress handler and SQLite resource limits bound execution. This is a restricted
SQL interface, not a general operating-system sandbox.

Schema changes are checked through SQLite metadata before commit. Foreign keys
to reserved tables and renames into the reserved namespace are rolled back;
ordinary user-table foreign keys and cascades remain supported. Worker requests
queue before their reply timeout starts. An actual worker communication timeout
reports an unknown outcome, so inspect data before retrying a write.

Open **Bot database** in a bot's settings to inspect that bot's tables, generated
columns, indexes and paginated rows. The browser uses fixed read-only operations,
bound filters and bounded results. Internal variable rows are visible there but
remain inaccessible to creator SQL actions.

## Storage and recovery

App configuration, bot/event/action definitions, variable declarations and
credential names remain in Hive. Creator-controlled variable values and custom
tables live in `bot_data/<bot-token-hash>.sqlite`, next to app configuration.
Existing app-managed inbox and plugin storage retain their existing formats.
SQL runs on a worker isolate; at most four database connections remain open.
Deleting a bot removes its builder data and credential references.

The additive Hive adapters retain old type IDs, field IDs and enum indexes.
Missing action/event settings default to an empty map. Before the first upgraded
write to existing bot storage, the app saves and verifies a snapshot under
`builder_upgrade_backup`. Keep that snapshot with the matching old app if a
downgrade is necessary: old app versions cannot execute new enum values.

Existing `.hive` configuration sharing does not include SQLite contents, variable
declarations or secure credentials. It is not a complete backup for an advanced
bot. API responses and named action outputs are temporary for each execution.

## Failures and limits

Open **Execution console** in the bot settings to see matched events, step names,
successes, skipped conditions, elapsed times and failures. The console retains
the latest 200 entries per bot, with a global 1,000-entry cap, for this session.

Failures stop the chain by default. Explicit **Continue** exposes
`steps.<name>.ok = false` and `steps.<name>.error` for a later conditional action.
Completed earlier actions are not undone: variable writes, API side effects and
Telegram sends are not one transaction. External writes are never automatically
retried, since an interrupted response does not establish whether a write ran.

Current device budgets:

- 64 actions per event; 32 queued executions per bot.
- HTTP: 22-second timeout, 64 KiB JSON request body, 1 MiB JSON response.
- Temporary step outputs: 2 MiB total per execution.
- SQL: one statement, 64 KiB SQL, 256 scalar parameters, 2-second execution budget,
  500 returned rows, 1 MiB returned data. Database growth is bounded by 262,144
  pages, approximately 1 GiB at the default 4 KiB page size.
- Variables: 64 declarations per bot, 4 KiB per text value, 16 KiB changed values
  per user/bot scope record. Limits report errors instead of evicting state.
- Polling intervals: 30–86,400 seconds, with no overlapping executions of a timer
  and no replay of missed ticks after Stop, process death or device downtime.

Network connectivity and the existing Android background-execution constraints
still apply. Automated tests use temporary storage and local HTTP/Bot API servers.
Native builds do not establish real-device delivery or OEM background behavior.
