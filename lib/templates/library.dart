import 'program.dart';

BotTemplateDraft buildLibrary(
  Map<String, String> settings,
  List<Map<String, dynamic>> rows,
  String admin,
) {
  final p = TemplateProgram(
    [
      sql(
        'setup_items',
        'CREATE TABLE IF NOT EXISTS library_items(id INTEGER PRIMARY KEY,category TEXT NOT NULL,title TEXT NOT NULL,description TEXT NOT NULL,url TEXT NOT NULL)',
      ),
      sql(
        'setup_favorites',
        'CREATE TABLE IF NOT EXISTS library_favorites(user_id TEXT NOT NULL,item_id INTEGER NOT NULL REFERENCES library_items(id) ON DELETE CASCADE,PRIMARY KEY(user_id,item_id))',
      ),
      seed(
        'library_items',
        ['id', 'category', 'title', 'description', 'url'],
        [
          for (final (i, row) in rows.indexed) {'id': i + 1, ...row},
        ],
      ),
    ],
    [
      variable('page', 0),
      variable('mode', 'category'),
      variable('category', ''),
      variable('search', ''),
      variable('searching', false),
    ],
  );
  final homeButtons = [
    [
      button('Categories', 'lib:home'),
      button('Search', 'lib:search'),
      button('Favorites', 'lib:favorites'),
    ],
  ];
  Acts home() => [
    setValue('searching', false),
    sql(
      'categories',
      'SELECT category,count(*) AS total FROM library_items GROUP BY category ORDER BY category LIMIT 20',
    ),
    render(
      'home',
      '{{steps.categories.rows}}',
      '{{item.category}} · {{item.total}} resources',
      header: '${settings['title']!}\n\n',
      buttons: [button('{{item.category}}', 'lib:category:{{item.category}}')],
      footerButtons: homeButtons,
    ),
    sendList('home'),
  ];
  const filter =
      "((?='category' AND i.category=?) OR (?='search' AND instr(lower(i.title||' '||i.description),lower(?))>0) OR (?='favorites' AND EXISTS(SELECT 1 FROM library_favorites f WHERE f.item_id=i.id AND f.user_id=?)))";
  List<dynamic> args() => [
    '{{user.mode}}',
    '{{user.category}}',
    '{{user.mode}}',
    '{{user.search}}',
    '{{user.mode}}',
    '{{event.userId}}',
  ];
  Acts listing() => [
    sql(
      'page',
      'SELECT page,page+1 AS number,pages FROM (SELECT max(0,min(?,max(0,CAST((count(*)-1)/5 AS INTEGER)))) AS page,max(1,CAST((count(*)+4)/5 AS INTEGER)) AS pages FROM library_items i WHERE $filter)',
      ['{{user.page}}', ...args()],
    ),
    setValue('page', '{{steps.page.rows.0.page}}'),
    sql(
      'items',
      'SELECT i.id,i.title,substr(i.description,1,180) AS description FROM library_items i WHERE $filter ORDER BY i.id LIMIT 5 OFFSET (?*5)',
      [...args(), '{{user.page}}'],
    ),
    render(
      'list',
      '{{steps.items.rows}}',
      '{{item.title}}\n{{item.description}}',
      header:
          'Library · {{user.mode}} · page {{steps.page.rows.0.number}} / {{steps.page.rows.0.pages}}\n\n',
      empty: 'No matching resources yet.',
      buttons: [button('View {{item.title}}', 'lib:open:{{item.id}}')],
      footerButtons: [
        [button('Previous', 'lib:prev'), button('Next', 'lib:next')],
        ...homeButtons,
      ],
    ),
    sendList('list'),
  ];
  Acts detail() => [
    sql(
      'item',
      'SELECT i.*,CASE WHEN EXISTS(SELECT 1 FROM library_favorites WHERE item_id=i.id AND user_id=?) THEN \'Remove favorite\' ELSE \'Save favorite\' END AS favorite FROM library_items i WHERE id=?',
      ['{{event.userId}}', '{{event.input}}'],
    ),
    render(
      'detail',
      '{{steps.item.rows}}',
      '{{item.title}}\n{{item.category}}\n\n{{item.description}}',
      empty: 'This resource is no longer available.',
      buttons: [
        {'text': 'Open link', 'url': '{{item.url}}'},
        button('{{item.favorite}}', 'lib:favorite:{{item.id}}'),
      ],
      footerButtons: homeButtons,
    ),
    sendList('detail'),
  ];
  p.command('start', home());
  p.command('library', home());
  p.command('cancel', home());
  p.click('lib:home', home());
  p.click('lib:category:', [
    setValue('category', '{{event.input}}'),
    setValue('mode', 'category'),
    setValue('page', 0),
    ...listing(),
  ], prefix: true);
  p.click('lib:favorites', [
    setValue('mode', 'favorites'),
    setValue('page', 0),
    ...listing(),
  ]);
  Acts search() => [
    setValue('searching', true),
    say(
      'prompt',
      'Send a search phrase (1–200 characters). Use /cancel to return.',
    ),
  ];
  p.command('search', search());
  p.click('lib:search', search());
  p.click('lib:open:', detail(), prefix: true);
  p.click('lib:favorite:', [
    sql(
      'saved',
      'SELECT count(*) AS n FROM library_favorites WHERE user_id=? AND item_id=?',
      ['{{event.userId}}', '{{event.input}}'],
    ),
    sql(
      'remove',
      'DELETE FROM library_favorites WHERE user_id=? AND item_id=?',
      ['{{event.userId}}', '{{event.input}}'],
      {'when': when('{{steps.saved.rows.0.n}}', 1)},
    ),
    sql(
      'save',
      'INSERT OR IGNORE INTO library_favorites SELECT ?,id FROM library_items WHERE id=?',
      ['{{event.userId}}', '{{event.input}}'],
      {'when': when('{{steps.saved.rows.0.n}}', 0)},
    ),
    ...detail(),
  ], prefix: true);
  for (final direction in ['next', 'prev']) {
    p.click('lib:$direction', [
      templateAction(
        VirtActType.incrementVariable,
        direction == 'next' ? '1' : '-1',
        'move_page',
        {'variable': 'page', 'scope': 'user'},
      ),
      ...listing(),
    ]);
  }
  p.text([
    say(
      'help',
      'Use /library to browse or /search to find a resource.',
      only: when('{{user.searching}}', false),
    ),
    check('searching', '{{user.searching}}', true),
    sql('valid', 'SELECT length(trim(?)) BETWEEN 1 AND 200 AS valid', [
      '{{event.input}}',
    ]),
    say(
      'invalid',
      'Use a search phrase with 1–200 characters, or /cancel.',
      only: when('{{steps.valid.rows.0.valid}}', 0),
    ),
    check('valid_search', '{{steps.valid.rows.0.valid}}', 1),
    setValue('search', '{{event.input}}'),
    setValue('searching', false),
    setValue('mode', 'search'),
    setValue('page', 0),
    ...listing(),
  ]);
  return p.draft;
}
