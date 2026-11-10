# Remaining work

Updated 2026-11-10 (Asia/Tehran). Current status is based on implemented code and
recorded verification in [PLUGIN_RUNTIME.md](PLUGIN_RUNTIME.md). Older ideas and
implementation proposals preserve history; they are not all outstanding tasks.
Publishing a release is explicitly deferred until the plugin is useful to shops.

## Finish verification of the implemented features

1. **Actual paid-order alert.** The owner confirmed the Telegram connection message
   and `/products` response. A real new paid-order alert is still unverified because
   local Gogoli Shop checkout is not enabled. 🟣 Inshopa must make that local shop
   ready for mock checkout; then complete a purchase while Bottogram runs and
   confirm the admin alert. This project must not activate the shop or alter its DB.
2. **Live recovery scenarios.** Check no historical alerts on initial setup, one
   alert across multiple polling cycles, Stop/Start, an offline interval, delayed
   payment, and changed key/storefront settings against the real local API. Unit
   fixtures already cover baseline, late payment, durable receipts and failures.
3. **Physical Android operation.** 🟣 Test a real device with the screen off,
   backgrounded UI, Doze, notification Stop, permissions revoked, force-stop and
   reopening. Include Android 7.0/API 24 minimum support and at least one current OEM.
   Emulator background continuity passed; it does not establish OEM behavior.
4. **Production connection.** Inshopa owns rollout and valid production-key issuance.
   🟣 Once ready, configure a production plugin bot and verify catalog and paid-order
   access with the intended scopes and registered storefront. Local success does
   not establish that production is ready.
5. **Build and desktop checks.** Run the new GitHub workflow after pushing it and
   resolve actual hosted build failures. 🟣 Test the Windows bundle on a clean PC
   and AppImage on a clean Linux desktop, including plugin install, secure storage,
   file opening and Telegram connectivity. See [build artifacts](BUILD_ARTIFACTS.md).

## Proposed next work to make the Inshopa plugin useful

These are priorities to discuss, not features implemented or newly approved by
this document. Keep the host generic: package declarations compose registered
trigger/action capabilities instead of adding Inshopa conditions to the runtime.

1. **Verify storefront navigation.** The supported shipped packages now open the
   existing HTTPS shop and `/orders` as Telegram Mini Apps, with brief help and a
   `/products` launcher alias. Verify fresh/existing login, cross-host handoff,
   buyer isolation/account switching, custom domains and payment return in real
   Telegram clients. See [Storefront navigation](STOREFRONT_NAVIGATION.md).
   Chat catalog/cart/checkout duplication and buyer API features are deferred.
2. **Verify checkout suitability.** Reuse the existing website and its restrictions;
   do not assume external-browser session sharing. Digital goods sold inside
   Telegram require Stars, so unchanged external checkout is not universally
   suitable. No Inshopa changes or auth/session workaround are included.
3. **Useful seller alerts.** Show an understandable order reference, amount/currency,
   relevant item summary and an order/dashboard link where the API provides them.
   Keep alerts restricted to the configured admin; do not add buyer messages or
   expose buyer personal information through the public catalog command.
4. **Connection checks during setup/editing.** Validate the key, storefront, required
   scopes and Telegram admin reachability, with a labelled test-message action and
   clear guidance when the admin has not started the bot.
5. **Operational status.** Show last successful check, last alert, current connection
   failure/retry, and what needs user attention. “Active” alone is insufficient.
6. **Explicit plugin upgrades.** Offer a reviewed way for an existing bot to move
   between installed plugin versions, validating retained fields/preferences and
   defining progress compatibility. Current immutable versions and pinned bots
   work; automatic upgrades are not implemented.
7. **Protected backup/import for plugin bots.** Currently unavailable; existing
   configuration sharing supports manual bots only. Define secret handling and
   restoration before implementing it. Any new database migration needs separate
   approval under the project's migration policy.

## Later, before the first public release

- Independent backup of the Android signing identity, Windows signing/installer choice, upgrade testing,
  version/build-number policy and final app metadata.
- Privacy/documentation review, practical shop onboarding, support instructions,
  and the applicable distribution review for Android foreground execution.
- Document current-state polling limits honestly. The existing order-summary API
  is not a durable payment event log; strict recovery guarantees would require an
  explicitly agreed Inshopa API improvement, not invented client-side cursors.

The wider ideas such as human takeover, a simulator, complete bot templates and
conversation steps remain optional product ideas, rather than blockers for this
minimal Inshopa integration. Plugin installation, execution, parameter editing,
the users inbox, battery guidance and Android service are already implemented.
