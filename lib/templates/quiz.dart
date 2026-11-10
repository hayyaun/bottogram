import 'program.dart';

BotTemplateDraft buildQuiz(
  Map<String, String> settings,
  List<Map<String, dynamic>> rows,
  String admin,
) {
  final p = TemplateProgram([
    sql(
      'setup_questions',
      'CREATE TABLE IF NOT EXISTS quiz_questions(id INTEGER PRIMARY KEY,topic TEXT NOT NULL,question TEXT NOT NULL,a TEXT NOT NULL,b TEXT NOT NULL,c TEXT NOT NULL,correct TEXT NOT NULL,explanation TEXT NOT NULL)',
    ),
    sql(
      'setup_runs',
      'CREATE TABLE IF NOT EXISTS quiz_runs(user_id TEXT PRIMARY KEY,topic TEXT NOT NULL,position INTEGER NOT NULL,score INTEGER NOT NULL)',
    ),
    sql(
      'setup_scores',
      'CREATE TABLE IF NOT EXISTS quiz_scores(user_id TEXT NOT NULL,topic TEXT NOT NULL,best INTEGER NOT NULL,PRIMARY KEY(user_id,topic))',
    ),
    seed(
      'quiz_questions',
      ['id', 'topic', 'question', 'a', 'b', 'c', 'correct', 'explanation'],
      [
        for (final (i, row) in rows.indexed) {'id': i + 1, ...row},
      ],
    ),
  ]);
  Acts menu() => [
    sql(
      'topics',
      'SELECT topic,count(*) AS total FROM quiz_questions GROUP BY topic ORDER BY topic LIMIT 20',
    ),
    render(
      'menu',
      '{{steps.topics.rows}}',
      '{{item.topic}} · {{item.total}} questions',
      header: '${settings['title']!}\n\n',
      buttons: [button('Start {{item.topic}}', 'quiz:topic:{{item.topic}}')],
      footerButtons: [
        [button('My best scores', 'quiz:scores')],
      ],
    ),
    sendList('menu'),
  ];
  p.command('start', menu());
  p.click('quiz:home', menu());
  Acts showQuestion() => [
    sql(
      'stats',
      'SELECT r.*, (SELECT count(*) FROM quiz_questions WHERE topic=r.topic) AS total, coalesce((SELECT best FROM quiz_scores WHERE user_id=r.user_id AND topic=r.topic),0) AS best FROM quiz_runs r WHERE user_id=?',
      ['{{event.userId}}'],
    ),
    sql(
      'question',
      'WITH q AS (SELECT *,row_number() OVER(PARTITION BY topic ORDER BY id) AS n FROM quiz_questions) SELECT q.* FROM q JOIN quiz_runs r ON q.topic=r.topic AND q.n=r.position+1 WHERE r.user_id=?',
      ['{{event.userId}}'],
    ),
    render(
      'view',
      '{{steps.question.rows}}',
      '{{item.question}}\nA. {{item.a}}\nB. {{item.b}}\nC. {{item.c}}',
      header:
          '{{steps.stats.rows.0.topic}} · {{steps.stats.rows.0.position}} answered\n\n',
      empty:
          'Finished! Score: {{steps.stats.rows.0.score}} / {{steps.stats.rows.0.total}}\nPersonal best: {{steps.stats.rows.0.best}}',
      buttons: [
        for (final letter in ['A', 'B', 'C'])
          button(letter, 'quiz:$letter:{{item.id}}'),
      ],
      footerButtons: [
        [
          button('Topics', 'quiz:home'),
          button('My best scores', 'quiz:scores'),
        ],
      ],
    ),
    sendList('view'),
  ];
  p.click('quiz:topic:', [
    sql(
      'begin',
      'INSERT INTO quiz_runs(user_id,topic,position,score) SELECT ?,?,0,0 WHERE EXISTS(SELECT 1 FROM quiz_questions WHERE topic=?) ON CONFLICT(user_id) DO UPDATE SET topic=excluded.topic,position=0,score=0',
      ['{{event.userId}}', '{{event.input}}', '{{event.input}}'],
    ),
    say(
      'missing_topic',
      'This topic is no longer available. Use /start.',
      only: when('{{steps.begin.affectedRows}}', 0),
    ),
    check('topic_exists', '{{steps.begin.affectedRows}}', 0, 'greater'),
    ...showQuestion(),
  ], prefix: true);
  for (final letter in ['A', 'B', 'C']) {
    p.click('quiz:$letter:', [
      sql(
        'answer',
        'WITH q AS (SELECT id,correct,row_number() OVER(ORDER BY id) AS n FROM quiz_questions WHERE topic=(SELECT topic FROM quiz_runs WHERE user_id=?)) UPDATE quiz_runs SET score=score+CASE WHEN (SELECT correct FROM q WHERE id=?)=? THEN 1 ELSE 0 END,position=position+1 WHERE user_id=? AND EXISTS(SELECT 1 FROM q WHERE id=? AND n=quiz_runs.position+1)',
        [
          '{{event.userId}}',
          '{{event.input}}',
          letter,
          '{{event.userId}}',
          '{{event.input}}',
        ],
      ),
      say(
        'stale',
        'This question was already answered or belongs to an earlier quiz.',
        only: when('{{steps.answer.affectedRows}}', 0),
      ),
      check('fresh_answer', '{{steps.answer.affectedRows}}', 0, 'greater'),
      sql(
        'explanation',
        'SELECT CASE WHEN correct=? THEN \'Correct!\' ELSE \'Not quite.\' END AS result,correct,explanation FROM quiz_questions WHERE id=?',
        [letter, '{{event.input}}'],
      ),
      say(
        'feedback',
        '{{steps.explanation.rows.0.result}} Answer: {{steps.explanation.rows.0.correct}}\n{{steps.explanation.rows.0.explanation}}',
      ),
      sql(
        'best',
        'INSERT INTO quiz_scores(user_id,topic,best) SELECT user_id,topic,score FROM quiz_runs WHERE user_id=? AND position=(SELECT count(*) FROM quiz_questions WHERE topic=quiz_runs.topic) ON CONFLICT(user_id,topic) DO UPDATE SET best=max(best,excluded.best)',
        ['{{event.userId}}'],
      ),
      ...showQuestion(),
    ], prefix: true);
  }
  Acts scores() => [
    sql(
      'scores',
      'SELECT topic,best FROM quiz_scores WHERE user_id=? ORDER BY topic LIMIT 20',
      ['{{event.userId}}'],
    ),
    render(
      'scores_view',
      '{{steps.scores.rows}}',
      '{{item.topic}}: {{item.best}}',
      empty: 'Finish a quiz to record your first score.',
      footerButtons: [
        [button('Topics', 'quiz:home')],
      ],
    ),
    sendList('scores_view'),
  ];
  p.command('score', scores());
  p.click('quiz:scores', scores());
  return p.draft;
}
