# Run a plugin bot on a Linux server

Bottogram's command-line worker runs one live plugin bot per service using
Telegram long polling. It needs outbound access to Telegram and the plugin's
configured APIs. The sample Compose service publishes no ports.

Use the example from a Linux machine with Docker and Compose. It runs a small
plugin that replies to `/start`.

```sh
cd examples/headless
install -d -m 0700 secrets
```

Save the Telegram bot token from [BotFather](https://t.me/BotFather) in
`secrets/bot_token`. Keep the file private and readable by the container's user
(UID 1000 by default). The example directory ignores files under `secrets/`.
Compose mounts the token at `/run/secrets/bot_token`.

```sh
docker compose build
docker compose run --rm bottogram validate --config /config/bot.json
docker compose up -d
docker compose logs -f bottogram
```

Send `/start` to the bot in Telegram. Run only one polling process per token.
Stop a desktop copy of the same bot before starting the server copy.

## Use your own plugin

Place the `.bottogram-plugin.json` in `config/` and point `plugin` in
`config/bot.json` at it. Mount the config directory read only. File paths in
`bot.json` can be absolute in the container or relative to the config file.
The configuration accepts these fields.

- `plugin` and `tokenFile` are required.
- `adminIds` lists Telegram admin IDs as strings. Supply it for plugins that
  require admins.
- `fields` maps declared non-secret setup fields to strings. Omitted fields use
  the manifest defaults if present.
- `secretFiles` maps declared secret fields to file paths. Add a Compose secret
  for each file and mount it on the service just as the example mounts the token.
- `settings` maps declared plugin preferences to the JSON types in the plugin
  manifest.

For example, a plugin declaring a public `storefrontUrl` field and a secret
`apiKey` field can use this configuration.

```json
{
  "plugin": "storefront.bottogram-plugin.json",
  "tokenFile": "/run/secrets/bot_token",
  "adminIds": ["123456789"],
  "fields": {"storefrontUrl": "https://shop.example.com"},
  "secretFiles": {"apiKey": "/run/secrets/shop_api_key"}
}
```

To mount that API key, add `shop_api_key` to the service's `secrets` list and
declare it under the top-level `secrets` section with
`file: ./secrets/shop_api_key`.

After changing the config or secrets, run the validation command again and then
apply the changes with `docker compose up -d --force-recreate bottogram`. The service uses
the `progress` volume for automation checkpoints and Telegram command sync
state. Keep it across container updates. Checkpoints are tied to the bot and
exact plugin package, so replacing the plugin JSON starts a separate progress
namespace. Account for fresh progress when changing plugin versions. Stop with `docker compose stop` to let the worker close its Telegram
connection and flush progress.

## Run the executable directly

Build from the repository root with the same Flutter SDK the desktop app uses.

```sh
flutter pub get --enforce-lockfile
dart build cli --target bin/bottogram.dart --output build/headless
build/headless/bundle/bin/bottogram validate --config /path/to/bot.json
build/headless/bundle/bin/bottogram run --config /path/to/bot.json --data-dir /path/to/data
```

Keep the complete `bundle` directory when moving it to a compatible Linux host.
The worker supports live plugin packages. Desktop manual bots and inbox
management use the desktop app.
