import 'card_widgets.dart';
import 'program.dart';

BotTemplateDraft buildCrypto(
  Map<String, String> settings,
  List<Map<String, dynamic>> rows,
  String admin,
) {
  final currency = settings['currency']!,
      cooldown = int.parse(settings['cooldown']!);
  final buttons = keyboard([
    [button('Refresh prices', 'prices:refresh')],
  ]);
  final p = TemplateProgram([
    sql(
      'setup_prices',
      'CREATE TABLE IF NOT EXISTS price_requests(id INTEGER PRIMARY KEY,last_at INTEGER NOT NULL)',
    ),
  ]);
  p.command('start', [
    say(
      'welcome',
      'Request the current top five cryptocurrency prices in ${currency.toUpperCase()}.\nData provided by CoinGecko: https://www.coingecko.com\nUse /prices or Refresh prices.',
      buttons: buttons,
    ),
  ]);
  Acts prices({bool widget = true}) => [
    sql(
      'gate',
      'INSERT INTO price_requests(id,last_at) VALUES(1,unixepoch(?)) ON CONFLICT(id) DO UPDATE SET last_at=excluded.last_at WHERE price_requests.last_at<=excluded.last_at-?',
      ['{{event.timestamp}}', cooldown],
    ),
    say(
      'cooldown',
      'Please wait $cooldown seconds between refreshes. The free data service has a shared request limit.',
      buttons: buttons,
      only: when('{{steps.gate.affectedRows}}', 0),
    ),
    check('allowed', '{{steps.gate.affectedRows}}', 0, 'greater'),
    say(
      'loading',
      'Fetching current prices…',
      draftId: '{{event.updateId}}',
      rich: [
        heading('Market snapshot'),
        {'type': 'thinking', 'text': 'Fetching current prices from CoinGecko…'},
      ],
    )..config['onError'] = 'continue',
    templateAction(VirtActType.http, '', 'prices', {
      'url':
          'https://api.coingecko.com/api/v3/coins/markets?vs_currency=$currency&order=market_cap_desc&per_page=5&page=1&sparkline=false&precision=2',
      'onError': 'continue',
    }),
    render(
      'quotes',
      '{{steps.prices.body}}',
      '{{item.market_cap_rank}}. {{item.name}} ({{item.symbol}})\n{{item.current_price}} ${currency.toUpperCase()}',
      header:
          'Current prices · ${currency.toUpperCase()}\nTop five by market capitalization\n\n',
      itemData: [
        '{{item.market_cap_rank}}',
        '{{item.name}}',
        '{{item.symbol}}',
        '{{item.current_price}}',
      ],
      columns: {
        'Rank': '{{item.market_cap_rank}}',
        'Asset': '{{item.name}} ({{item.symbol}})',
        currency.toUpperCase(): '{{item.current_price}}',
      },
      photoField: 'image',
      photoHosts: const [
        'coin-images.coingecko.com',
        'assets.coingecko.com',
        'images.coingecko.com',
      ],
      buttonsInMessage: true,
      empty: 'No price data is available right now. Please try again later.',
      footer:
          '\n\nSource: CoinGecko · https://www.coingecko.com\nRequested: {{event.timestamp}}',
      footerButtons: [
        [button('Refresh prices', 'prices:refresh')],
      ],
    )..config['onError'] = 'continue',
    say(
      'unavailable',
      'Prices are unavailable right now.\nThe service may be busy, rate-limited or unreachable. Please wait a little and try again.',
      buttons: buttons,
      only: when('{{steps.quotes.ok}}', false),
    ),
    if (widget)
      ...sendListWidget(
        'quotes',
        marketSnapshotWidget,
        {'items': '{{steps.quotes.items}}', 'currency': currency.toUpperCase()},
        caption: 'CoinGecko prices · Send /prices_text for the text view.',
        only: when('{{steps.quotes.ok}}', true),
        widgetWhen: when('{{steps.quotes.count}}', 0, 'greater'),
      )
    else
      sendList('quotes', only: when('{{steps.quotes.ok}}', true)),
  ];
  p.command('prices', prices());
  p.command('prices_text', prices(widget: false));
  p.click('prices:refresh', prices(), widgetQueries: true);
  return p.finish('Crypto Price Watch');
}
