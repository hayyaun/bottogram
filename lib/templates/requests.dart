import 'program.dart';

BotTemplateDraft buildRequests(
  Map<String, String> settings,
  List<Map<String, dynamic>> rows,
  String admin,
) {
  final p = TemplateProgram(
    [
      sql(
        'setup_requests',
        """CREATE TABLE IF NOT EXISTS requests(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id TEXT NOT NULL,subject TEXT NOT NULL,body TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'Open',reply TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL)""",
      ),
      sql(
        'setup_request_index',
        'CREATE INDEX IF NOT EXISTS requests_user ON requests(user_id,id)',
      ),
    ],
    [
      variable('adminId', admin, scope: 'bot'),
      variable('flow', 'idle'),
      variable('subject', ''),
      variable('requestId', 0),
      variable('page', 0),
    ],
  );
  final homeKeyboard = keyboard([
    [
      button('New request', 'request:new'),
      button('My requests', 'request:list'),
    ],
  ]);
  Acts home() => [
    setValue('flow', 'idle'),
    say(
      'welcome',
      '${settings['title']!}\nAdmin inbox: /inbox',
      buttons: homeKeyboard,
    ),
  ];
  p.command('start', home());
  p.command('cancel', home());
  p.click('request:new', [
    setValue('flow', 'subject'),
    say('subject', 'Send a short subject (1–120 characters), or /cancel.'),
  ]);
  Acts listing({bool inbox = false}) => [
    if (inbox) check('admin', '{{event.userId}}', '{{bot.adminId}}'),
    sql(
      'page',
      'SELECT max(0,min(?,max(0,CAST((count(*)-1)/5 AS INTEGER)))) AS page FROM requests WHERE ${inbox ? '1=1' : 'user_id=?'}',
      ['{{user.page}}', if (!inbox) '{{event.userId}}'],
    ),
    setValue('page', '{{steps.page.rows.0.page}}'),
    sql(
      'requests',
      'SELECT id,subject,status FROM requests WHERE ${inbox ? '1=1' : 'user_id=?'} ORDER BY id DESC LIMIT 5 OFFSET (?*5)',
      [if (!inbox) '{{event.userId}}', '{{user.page}}'],
    ),
    render(
      'list',
      '{{steps.requests.rows}}',
      '#{{item.id}} · {{item.subject}}\n{{item.status}}',
      header: inbox ? 'Request inbox\n\n' : 'Your requests\n\n',
      buttons: [button('Open #{{item.id}}', 'request:open:{{item.id}}')],
      footerButtons: [
        [
          button('Previous', inbox ? 'request:adminprev' : 'request:prev'),
          button('Next', inbox ? 'request:adminnext' : 'request:next'),
        ],
        [button('New request', 'request:new')],
      ],
    ),
    sendList('list'),
  ];
  p.command('inbox', [setValue('page', 0), ...listing(inbox: true)]);
  p.click('request:list', [setValue('page', 0), ...listing()]);
  for (final inbox in [false, true]) {
    for (final direction in ['next', 'prev']) {
      p.click('request:${inbox ? 'admin' : ''}$direction', [
        templateAction(
          VirtActType.incrementVariable,
          direction == 'next' ? '1' : '-1',
          'move_page',
          {'variable': 'page', 'scope': 'user'},
        ),
        ...listing(inbox: inbox),
      ]);
    }
  }
  p.click('request:open:', [
    sql(
      'request',
      'SELECT *,CASE WHEN reply=\'\' THEN \'Awaiting a reply\' ELSE reply END AS response FROM requests WHERE id=? AND (user_id=? OR CAST(? AS TEXT)=CAST(? AS TEXT))',
      [
        '{{event.input}}',
        '{{event.userId}}',
        '{{event.userId}}',
        '{{bot.adminId}}',
      ],
    ),
    render(
      'detail',
      '{{steps.request.rows}}',
      '#{{item.id}} · {{item.subject}}\nStatus: {{item.status}}\n\n{{item.body}}\n\nReply: {{item.response}}',
      empty: 'This request is not available to you.',
      footerButtons: [
        [button('My requests', 'request:list')],
      ],
    ),
    sendList('detail'),
    render(
      'controls',
      '{{steps.request.rows}}',
      'Admin controls for #{{item.id}}',
      buttons: [
        button('Reply', 'request:reply:{{item.id}}'),
        button('Close', 'request:close:{{item.id}}'),
        button('Reopen', 'request:reopen:{{item.id}}'),
      ],
    )..config['when'] = when('{{event.userId}}', '{{bot.adminId}}'),
    sendList(
      'controls',
      output: 'controls_sent',
      only: when('{{event.userId}}', '{{bot.adminId}}'),
    ),
  ], prefix: true);
  p.click('request:reply:', [
    check('admin', '{{event.userId}}', '{{bot.adminId}}'),
    sql('exists', 'SELECT count(*) AS n FROM requests WHERE id=?', [
      '{{event.input}}',
    ]),
    say(
      'missing',
      'This request no longer exists.',
      only: when('{{steps.exists.rows.0.n}}', 0),
    ),
    check('exists_check', '{{steps.exists.rows.0.n}}', 1),
    setValue('requestId', '{{event.input}}'),
    setValue('flow', 'adminReply'),
    say(
      'prompt',
      'Send the reply for request #{{event.input}} (1–1800 characters), or /cancel.',
    ),
  ], prefix: true);
  for (final operation in ['close', 'reopen']) {
    p.click('request:$operation:', [
      check('admin', '{{event.userId}}', '{{bot.adminId}}'),
      sql('updated', 'UPDATE requests SET status=? WHERE id=?', [
        operation == 'close' ? 'Closed' : 'Open',
        '{{event.input}}',
      ]),
      say(
        'status',
        'Request status updated.',
        buttons: homeKeyboard,
        only: when('{{steps.updated.affectedRows}}', 0, 'greater'),
      ),
      say(
        'missing',
        'This request no longer exists.',
        only: when('{{steps.updated.affectedRows}}', 0),
      ),
    ], prefix: true);
  }
  p.text([
    sql('input', 'SELECT ? AS stage,length(trim(?)) AS n', [
      '{{user.flow}}',
      '{{event.input}}',
    ]),
    say(
      'help',
      'Use /start and choose New request.',
      only: when('{{steps.input.rows.0.stage}}', 'idle'),
    ),
    check('in_flow', '{{steps.input.rows.0.stage}}', 'idle', 'notEquals'),
    sql(
      'valid',
      'SELECT CASE WHEN ?=\'subject\' THEN ? BETWEEN 1 AND 120 ELSE ? BETWEEN 1 AND 1800 END AS valid',
      [
        '{{steps.input.rows.0.stage}}',
        '{{steps.input.rows.0.n}}',
        '{{steps.input.rows.0.n}}',
      ],
    ),
    say(
      'invalid',
      'Use 1–120 characters for a subject or 1–1800 for a message. Try again or /cancel.',
      only: when('{{steps.valid.rows.0.valid}}', 0),
    ),
    check('valid_input', '{{steps.valid.rows.0.valid}}', 1),
    setValue(
      'subject',
      '{{event.input}}',
      only: when('{{steps.input.rows.0.stage}}', 'subject'),
    ),
    setValue(
      'flow',
      'body',
      only: when('{{steps.input.rows.0.stage}}', 'subject'),
    ),
    say(
      'body_prompt',
      'Now send the details (1–1800 characters), or /cancel.',
      only: when('{{steps.input.rows.0.stage}}', 'subject'),
    ),
    sql(
      'created',
      'INSERT INTO requests(user_id,subject,body,created_at) VALUES(?,?,?,?)',
      [
        '{{event.userId}}',
        '{{user.subject}}',
        '{{event.input}}',
        '{{event.timestamp}}',
      ],
      {'when': when('{{steps.input.rows.0.stage}}', 'body')},
    ),
    say(
      'receipt',
      'Your request has been saved.\nTracking number: #{{steps.created.lastInsertRowId}}\nUse My requests to follow its status.',
      buttons: homeKeyboard,
      only: when('{{steps.input.rows.0.stage}}', 'body'),
    ),
    templateAction(
      VirtActType.reply,
      'New request #{{steps.created.lastInsertRowId}}\n{{user.subject}}\nUse /inbox to reply.',
      'notify_admin',
      {
        'chatId': '{{bot.adminId}}',
        'when': when('{{steps.input.rows.0.stage}}', 'body'),
        'onError': 'continue',
      },
    ),
    sql(
      'replied',
      'UPDATE requests SET reply=?,status=\'Replied\' WHERE id=? AND CAST(? AS TEXT)=CAST(? AS TEXT) RETURNING user_id,id',
      [
        '{{event.input}}',
        '{{user.requestId}}',
        '{{event.userId}}',
        '{{bot.adminId}}',
      ],
      {'when': when('{{steps.input.rows.0.stage}}', 'adminReply')},
    ),
    templateAction(
      VirtActType.reply,
      'Reply to request #{{steps.replied.rows.0.id}}\n\n{{event.input}}',
      'notify_user',
      {
        'chatId': '{{steps.replied.rows.0.user_id}}',
        'when': when('{{steps.input.rows.0.stage}}', 'adminReply'),
        'onError': 'continue',
      },
    ),
    say(
      'saved_reply',
      'Reply saved. The requester can also read it under My requests.',
      buttons: homeKeyboard,
      only: when('{{steps.input.rows.0.stage}}', 'adminReply'),
    ),
    setValue(
      'flow',
      'idle',
      only: when('{{steps.input.rows.0.stage}}', 'subject', 'notEquals'),
    ),
  ]);
  return p.draft;
}
