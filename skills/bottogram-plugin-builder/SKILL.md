---
name: bottogram-plugin-builder
description: Create, customize, or validate Bottogram .bottogram-plugin.json packages for a user's integration. Use for declarative plugins, not manual bot templates or changes to the Bottogram runtime.
---

# Bottogram plugin builder

Deliver an importable UTF-8 `.bottogram-plugin.json` file that expresses the
user's integration using Bottogram's registered capabilities. Plugin-specific
commands, routes, filters, labels and error messages belong in that file. The
host provides generic capabilities; a package does not contain executable code.

Read [the bundled contract](references/contract.md) before authoring. It is
self-contained because installing this skill does not install the Bottogram
source repository. The [public authoring guide](https://github.com/hayyaun/bottogram/blob/main/docs/PLUGIN_AUTHORING.md)
provides the longer tutorial. If the user's installed host differs, check its
current contract rather than inventing compatibility syntax.

## Shape the integration

Establish the commands, intended chat types, website destinations, API operations
and delivery audience the user actually needs. For API work, obtain documented
endpoints and representative response objects, including pagination and stable
item IDs. Ask for missing contract details rather than guessing vendor routes,
authentication scopes or response paths.

Choose the smallest supported composition:

- Existing website or Mini App: copy and adapt
  [the portal starter](assets/portal.bottogram-plugin.json). The user supplies
  their HTTPS origin during bot creation. This does not build or host a website.
- Command-driven API read: command trigger, `http.get-json.v1`, then a reply.
- Background updates to the configured admin: a polling trigger, then
  `telegram.notify-admin.v1`. Choose baseline versus replay deliberately.

Current plugin HTTP requests are GET-only and use literal URLs. A setup field
cannot replace an API URL. Only the list poll's documented lookup can bind
complete path segments. The separate manual bot builder supports other features;
its action names and expression language are not plugin capabilities.

When the requested behavior is unsupported, identify the missing reusable host
capability and explain the gap. Do not emit fictitious types, scripts, webhooks,
POST requests or expression syntax, or add provider-specific code to the host.

## Author the package

Use `manifestVersion: 2`, `hostApiMajor: 2` and `executionStatus: "live"`.
Choose a lowercase, namespaced ID and a numeric `major.minor.patch` version.
Do not add `engine` to a live package.

Put connection inputs in `setupFields`; put credentials in required `secret`
fields and refer to them through `authentication.secretField`. The Telegram bot
token and admin ID are host fields, not plugin-defined fields. Real credentials
do not belong in JSON, examples, commits or error text. Normal setup enters them
in Bottogram. Use an authorized secure mechanism only when an actual live check
requires a credential.

Put non-secret preferences in `settings`. The runtime currently consumes boolean
preferences through `enabledBySetting`; other preference types do not create
runtime bindings. Message templates support only `event` and `item` dot paths.
There is no `fields`, `settings`, `secrets`, array-index or expression namespace.

Use `errorMessages` resources and component-local `errorMap` entries for useful
provider wording and recovery guidance. They are presentation, not control over
retries, checkpoints or delivery acknowledgement. Follow the contract's bounds
and privacy implications when composing commands and notifications.

## Validate and deliver

Parse the generated file with a JSON parser and check its composition against
the bundled contract. JSON syntax alone does not prove host compatibility.
When a Bottogram source checkout with its Flutter dependencies installed is
available, validate with the real host parser from that checkout:

```sh
dart run tool/validate_plugin.dart /path/to/example.bottogram-plugin.json
```

This skill does not require a source checkout or install that validator. Without
one, check the bundled contract and use Bottogram's import review as the
authoritative schema check. Report which checks actually ran and which API or
Telegram behavior is still unverified.

Deliver the file and briefly explain:

- The declared commands, destinations and recipient of background notifications.
- Which setup values and API permissions the user must supply, without including
  real secret values in the package.
- How to open **Plugins → Install from file**, review the capabilities, create a
  bot with the installed version and explicitly start it when ready.
- Any unsupported behavior or real-client checks still outstanding.

An installed package is pinned by ID, version and content digest. For edits,
produce a new version instead of replacing an installed version's bytes. Import
alone does not update an existing bot. Use Bottogram's reviewed update flow when
the task includes updating a bot; do not edit its saved database records.

Stay within the user's authorization. Creating a package alone does not
authorize importing it into an existing setup, changing credentials, starting
bots or sending test messages. Continue those actions when the task already
authorizes them; otherwise hand off the file and installation instructions.
