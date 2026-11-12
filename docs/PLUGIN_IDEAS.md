# Bottogram plugin ideas

Initial integration shortlist for discussion.

## WooCommerce

A seller bot could send paid-order alerts privately to all bot admins, show
today's sales and low-stock products, and link to the relevant order or product
in the WooCommerce dashboard.

Each installation has its own HTTPS API address. A reusable host capability
could let plugins declare a configurable API base URL and use stored
credentials for HTTP Basic authentication. WooCommerce returns order lists as
top-level JSON arrays, which the list poller would need to support.

[WooCommerce REST API](https://woocommerce.github.io/woocommerce-rest-api-docs/)

## GitHub

Start with a `/release` command for Bottogram's own repository. The bot could
show the latest version, release notes, and a link to downloads. The latest
release endpoint works without a token for public repositories. Later versions
could let users choose a repository, announce releases in a Telegram channel,
and send a digest of pull requests awaiting review.

[GitHub Releases API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
and [Pull Requests API](https://docs.github.com/en/rest/pulls/pulls#list-pull-requests)

## n8n

Let a bot command invoke a workflow the owner already configured. For example,
`/stock ABC123` could look up inventory and return a short Telegram message.
The first version could call an authenticated GET webhook and render its JSON
response. Workflows that change records or trigger jobs would use authenticated
POST requests when the host supports them.

[n8n Webhook documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)

## Basalam

A bot for Iranian marketplace sellers could show new orders and remind sellers
about orders that still need shipping. Basalam documents OAuth 2.0 for seller
access. Confirm which scopes and endpoints expose order and shipping data before
designing the bot's connection flow.

[Basalam Open API documentation](https://github.com/basalam/openapi-docs)
