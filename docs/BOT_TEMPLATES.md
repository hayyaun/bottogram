# General bot templates

Open **Store**, choose a template and connect a new Telegram bot. Each template
creates ordinary editable events and actions, without installing a plugin.
Existing bots and their data are never replaced. A token already in the bot list,
or with surviving builder data, cannot overwrite that configuration.

The catalog order is:

1. Quiz with scores: topics, three choices per question, answer explanations and
   per-user, per-topic personal bests. Repeated answer clicks cannot add points.
2. Crypto prices: on-demand CoinGecko prices for the five leading coins by market
   capitalization, quote currency selection, cooldown and friendly retry output.
3. Personal task list with an editable board, Open and Completed views, quick
   entry, rename and delete confirmation. Tasks are private to each user.
4. Searchable library: categories, literal title/description search, resource and
   file links, details and per-user favorites.
5. Feedback survey: rating/text questions, Back/Cancel, paginated review,
   duplicate-safe submission and admin totals with recent response previews.
6. Requests and replies: subjects and messages, tracking numbers, private request
   history, admin inbox/replies and close/reopen controls. No commerce dependency.
7. Event registration: seat counts, duplicate-safe registration, cancellation and
   admin counts. One guarded SQL statement performs the capacity check and insert.

New bots from the templates use Telegram rich messages for lists, tables and
expandable details. Repeated list layouts and button rows are saved to the
builder libraries so they can be edited once and reused in other events or bots.

The quiz presents questions in a widget with answer buttons and a progress
indicator. Use **/quiz_text** for the rich text view or **/quiz** to return to
widgets. The crypto template shows a progress preview while fetching prices
and then a market widget with a refresh button. **/prices_text** shows the rich
table with coin images when the response supplies supported image URLs.
Existing bots keep their saved actions.

## Using the task board

Open the board with **/tasks**. Tap **Add task** and send a title, or use
**/add Buy groceries** to add it directly. The task controls sit beside each
title. **Complete** moves it to Completed, where **Reopen** brings it back.
Open **Details** to rename a task or confirm its deletion.

The board uses a Telegram widget in private chats. It updates in the same
message, shows completion progress and only offers navigation to available pages.
Send task titles in chat when the board asks for them.

Send **/tasks_text** if your Telegram client cannot display the widget.
Bottogram remembers that preference. Use **/tasks_widget** to switch back.
If a board message was deleted, send **/tasks** to reopen it with your
saved tasks. The widget is included when creating a new task-list bot.

## Setup and editing

The setup form includes sample content. Edit or replace quiz questions and answer
explanations, library resources, survey questions and event details before creating
the bot. Samples are copied, so editing one draft does not change another draft.
There are up to 20 sample rows per template. Topic/category names are bounded by
UTF-8 bytes because Telegram button callback data is limited to 64 bytes.

After creation, review the normal event/action list and start the bot from **Bots**.
Admin templates use the Telegram user IDs in the bot's **Admins** setting.
Each admin can use the template's admin actions. The requests template sends
new request notices to every listed admin. The templates default to
private chats to keep personal records out of group replies. These are editable
action conditions, not a restriction on other bots built in Bottogram.

Initialization actions create this new bot's tables and bind sample values as SQL
parameters on first use. They set **bot.initialized** only after successful setup.
The SQL is idempotent for retries; it never drops tables or overwrites existing
rows. Later runs skip initialization. No existing bot database is migrated.
App definitions remain in Hive; state and template tables stay in that bot's
separate SQLite file.

Sample controls apply when creating a bot. For later changes to stored content,
use **Run SQL** with bound parameters on this bot's tables. For example:

    UPDATE quiz_questions SET question=?,explanation=? WHERE id=?

Editing an initialization seed alone does not update rows after initialization.
The database browser remains read-only; there is no hidden template-specific
database editor or automatic data reset.

## CoinGecko behavior

The template performs a request only after **/prices**, **/prices_text** or a Refresh click.
**/start**, app launch and polling timers do not request prices. A default
15-second per-bot cooldown limits repeated requests; it is adjustable during
setup. There are no automatic retries. Unavailable services, rate limits,
malformed responses and missing required fields produce a plain-language message
and a retry button. Detailed failures stay in the execution console.

CoinGecko attribution is included in replies. Keyless access and the chosen
endpoint were checked on 2026-11-10; one live request returned HTTP 200 with five
rows and the expected fields. This is not an availability guarantee. CoinGecko's
[keyless documentation](https://docs.coingecko.com/docs/keyless-public-api)
describes shared, dynamic IP limits and discourages production/high-frequency
or scheduled workloads. Keyed credentials are not bundled into the template.

## Reusable builder capabilities

Text/callback/inline events can use **Exact value** or **Starts with** matching.
Text events also support **Any text except commands**. Matching is literal;
prefixes are not regular expressions. **event.input** contains the part after the
prefix, or the complete text for an any-text event. Existing events without a
matching setting retain their legacy behavior, including existing inline patterns.
Place specific events before broad text events.

**Render list** accepts a SQL/API array reference and formats up to 50 items.
Its row template can use **item.field** and the one-based **index**. It supports
per-item inline buttons, footer button rows, headings, separators and empty-state
copy. Results expose **text**, **keyboard**, **count** and **ok**.

Use {{steps.list.text}} as a message's plain text and {{steps.list.keyboard}} in
**Keyboard output reference**. The reference takes priority over a static
keyboard. Typed objects pass between actions without stringifying JSON. Callback
byte limits, array/row limits and the 4096-character text budget are validated
before sending. Larger data should use paginated SQL, as the task list, library,
survey review and request history demonstrate.

## Verification

Template tests execute real generated action chains through the builder engine
and guarded temporary SQLite files. They cover scoring/repeated clicks, per-user
records, paging, literal searches, submission idempotency, admin permissions,
registration capacity, separate bot files and crypto failures/cooldowns.
Additional tests exercise actual Televerse event dispatch and generated keyboard
serialization against a local Bot API fixture. Widget tests cover phone/desktop
layout, dark mode with larger text, sample editing and preservation after errors.
These checks do not send messages to real Telegram accounts.

On 2026-11-10, the full 151-test unit/widget suite passed and analysis reported
no issues. The packaged template smoke test passed on native Linux and an Android
API 35 x86_64 emulator, executing all seven templates with real temporary SQLite
state. Both targets reported SQLite 3.54.1 with authorization/progress hooks
active. The Linux release and rebuilt AppImage passed their native-library probes.
Windows execution is configured in CI but was not run locally; physical Android
devices and other Android ABIs remain untested.

Logs are in build/verification/templates-*. The native test entry point is
integration_test/templates_test.dart. It uses fixture prices, not live polling.
