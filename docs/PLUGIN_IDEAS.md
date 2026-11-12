# Bottogram plugin ideas

Candidate integrations and what each could bring to a Telegram bot.

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

## RSS and Atom

Turn public feeds from blogs, podcasts, and software projects into one daily
Telegram digest. The owner supplies feed URLs and chooses a destination. A
shared feed reader could handle parsing and track published entry IDs so
individual plugins do not have to implement the same logic.

[RSS specification](https://www.rssboard.org/rss-specification)
and [Atom specification](https://www.rfc-editor.org/rfc/rfc4287)

## Google Calendar

Give a club, class, or family a shared agenda. A `/week` command shows upcoming
events, while reminders include the local time, location, and meeting link.
Start with one calendar and decide who should receive its details during setup.

[Google Calendar events API](https://developers.google.com/workspace/calendar/api/v3/reference/events/list)

## Discourse

Show unanswered topics from selected forum categories in a moderator chat.
Volunteers can use `/unanswered` to find a question and open it on the forum.
The bot could also send a digest of older threads that still have no replies.

[Discourse topic filters](https://meta.discourse.org/t/unanswered-topics-topics-with-0-replies/358746)

## Todoist

Forward a Telegram message to the bot, pick a project, and choose Today,
Tomorrow, or No date. The bot creates the task and returns a link to it. This
requires an authenticated write action with a JSON body.

[Todoist API](https://developer.todoist.com/api/v1/)

## Public transit (GTFS Realtime)

Save a stop and use `/home` to see the next three departures and any delays.
Start with one transit agency that publishes a live feed. The bot needs both
scheduled stop and trip data and the agency's real-time updates.

[GTFS Realtime specification](https://gtfs.org/documentation/realtime/reference/)

## TMDB and Seerr

Make a movie-night bot. Search for a title, show a card with its poster and
synopsis, and let the group nominate and vote on films. Pin the winning title
in the group. TMDB supplies the movie data. A later Seerr integration could
submit a request for the winner to a Jellyfin, Plex, or Emby library.

[TMDB movie search](https://developer.themoviedb.org/reference/search-movie)
and [Seerr documentation](https://docs.seerr.dev/)

## Lichess

Share the daily chess puzzle with a group and open it on Lichess. A
`/challenge 5+3` command could create a link that pairs the first two people
to join. The daily puzzle uses a public GET endpoint and the open challenge
uses a public POST endpoint.

[Lichess puzzle API](https://lichess.org/api#tag/Puzzles/operation/apiPuzzleDaily)
and [open challenge API](https://lichess.org/api#tag/Challenges/operation/challengeOpen)

## Twitch

A watch club could use `/live` to see which of its selected streamers are on.
Show the game, stream title, and a Watch button. Share upcoming streams and
let members vote on clips to catch up on. The Twitch API requires an access
token for these reads.

[Twitch API](https://dev.twitch.tv/docs/api/reference/)
and [authentication](https://dev.twitch.tv/docs/authentication/)

## ListenBrainz

Run a weekly music swap. Members opt in with their usernames, and the bot
picks one recent track from each participant's listens. The group votes for
its favorite discovery of the week. The first version can link to tracks and
keep the group's vote in Telegram.

[ListenBrainz recent listens](https://listenbrainz.readthedocs.io/en/latest/users/api/core.html)
and [listening stats](https://listenbrainz.readthedocs.io/en/latest/users/api/statistics.html)

## iNaturalist

A hiking group chooses a park or region and uses `/nearby` to browse recent
wildlife sightings. Each result links to its original observation. A weekly
challenge could choose a local species for members to try to spot.

[iNaturalist API](https://api.inaturalist.org/v1/docs/)
and [geographic filters](https://www.inaturalist.org/pages/search%2Burls)

## ComfyUI

Turn a group chat into an image workshop. A prompt such as "a sci-fi poster
for our hiking club" runs one workflow preset selected by the bot owner.
The bot acknowledges the job, follows it through the queue, and returns the
finished image. Reusable host capabilities include submitting a job, tracking
it by ID, and delivering the resulting file. Bottogram needs network access to
the configured ComfyUI instance.

[ComfyUI server routes](https://docs.comfy.org/development/comfyui-server/comms_routes)

## Immich

Send a family group a photo from the same month in a past year. A
`/throwback` command can pull another photo from the same album. The owner
chooses the source album and the destination. The bot can read album assets and
fetch a thumbnail using Immich's authenticated API.

[Immich album API implementation](https://github.com/immich-app/immich/blob/main/server/src/controllers/album.controller.ts)
and [asset media API implementation](https://github.com/immich-app/immich/blob/main/server/src/controllers/asset-media.controller.ts)

## Pterodactyl

Give a Minecraft group a game-night button. A designated operator taps Start
server, the bot checks the server's status, then posts its join address to
the group when the server reports it is running. The operator sets the address
during setup. Pterodactyl's client API exposes status and power actions for an
authorized account.

[Pterodactyl client API routes](https://github.com/pterodactyl/panel/blob/1.0-develop/routes/api-client.php)

## Wikipedia

Run a real-world history scavenger hunt. Pick a public starting point and use
Wikipedia's geosearch to find nearby landmarks with articles. The bot offers a
clue for each stop and reveals the article when the group solves it. One
curated route would be enough to test the format.

[MediaWiki Geosearch API](https://www.mediawiki.org/wiki/API:Geosearch)

## PokéAPI

Run a quick guessing game in a group. Show a silhouette based on a sprite,
offer a hint from the Pokémon's type, and give a point to the first correct
answer. PokéAPI supplies the data. The bot manages rounds and scoring, which
could also support other quiz packs.

[PokéAPI documentation](https://pokeapi.co/docs/v2#pokemon)
