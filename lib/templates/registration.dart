import 'program.dart';

BotTemplateDraft buildRegistration(
  Map<String, String> settings,
  List<Map<String, dynamic>> rows,
  String admin,
) {
  final p = TemplateProgram([
    sql(
      'setup_events',
      'CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY,title TEXT NOT NULL,details TEXT NOT NULL,capacity INTEGER NOT NULL CHECK(capacity>0))',
    ),
    sql(
      'setup_registrations',
      'CREATE TABLE IF NOT EXISTS registrations(event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,user_id TEXT NOT NULL,name TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(event_id,user_id))',
    ),
    seed(
      'events',
      ['id', 'title', 'details', 'capacity'],
      [
        for (final (i, row) in rows.indexed) {'id': i + 1, ...row},
      ],
    ),
  ]);
  Acts home() => [
    sql(
      'events',
      'SELECT e.*,max(0,capacity-(SELECT count(*) FROM registrations WHERE event_id=e.id)) AS remaining FROM events e ORDER BY id LIMIT 20',
    ),
    render(
      'events_view',
      '{{steps.events.rows}}',
      '{{item.title}}\nSeats remaining: {{item.remaining}} / {{item.capacity}}',
      header: '${settings['title']!}\n\n',
      buttons: [button('Details', 'reg:open:{{item.id}}')],
    ),
    sendList('events_view'),
  ];
  Acts detail() => [
    sql(
      'event',
      'SELECT e.*,max(0,capacity-(SELECT count(*) FROM registrations WHERE event_id=e.id)) AS remaining,CASE WHEN EXISTS(SELECT 1 FROM registrations WHERE event_id=e.id AND user_id=?) THEN \'You are registered\' ELSE \'You are not registered\' END AS status FROM events e WHERE id=?',
      ['{{event.userId}}', '{{event.input}}'],
    ),
    render(
      'detail',
      '{{steps.event.rows}}',
      '{{item.title}}\n{{item.details}}\n\nSeats remaining: {{item.remaining}} / {{item.capacity}}\n{{item.status}}',
      empty: 'This event is no longer available.',
      rowBlocks: [
        heading('{{item.title}}'),
        paragraph(
          '{{item.status}} · {{item.remaining}} of {{item.capacity}} seats left',
        ),
        details('Event details', '{{item.details}}'),
      ],
      buttons: [
        button('Register', 'reg:join:{{item.id}}'),
        button('Cancel registration', 'reg:cancel:{{item.id}}'),
      ],
      footerButtons: [
        [button('All events', 'reg:home')],
      ],
    ),
    sendList('detail'),
  ];
  p.command('start', home());
  p.command('events', home());
  p.click('reg:home', home());
  p.click('reg:open:', detail(), prefix: true);
  p.click('reg:join:', [
    sql(
      'registered',
      'INSERT OR IGNORE INTO registrations(event_id,user_id,name,created_at) SELECT id,?,?,? FROM events WHERE id=? AND (SELECT count(*) FROM registrations WHERE event_id=events.id)<capacity',
      [
        '{{event.userId}}',
        '{{event.firstName}}',
        '{{event.timestamp}}',
        '{{event.input}}',
      ],
    ),
    sql(
      'result',
      'SELECT CASE WHEN EXISTS(SELECT 1 FROM registrations WHERE event_id=? AND user_id=?) THEN \'Your registration is confirmed.\' WHEN EXISTS(SELECT 1 FROM events WHERE id=?) THEN \'This event is full. Please check again later.\' ELSE \'This event is no longer available.\' END AS message',
      ['{{event.input}}', '{{event.userId}}', '{{event.input}}'],
    ),
    say('confirmation', '{{steps.result.rows.0.message}}'),
    ...detail(),
  ], prefix: true);
  p.click('reg:cancel:', [
    sql(
      'cancelled',
      'DELETE FROM registrations WHERE event_id=? AND user_id=?',
      ['{{event.input}}', '{{event.userId}}'],
    ),
    say('cancelled_notice', 'You have no active registration for this event.'),
    ...detail(),
  ], prefix: true);
  p.command('registrations', [
    check('admin', '{{event.isAdmin}}', true),
    sql(
      'counts',
      'SELECT title,capacity,(SELECT count(*) FROM registrations WHERE event_id=e.id) AS registered FROM events e ORDER BY id LIMIT 20',
    ),
    render(
      'report',
      '{{steps.counts.rows}}',
      '{{item.title}}: {{item.registered}} / {{item.capacity}}',
      header: 'Registration report',
      columns: {
        'Event': '{{item.title}}',
        'Registered': '{{item.registered}}',
        'Capacity': '{{item.capacity}}',
      },
    ),
    sendList('report'),
  ]);
  return p.finish('Event Registration');
}
