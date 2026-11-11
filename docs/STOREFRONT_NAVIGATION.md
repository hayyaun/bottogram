# Storefront navigation

This document describes the original Inshopa 0.6.0 navigation.
The bundled [0.8.4 package](../examples/plugins/inshopa.storefront.0.8.4.bottogram-plugin.json)
adds HTML storefront widgets and product broadcasts. Its widget shows six
products per page with 64 px thumbnails.
There is no Inshopa source, API, page, authentication, database or configuration
change.

## Plugin-owned chat behavior

- `/start` and `/shop`: a short reply with **Open shop** and **My orders**.
- `/orders`: a short reply with **My orders**, opening the existing `/orders` page.
- `/help`: brief website sign-in guidance and the same navigation buttons.
- `/products`, including its previous page argument, is a shop-launcher alias.
  Version 0.6.0 does not fetch or duplicate products in chat.
- The plugin limits these command triggers to private chats. Other chat types
  receive no navigation reply from these automations.
- The plugin declares a default **Open shop** menu button, synchronized at Start.

All command names, aliases, messages, button labels, routes and menu labels live
in JSON. The host contains no registry that recognizes Inshopa IDs, versions or
source digests and substitutes behavior. Packages execute the declarations they
contain. The unreleased format is allowed to break; there is no decoder that
recreates the removed implicit HTTP-header convention for old installed data.

## Generic host capabilities

`telegram.command.v2` declares a bounded list of command aliases, allowed chat
types and argument handling. It uses the automation runner and bounded event
queue, rather than a plugin-specific command handler. Version 1 command triggers
continue to work.

`telegram.reply.v2` declares text and an inline keyboard. A Mini App button uses
a typed URL reference, for example:

```json
{
  "text": "My orders",
  "webApp": {
    "originField": "storefrontUrl",
    "path": "/orders"
  }
}
```

The referenced field must be declared as required non-secret text. The host
resolves a valid HTTPS origin and a literal same-origin path. Userinfo,
credentials, queries, fragments, alternate authorities and template expressions
cannot enter the launch URL. Invalid field values are not echoed in errors or
logs. Existing HTTP development registrations are not converted to HTTPS.
If the scheme is omitted, a hostname such as `shop.example.com` resolves as
`https://shop.example.com`. The same rule applies to URL-derived header bindings.
Resolution does not rewrite saved setup values or reset automation progress.

The optional top-level `telegram.menuButton` uses the same validated URL form.
The supported Televerse `InlineKeyboardButton.webApp`, `WebAppInfo` and
`MenuButton.webApp` APIs supply the launchers. Menu configuration failure does
not stop independent command replies or seller alerts. Installer/update review
shows the declared commands, web destinations and API requests. Unknown types,
unknown keys, duplicate aliases and unsafe field references are rejected before
execution.

## Versions, reviewed updates and saved state

Fresh installations seed Inshopa 0.6.0. The current production and local 0.6.0
definitions declare request headers and error messages explicitly. Shipped older
example versions have also been rewritten to the current request syntax; their
old source bytes are not a compatibility promise. The approved one-time offline
Hive transition rewrote three installed definitions and added local 0.6.0 after
exact data-file backups outside the repository. Installing a package is distinct
from applying it to a bot.

For a compatible update, the bot instance ID, token binding, admin destination,
field values, secure key references and saved preferences remain unchanged.
The `paid-orders` execution behavior remains the same: its setting gate, action
IDs, API endpoints, intervals, pagination, filter and notification text are
retained. Header construction is now explicit JSON, and error presentation is
plugin metadata. Error wording and presentation mappings are excluded from
execution compatibility comparisons; request behavior is not ignored.

The existing progress key includes the whole package source digest. Reusing an
automation ID alone therefore cannot preserve its state. The updater compares
the old/new automation execution configuration and retained execution context,
excluding error catalogs and component `errorMap` presentation metadata, then
stages its state and all delivery-receipt keys under the new package namespace
before committing the setup pin. A failed copy leaves the original bot pin and
progress intact. The source namespace and old package are retained; a package's
own declaration cannot authorize state reuse across different shops or contexts.
The header/error source contract requires no schema migration or startup backfill.
The approved one-time offline data transition changed only the local 0.5.0 setup
digest, retained its other settings and defaults
(including enabled seller notifications), and copied two progress records while
retaining their originals. There were no delivery receipts to copy. Automated
checks and reopening the normal Linux debug preview verified the transitioned
data: all package pins resolve and the other public setup fields, including the
exact shop URL, are unchanged. No bot was restarted.

The retained state includes the baseline, pending event/action position, page
continuation and durable delivery receipts. An update does not establish a fresh
paid-order baseline or re-enable a disabled notification preference. The
current-state polling and ambiguous-delivery limits in
[Plugin runtime](PLUGIN_RUNTIME.md) continue to apply.

A stopped bot applies a reviewed update immediately. An active bot can queue
the reviewed selection for its next normal Start, without being stopped. The
queue belongs to the current app session: restarting Bottogram discards the
selection and requires another review. The update is revalidated when applied.
An invalid or HTTP target Mini App origin rejects that update; the older pinned
bot and its alerts remain intact. No shop/domain or protocol rewrite is inferred.

The local package keeps `bottogram-plugin-inshopa-local` and the existing local
API destinations. It is not a production-backend replacement. Local 0.6.0 is
installed and available; the current local bot remains on 0.5.0 because no
reachable HTTPS shop address has been provided. A local HTTP website cannot be
advertised as a usable Telegram Mini App destination.

Flutter hot reload keeps existing sessions and their already-registered handlers
alive. It does not retroactively install new startup handlers or select plugin
updates. A hot restart resets in-memory sessions and stops bots, so it is not
used solely to activate navigation while active bots must remain running.

## Website and authentication boundary

The plugin's two public launch URLs are the existing shop origin and the same
origin with `/orders`. Bottogram does not request those page URLs or add API
keys, bot tokens, buyer identifiers or session information. No new order-history
page, catalog, cart or checkout implementation is introduced.

Telegram hosts the buyer's browser environment. Inshopa handles its existing
login, cookies, session validity, cart and checkout. Telegram identity does not
authenticate an Inshopa account. There is no OTP/password collection, account
linking, page proxy, wrapper, session relay, Telegram Login, `sendData` or
`answerWebAppQuery` flow. Buyer order history is not fetched with the seller key.

Page launch needs no `storefront:buyer` permission. The existing seller scopes
remain: `storefront:read` identifies the shop for polling, and
`shop:orders:read` supplies order summaries when purchase alerts are enabled.
The existing inbox still stores ordinary private Telegram messages and user
identities, including text a buyer voluntarily sends. Existing pending seller
events and outgoing admin summaries may also be retained. The boundary concerns
website authentication/session data, rather than an absence of all buyer-related
data from Bottogram.

The Inshopa chat reported source/local findings of host-only HttpOnly cookies,
Secure cookies on HTTPS and the existing cross-host handoff/PKCE login flow.
Those findings are not fresh production or real Telegram-client verification.
Cookie persistence, sharing with an external browser and isolation after
switching Telegram accounts on a shared device are not assumed. Existing shop,
domain, authentication and purchase restrictions remain effective.

## Availability and remaining client verification

Already-sent Mini App buttons and a configured menu launch the hosted website
without a fresh Bottogram reply. They still need Telegram, the website and a
working connection. New command replies and seller alerts require a running bot.
Stopping or deleting a bot does not revoke published website buttons or the
configured Telegram menu. Changing a storefront value does not recall prior
messages, and a failed menu update may leave the previous menu in place.

Local automated checks use fixtures rather than real bot tokens, buyer sessions
or payment-provider credentials. Current verification results are recorded in
[Plugin runtime](PLUGIN_RUNTIME.md).

Real Telegram checks remain outstanding: fresh/existing login, cross-host
handoff and return to `/orders`, custom shop domains, reopening, logout/account
switching, payment success/cancel/failure and return, and website operation while
Bottogram is stopped. A failed flow must be reported before proposing Inshopa
changes or a workaround; restrictions are not bypassed to make a test pass.

Telegram requires Stars for digital goods/services sold inside Mini Apps.
Loading an existing website does not remove that requirement. The intended
shop product categories remain an open constraint; the existing external
checkout is not claimed to work universally for digital shops, and no category
is silently excluded or routed through an invented fallback.

Official references:

- [Mini App launchers](https://core.telegram.org/bots/webapps)
- [InlineKeyboardButton](https://core.telegram.org/bots/api#inlinekeyboardbutton)
- [Bot menu](https://core.telegram.org/bots/api#setchatmenubutton)
- [Digital goods payment requirements](https://core.telegram.org/bots/payments-stars#q-i-run-my-own-website-to-process-sales-does-this-mean-i-dont-have-to-use-telegram-stars)
