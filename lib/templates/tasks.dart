import 'dart:convert';

import 'program.dart';
import 'task_widget.dart';

const _revision = '{{event.updateId}}';
const _buttonValue = '{{event.inputParts.1}}';
const _taskId = '{{steps.task.rows.0.id}}';
const _taskTitle = '{{steps.task.rows.0.title}}';

BotTemplateDraft buildTasks(
  Map<String, String> settings,
  List<Map<String, dynamic>> rows,
  String admin,
) {
  final program = TemplateProgram(
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
    [
      variable('tab', 0),
      variable('page', 0),
      variable('panelMessage', 0),
      variable('panelWidget', false),
      variable('textBoard', false),
      variable('panelRevision', 0),
      variable('inputMode', 'browse'),
      variable('renameTask', 0),
    ],
  );

  Map<String, dynamic> control(
    String text,
    String action, {
    String? value,
    String? style,
    Map<String, dynamic>? only,
  }) => button(
    text,
    ['task', action, _revision, if (value != null) value].join(':'),
    style: style,
    only: only,
  );

  VirtAct answer(String name, String text, {Map<String, dynamic>? only}) =>
      templateAction(VirtActType.callbackAnswer, text, name, {
        'onError': 'continue',
        if (only != null) 'when': only,
      });

  void click(String action, Acts actions) {
    const message = '{{event.messageId}}';
    const panelMessage = '{{user.panelMessage}}';
    const revision = '{{event.inputParts.0}}';
    const panelRevision = '{{user.panelRevision}}';
    const stale = 'This view has changed. Use the latest task board or /tasks.';
    program.click(
      'task:$action:',
      [
        answer(
          'old_message',
          stale,
          only: when(message, panelMessage, 'notEquals'),
        ),
        check('current_message', message, panelMessage),
        answer(
          'old_view',
          stale,
          only: when(revision, panelRevision, 'notEquals'),
        ),
        check('current_view', revision, panelRevision),
        answer('acknowledge', ''),
        ...actions,
      ],
      prefix: true,
      inputSeparator: ':',
    );
    program.events.last.config['widgetQueries'] = true;
  }

  Map<String, dynamic> widgetCondition(bool fresh) => fresh
      ? when('{{user.textBoard}}', false)
      : when('{{user.panelWidget}}', true);

  Acts publish(
    VirtAct message,
    Object widgetState, {
    bool fresh = false,
    String mode = 'browse',
  }) {
    final output = message.config['output'];
    message.config.addAll({
      'widgetChatData': jsonEncode(widgetState),
      'widgetWhen': widgetCondition(fresh),
      if (fresh) ...{
        'widgetHtml': taskBoardWidget,
        'widgetCaption': 'Task board · For the text version, send /tasks_text.',
        'widgetQueries': true,
        'onError': 'continue',
      },
    });
    if (!fresh) {
      message
        ..type = VirtActType.editText
        ..config['messageId'] = '{{user.panelMessage}}'
        ..config['onError'] = 'continue';
    }
    return [
      message,
      say(
        'recover_$output',
        fresh
            ? 'Could not open the board. Send /tasks_text to open the text version.'
            : 'The board could not refresh. Open /tasks or /tasks_text to see your current list.',
        only: when('{{steps.$output.ok}}', false),
      ),
      check('updated_$output', '{{steps.$output.ok}}', true),
      if (fresh) ...[
        setValue('panelMessage', '{{steps.$output.messageId}}'),
        setValue('panelWidget', '{{steps.$output.widget}}'),
      ],
      setValue('panelRevision', _revision),
      setValue(
        'inputMode',
        mode,
        only: when('{{user.inputMode}}', mode, 'notEquals'),
      ),
    ];
  }

  Acts card(
    String title,
    String body,
    List<List<Map<String, dynamic>>> controls, {
    bool fresh = false,
    String mode = 'browse',
    required String widgetView,
    String? note,
    String output = 'panel',
  }) => publish(
    say(
      output,
      '$title\n$body',
      rich: [
        heading(title),
        paragraph(body),
        if (note != null) paragraph(note),
      ],
      buttons: keyboard(controls),
    ),
    {
      'v': widgetView,
      'r': _revision,
      if (widgetView != 'add') ...{
        'i': '{{steps.task.rows.0.widget_id}}',
        'h': '{{steps.task.rows.0.widget_title}}',
      },
      if (widgetView == 'details') 'status': '{{steps.task.rows.0.status}}',
    },
    fresh: fresh,
    mode: mode,
  );

  Acts board({bool fresh = false}) => [
    sql(
      'pages',
      '''
WITH counts AS (
  SELECT count(*) FILTER (WHERE done=0) AS open_count,
         count(*) FILTER (WHERE done=1) AS done_count
  FROM tasks WHERE user_id=?
), totals AS (
  SELECT *, ? AS tab FROM counts
), pages AS (
  SELECT *, max(1, ((CASE WHEN tab=1 THEN done_count ELSE open_count END)+4)/5) AS pages
  FROM totals
), position AS (
  SELECT *, max(0,min(?,pages-1)) AS page FROM pages
)
SELECT *, page-1 AS previous, page+1 AS next,
       CASE WHEN tab=0 THEN '• Open' ELSE 'Open' END AS open_tab,
       CASE WHEN tab=1 THEN '• Completed' ELSE 'Completed' END AS done_tab,
       (CASE WHEN tab=1 THEN 'Completed tasks' ELSE 'Open tasks' END) ||
       (CASE WHEN pages>1 THEN ' · Page ' || (page+1) || ' of ' || pages ELSE '' END) AS view_label,
       CASE WHEN tab=1 THEN 'Completed tasks will appear here.'
            ELSE 'No open tasks. Tap Add task or type /add followed by a task name.' END AS empty_text,
       CASE WHEN length(CAST(json_quote(?) AS BLOB))<=80
            THEN ? ELSE substr(?,1,12)||'…' END AS widget_title
FROM position
''',
      [
        '{{event.userId}}',
        '{{user.tab}}',
        '{{user.page}}',
        for (var i = 0; i < 3; i++) settings['title']!,
      ],
    ),
    sql(
      'tasks',
      '''
SELECT id,title,CASE WHEN done=1 THEN 'Reopen' ELSE 'Complete' END AS action,
       CASE WHEN done=1 THEN 'reopen' ELSE 'complete' END AS callback,
       CAST(id AS TEXT) AS widget_id,
       CASE WHEN length(CAST(json_quote(title) AS BLOB))<=120
            THEN title ELSE substr(title,1,18)||'…' END AS widget_title
FROM tasks WHERE user_id=? AND done=? ORDER BY id DESC LIMIT 5 OFFSET (?*5)
''',
      ['{{event.userId}}', '{{user.tab}}', '{{steps.pages.rows.0.page}}'],
    ),
    render(
      'board',
      '{{steps.tasks.rows}}',
      '{{item.title}}',
      header: '${settings['title']!}\n{{steps.pages.rows.0.view_label}}\n\n',
      empty: '{{steps.pages.rows.0.empty_text}}',
      groupItemButtons: true,
      itemData: ['{{item.widget_id}}', '{{item.widget_title}}'],
      buttons: [
        control('{{item.action}}', '{{item.callback}}', value: '{{item.id}}'),
        control('Details', 'details', value: '{{item.id}}'),
      ],
      footerButtons: [
        [
          control(
            '‹ Previous',
            'page',
            value: '{{steps.pages.rows.0.previous}}',
            only: when('{{steps.pages.rows.0.page}}', 0, 'greater'),
          ),
          control(
            'Next ›',
            'page',
            value: '{{steps.pages.rows.0.next}}',
            only: when(
              '{{steps.pages.rows.0.next}}',
              '{{steps.pages.rows.0.pages}}',
              'less',
            ),
          ),
        ],
        [
          control(
            '{{steps.pages.rows.0.open_tab}} · {{steps.pages.rows.0.open_count}}',
            'open',
          ),
          control(
            '{{steps.pages.rows.0.done_tab}} · {{steps.pages.rows.0.done_count}}',
            'completed',
          ),
        ],
        [control('+ Add task', 'add', style: 'primary')],
      ],
    ),
    ...publish(sendList('board', output: 'panel'), {
      'v': 'board',
      'r': _revision,
      'h': '{{steps.pages.rows.0.widget_title}}',
      't': '{{user.tab}}',
      'p': '{{steps.pages.rows.0.page}}',
      'n': '{{steps.pages.rows.0.pages}}',
      'a': '{{steps.pages.rows.0.open_count}}',
      'd': '{{steps.pages.rows.0.done_count}}',
      'l': '{{steps.board.items}}',
    }, fresh: fresh),
  ];

  Acts openBoard() => [
    setValue('tab', 0),
    setValue('page', 0),
    ...board(fresh: true),
  ];

  Acts addPrompt({bool fresh = false}) => card(
    'Add a task',
    'Send the task name as your next message.',
    [
      [control('Cancel', 'back')],
    ],
    fresh: fresh,
    mode: 'add',
    widgetView: 'add',
    output: fresh ? 'add_prompt' : 'panel',
  );

  Acts findTask() => [
    sql(
      'task',
      '''
SELECT coalesce(t.id,0) AS id, t.title, CAST(t.id AS TEXT) AS widget_id,
       CASE WHEN length(CAST(json_quote(t.title) AS BLOB))<=800
            THEN t.title ELSE substr(t.title,1,120)||'…' END AS widget_title,
       CASE WHEN t.done=1 THEN 'Completed' ELSE 'Open' END AS status
FROM (SELECT 1) LEFT JOIN tasks t ON t.user_id=? AND t.id=?
''',
      ['{{event.userId}}', _buttonValue],
    ),
    say(
      'missing_task',
      'This task is no longer available. Open /tasks to refresh.',
      only: when(_taskId, 0),
    ),
    check('task_exists', _taskId, 0, 'greater'),
  ];

  Acts saveTitle(
    String input, {
    bool fresh = false,
    bool onlyWithArguments = false,
  }) {
    final adding = fresh ? null : when('{{user.inputMode}}', 'add');
    final actions = <VirtAct>[
      sql(
        'title',
        'SELECT value, length(value) BETWEEN 1 AND 200 AS valid FROM (SELECT trim(?,char(9,10,11,12,13,32)) AS value)',
        [input],
      ),
      say(
        'invalid_title',
        fresh
            ? 'Use 1–200 characters for the task name. Try /add again.'
            : 'Use 1–200 characters for the task name. Send another name or tap Cancel.',
        only: when('{{steps.title.rows.0.valid}}', 0),
      ),
      check('valid_title', '{{steps.title.rows.0.valid}}', 1),
      sql(
        'insert_task',
        'INSERT INTO tasks(user_id,title) VALUES(?,?)',
        ['{{event.userId}}', '{{steps.title.rows.0.value}}'],
        {if (adding != null) 'when': adding},
      ),
      if (!fresh)
        sql(
          'rename_task',
          'UPDATE tasks SET title=? WHERE user_id=? AND id=?',
          [
            '{{steps.title.rows.0.value}}',
            '{{event.userId}}',
            '{{user.renameTask}}',
          ],
          {'when': when('{{user.inputMode}}', 'rename')},
        ),
      setValue('tab', 0, only: adding),
      setValue('page', 0, only: adding),
      setValue(
        'inputMode',
        'browse',
        only: when('{{user.inputMode}}', 'browse', 'notEquals'),
      ),
      ...board(fresh: fresh),
    ];
    if (onlyWithArguments) {
      for (final action in actions) {
        final condition = action.config['when'];
        action.config['when'] = {
          'all': [
            when('{{event.argumentsText}}', '', 'notEquals'),
            if (condition != null) condition,
          ],
        };
      }
    }
    return actions;
  }

  program.command('start', openBoard());
  program.command('tasks', openBoard());
  program.command('tasks_text', [setValue('textBoard', true), ...openBoard()]);
  program.command('tasks_widget', [
    setValue('textBoard', false),
    ...openBoard(),
  ]);
  program.command('cancel', openBoard());
  program.command('add', [
    ...saveTitle(
      '{{event.argumentsText}}',
      fresh: true,
      onlyWithArguments: true,
    ),
    check('prompt_only', '{{event.argumentsText}}', ''),
    ...addPrompt(fresh: true),
  ]);

  click('add', addPrompt());
  click('back', board());
  for (final (view, tab) in [('open', 0), ('completed', 1)]) {
    click(view, [
      check('different_tab', '{{user.tab}}', tab, 'notEquals'),
      setValue('tab', tab),
      setValue('page', 0),
      ...board(),
    ]);
  }
  click('page', [setValue('page', _buttonValue), ...board()]);
  for (final (action, from, to) in [('complete', 0, 1), ('reopen', 1, 0)]) {
    click(action, [
      sql(
        'set_status',
        'UPDATE tasks SET done=? WHERE user_id=? AND id=? AND done=?',
        [to, '{{event.userId}}', _buttonValue, from],
      ),
      ...board(),
    ]);
  }
  click('details', [
    ...findTask(),
    ...card(_taskTitle, '{{steps.task.rows.0.status}}', [
      [
        control('Rename', 'rename', value: _taskId),
        control('Delete…', 'confirm', value: _taskId),
      ],
      [control('Back to tasks', 'back')],
    ], widgetView: 'details'),
  ]);
  click('rename', [
    ...findTask(),
    ...card(
      'Rename task',
      _taskTitle,
      [
        [control('Cancel', 'details', value: _taskId)],
      ],
      mode: 'rename',
      widgetView: 'rename',
      note: 'Send the new name as your next message.',
    ),
    setValue('renameTask', _taskId),
  ]);
  click('confirm', [
    ...findTask(),
    ...card('Delete this task?', _taskTitle, [
      [
        control('Delete task', 'delete', value: _taskId, style: 'danger'),
        control('Cancel', 'details', value: _taskId),
      ],
    ], widgetView: 'delete'),
  ]);
  click('delete', [
    sql('delete_task', 'DELETE FROM tasks WHERE user_id=? AND id=?', [
      '{{event.userId}}',
      _buttonValue,
    ]),
    ...board(),
  ]);
  program.click('task:', [
    answer('old_button', 'Open /tasks to use the current task board.'),
  ], prefix: true);
  program.events.last.config['widgetQueries'] = true;
  program.text([
    say(
      'task_hint',
      'Tap Add task on the board or type /add followed by a task name.',
      only: when('{{user.inputMode}}', 'browse'),
    ),
    check('entering_title', '{{user.inputMode}}', 'browse', 'notEquals'),
    ...saveTitle('{{event.input}}'),
  ]);
  return program.draft;
}
