import 'program.dart';

BotTemplateDraft buildTasks(
  Map<String, String> settings,
  List<Map<String, dynamic>> rows,
  String admin,
) {
  final p = TemplateProgram(
    [
      sql(
        'setup_tasks',
        'CREATE TABLE IF NOT EXISTS tasks(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id TEXT NOT NULL,title TEXT NOT NULL,done INTEGER NOT NULL DEFAULT 0 CHECK(done IN (0,1)))',
      ),
      sql(
        'setup_task_index',
        'CREATE INDEX IF NOT EXISTS tasks_user ON tasks(user_id,id)',
      ),
    ],
    [variable('page', 0), variable('addingTask', false)],
  );
  Acts view() => [
    sql(
      'page',
      'SELECT page,page+1 AS number,pages FROM (SELECT max(0,min(?,max(0,CAST((count(*)-1)/5 AS INTEGER)))) AS page,max(1,CAST((count(*)+4)/5 AS INTEGER)) AS pages FROM tasks WHERE user_id=?)',
      ['{{user.page}}', '{{event.userId}}'],
    ),
    setValue('page', '{{steps.page.rows.0.page}}'),
    sql(
      'tasks',
      'SELECT id,title,CASE WHEN done=1 THEN \'Done\' ELSE \'Open\' END AS status,CASE WHEN done=1 THEN \'Reopen\' ELSE \'Complete\' END AS action FROM tasks WHERE user_id=? ORDER BY id DESC LIMIT 5 OFFSET (?*5)',
      ['{{event.userId}}', '{{user.page}}'],
    ),
    render(
      'view',
      '{{steps.tasks.rows}}',
      '{{item.status}} · {{item.title}}',
      header:
          '${settings['title']!}\nPage {{steps.page.rows.0.number}} / {{steps.page.rows.0.pages}}\n\n',
      empty: 'No tasks yet. Add your first task below.',
      buttons: [
        button('{{item.action}}', 'task:toggle:{{item.id}}'),
        button('Delete', 'task:delete:{{item.id}}'),
      ],
      footerButtons: [
        [button('Previous', 'task:prev'), button('Next', 'task:next')],
        [button('Add task', 'task:add')],
      ],
    ),
    sendList('view'),
  ];
  Acts home() => [
    setValue('addingTask', false),
    setValue('page', 0),
    ...view(),
  ];
  p.command('start', home());
  p.command('tasks', home());
  p.command('cancel', home());
  p.click('task:home', home());
  p.click('task:add', [
    setValue('addingTask', true),
    say(
      'prompt',
      'Send the task text (1–200 characters). Use /cancel to return.',
    ),
  ]);
  for (final direction in ['next', 'prev']) {
    p.click('task:$direction', [
      templateAction(
        VirtActType.incrementVariable,
        direction == 'next' ? '1' : '-1',
        'move_page',
        {'variable': 'page', 'scope': 'user'},
      ),
      ...view(),
    ]);
  }
  for (final operation in ['toggle', 'delete']) {
    p.click('task:$operation:', [
      sql(
        'changed',
        operation == 'toggle'
            ? 'UPDATE tasks SET done=1-done WHERE user_id=? AND id=?'
            : 'DELETE FROM tasks WHERE user_id=? AND id=?',
        ['{{event.userId}}', '{{event.input}}'],
      ),
      say(
        'missing',
        'This task is no longer available.',
        only: when('{{steps.changed.affectedRows}}', 0),
      ),
      ...view(),
    ], prefix: true);
  }
  p.text([
    say(
      'help',
      'Use /tasks to view your list, then choose Add task.',
      only: when('{{user.addingTask}}', false),
    ),
    check('adding', '{{user.addingTask}}', true),
    sql(
      'added',
      'INSERT INTO tasks(user_id,title) SELECT ?,trim(?) WHERE length(trim(?)) BETWEEN 1 AND 200',
      ['{{event.userId}}', '{{event.input}}', '{{event.input}}'],
    ),
    say(
      'invalid',
      'Use 1–200 characters for a task. Send a shorter task or /cancel.',
      only: when('{{steps.added.affectedRows}}', 0),
    ),
    check('valid_task', '{{steps.added.affectedRows}}', 0, 'greater'),
    setValue('addingTask', false),
    setValue('page', 0),
    ...view(),
  ]);
  return p.draft;
}
