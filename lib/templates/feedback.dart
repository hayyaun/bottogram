import 'program.dart';

BotTemplateDraft buildFeedback(
  Map<String, String> settings,
  List<Map<String, dynamic>> rows,
  String admin,
) {
  final p = TemplateProgram(
    [
      sql(
        'setup_questions',
        'CREATE TABLE IF NOT EXISTS survey_questions(id INTEGER PRIMARY KEY,prompt TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN (\'rating\',\'text\')))',
      ),
      sql(
        'setup_runs',
        'CREATE TABLE IF NOT EXISTS survey_runs(user_id TEXT PRIMARY KEY,position INTEGER NOT NULL,generation INTEGER NOT NULL)',
      ),
      sql(
        'setup_drafts',
        'CREATE TABLE IF NOT EXISTS survey_drafts(user_id TEXT NOT NULL,question_id INTEGER NOT NULL REFERENCES survey_questions(id),answer TEXT NOT NULL,PRIMARY KEY(user_id,question_id))',
      ),
      sql(
        'setup_submissions',
        'CREATE TABLE IF NOT EXISTS survey_submissions(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id TEXT NOT NULL,generation INTEGER NOT NULL,created_at TEXT NOT NULL,summary TEXT NOT NULL,rating_sum INTEGER NOT NULL,rating_count INTEGER NOT NULL,UNIQUE(user_id,generation))',
      ),
      seed(
        'survey_questions',
        ['id', 'prompt', 'kind'],
        [
          for (final (i, row) in rows.indexed) {'id': i + 1, ...row},
        ],
      ),
    ],
    [variable('adminId', admin, scope: 'bot'), variable('reviewPage', 0)],
  );
  final homeKeyboard = keyboard([
    [button('Begin survey', 'survey:begin')],
  ]);
  Acts home() => [
    say(
      'welcome',
      '${settings['title']!}\nUse /cancel at any point. Admin report: /report.',
      buttons: homeKeyboard,
    ),
  ];
  p.command('start', home());
  Acts show() => [
    sql(
      'state',
      """WITH q AS (SELECT *,row_number() OVER(ORDER BY id) AS n FROM survey_questions)
SELECT r.position,coalesce(q.id,0) AS id,coalesce(q.kind,'review') AS kind,coalesce(q.prompt,'') AS prompt,
(SELECT count(*) FROM survey_questions) AS total FROM survey_runs r LEFT JOIN q ON q.n=r.position WHERE r.user_id=? AND r.position>0""",
      ['{{event.userId}}'],
    ),
    say(
      'rating',
      'Question {{steps.state.rows.0.position}} / {{steps.state.rows.0.total}}\n{{steps.state.rows.0.prompt}}\nChoose a rating from 1 to 5.',
      buttons: keyboard([
        [
          for (final n in [1, 2, 3, 4, 5])
            button('$n', 'survey:$n:{{steps.state.rows.0.id}}'),
        ],
        [button('Back', 'survey:back'), button('Cancel', 'survey:cancel')],
      ]),
      only: when('{{steps.state.rows.0.kind}}', 'rating'),
    ),
    say(
      'text',
      'Question {{steps.state.rows.0.position}} / {{steps.state.rows.0.total}}\n{{steps.state.rows.0.prompt}}\nSend your answer (1–1000 characters).',
      buttons: keyboard([
        [button('Back', 'survey:back'), button('Cancel', 'survey:cancel')],
      ]),
      only: when('{{steps.state.rows.0.kind}}', 'text'),
    ),
    sql(
      'review_page',
      'SELECT page,page+1 AS number,pages FROM (SELECT max(0,min(?,CAST((count(*)-1)/2 AS INTEGER))) AS page,max(1,CAST((count(*)+1)/2 AS INTEGER)) AS pages FROM survey_questions)',
      ['{{user.reviewPage}}'],
      {'when': when('{{steps.state.rows.0.kind}}', 'review')},
    ),
    setValue(
      'reviewPage',
      '{{steps.review_page.rows.0.page}}',
      only: when('{{steps.state.rows.0.kind}}', 'review'),
    ),
    sql(
      'review_rows',
      'SELECT q.prompt,coalesce(d.answer,\'Not answered\') AS answer FROM survey_questions q LEFT JOIN survey_drafts d ON d.question_id=q.id AND d.user_id=? ORDER BY q.id LIMIT 2 OFFSET (?*2)',
      ['{{event.userId}}', '{{user.reviewPage}}'],
      {'when': when('{{steps.state.rows.0.kind}}', 'review')},
    ),
    render(
      'review',
      '{{steps.review_rows.rows}}',
      '{{item.prompt}}\n{{item.answer}}',
      rowBlocks: [details('{{item.prompt}}', '{{item.answer}}')],
      header:
          'Review your answers · page {{steps.review_page.rows.0.number}} / {{steps.review_page.rows.0.pages}}\n\n',
      footerButtons: [
        [
          button('Previous page', 'survey:prev'),
          button('Next page', 'survey:next'),
        ],
        [button('Back', 'survey:back'), button('Submit', 'survey:submit')],
        [button('Cancel', 'survey:cancel')],
      ],
    )..config['when'] = when('{{steps.state.rows.0.kind}}', 'review'),
    sendList(
      'review',
      output: 'review_sent',
      only: when('{{steps.state.rows.0.kind}}', 'review'),
    ),
  ];
  p.click('survey:begin', [
    setValue('reviewPage', 0),
    sql('clear', 'DELETE FROM survey_drafts WHERE user_id=?', [
      '{{event.userId}}',
    ]),
    sql(
      'begin',
      'INSERT INTO survey_runs VALUES(?,1,1) ON CONFLICT(user_id) DO UPDATE SET position=1,generation=generation+1',
      ['{{event.userId}}'],
    ),
    ...show(),
  ]);
  for (final n in [1, 2, 3, 4, 5]) {
    p.click('survey:$n:', [
      sql(
        'answer',
        """WITH q AS (SELECT *,row_number() OVER(ORDER BY id) AS n FROM survey_questions)
INSERT INTO survey_drafts(user_id,question_id,answer) SELECT r.user_id,q.id,? FROM survey_runs r JOIN q ON q.n=r.position
WHERE r.user_id=? AND q.id=? AND q.kind='rating'
ON CONFLICT(user_id,question_id) DO UPDATE SET answer=excluded.answer""",
        ['$n', '{{event.userId}}', '{{event.input}}'],
      ),
      say(
        'stale',
        'This is an earlier question. Use the latest question or /start.',
        only: when('{{steps.answer.affectedRows}}', 0),
      ),
      check('valid_answer', '{{steps.answer.affectedRows}}', 0, 'greater'),
      sql(
        'advance',
        'UPDATE survey_runs SET position=position+1 WHERE user_id=?',
        ['{{event.userId}}'],
      ),
      ...show(),
    ], prefix: true);
  }
  p.click('survey:back', [
    sql(
      'back',
      'UPDATE survey_runs SET position=max(1,position-1) WHERE user_id=? AND position>0',
      ['{{event.userId}}'],
    ),
    say(
      'inactive',
      'Use /start to begin a survey.',
      only: when('{{steps.back.affectedRows}}', 0),
    ),
    check('active', '{{steps.back.affectedRows}}', 0, 'greater'),
    ...show(),
  ]);
  for (final direction in ['next', 'prev']) {
    p.click('survey:$direction', [
      sql(
        'active',
        'SELECT count(*) AS n FROM survey_runs WHERE user_id=? AND position>(SELECT count(*) FROM survey_questions)',
        ['{{event.userId}}'],
      ),
      check('reviewing', '{{steps.active.rows.0.n}}', 1),
      templateAction(
        VirtActType.incrementVariable,
        direction == 'next' ? '1' : '-1',
        'move_page',
        {'variable': 'reviewPage', 'scope': 'user'},
      ),
      ...show(),
    ]);
  }
  Acts cancel() => [
    sql('cancel', 'UPDATE survey_runs SET position=0 WHERE user_id=?', [
      '{{event.userId}}',
    ]),
    sql('clear', 'DELETE FROM survey_drafts WHERE user_id=?', [
      '{{event.userId}}',
    ]),
    ...home(),
  ];
  p.command('cancel', cancel());
  p.click('survey:cancel', cancel());
  p.click('survey:submit', [
    sql(
      'submit',
      """INSERT INTO survey_submissions(user_id,generation,created_at,summary,rating_sum,rating_count)
SELECT r.user_id,r.generation,?,group_concat(q.prompt||char(10)||d.answer,char(10)||char(10)),
sum(CASE WHEN q.kind='rating' THEN CAST(d.answer AS INTEGER) ELSE 0 END),sum(CASE WHEN q.kind='rating' THEN 1 ELSE 0 END)
FROM survey_runs r JOIN survey_drafts d ON d.user_id=r.user_id JOIN survey_questions q ON q.id=d.question_id
WHERE r.user_id=? AND r.position>(SELECT count(*) FROM survey_questions)
GROUP BY r.user_id,r.generation HAVING count(*)=(SELECT count(*) FROM survey_questions)
ON CONFLICT(user_id,generation) DO NOTHING""",
      ['{{event.timestamp}}', '{{event.userId}}'],
    ),
    say(
      'duplicate',
      'This response was already submitted or is incomplete. Use /start to begin again.',
      only: when('{{steps.submit.affectedRows}}', 0),
    ),
    check('new_submission', '{{steps.submit.affectedRows}}', 0, 'greater'),
    sql('finish', 'UPDATE survey_runs SET position=0 WHERE user_id=?', [
      '{{event.userId}}',
    ]),
    say(
      'thanks',
      'Thank you! Your feedback has been saved.',
      buttons: homeKeyboard,
    ),
  ]);
  p.command('report', [
    check('admin', '{{event.userId}}', '{{bot.adminId}}'),
    sql(
      'totals',
      'SELECT count(*) AS total,coalesce(round(sum(rating_sum)*1.0/nullif(sum(rating_count),0),2),0) AS average FROM survey_submissions',
    ),
    sql(
      'recent',
      'SELECT id,created_at,substr(summary,1,300) AS preview FROM survey_submissions ORDER BY id DESC LIMIT 5',
    ),
    render(
      'report',
      '{{steps.recent.rows}}',
      '#{{item.id}} · {{item.created_at}}\n{{item.preview}}',
      rowBlocks: [
        details(
          'Submission #{{item.id}} · {{item.created_at}}',
          '{{item.preview}}',
        ),
      ],
      header:
          'Submissions: {{steps.totals.rows.0.total}}\nAverage rating: {{steps.totals.rows.0.average}} / 5\n\nLatest five responses (300-character previews)\n\n',
    ),
    sendList('report'),
  ]);
  p.text([
    sql(
      'current',
      """WITH q AS (SELECT *,row_number() OVER(ORDER BY id) AS n FROM survey_questions)
SELECT coalesce((SELECT q.id FROM q JOIN survey_runs r ON q.n=r.position WHERE r.user_id=? AND q.kind='text'),0) AS id""",
      ['{{event.userId}}'],
    ),
    say(
      'help',
      'Use /start to begin a survey, or answer the latest question using its buttons.',
      only: when('{{steps.current.rows.0.id}}', 0),
    ),
    check('text_expected', '{{steps.current.rows.0.id}}', 0, 'greater'),
    sql(
      'answer',
      'INSERT INTO survey_drafts(user_id,question_id,answer) SELECT ?,?,trim(?) WHERE length(trim(?)) BETWEEN 1 AND 1000 ON CONFLICT(user_id,question_id) DO UPDATE SET answer=excluded.answer',
      [
        '{{event.userId}}',
        '{{steps.current.rows.0.id}}',
        '{{event.input}}',
        '{{event.input}}',
      ],
    ),
    say(
      'invalid',
      'Please use 1–1000 characters, or /cancel.',
      only: when('{{steps.answer.affectedRows}}', 0),
    ),
    check('valid_answer', '{{steps.answer.affectedRows}}', 0, 'greater'),
    sql(
      'advance',
      'UPDATE survey_runs SET position=position+1 WHERE user_id=?',
      ['{{event.userId}}'],
    ),
    ...show(),
  ]);
  return p.finish('Feedback');
}
