/// Telegram renders this fixed document. The task template supplies private
/// chat data and handles every request with the same actions as the text board.
const taskBoardWidget = r'''
<style>
body{margin:0;padding:12px;color:var(--tg-theme-text-color)}
h2,p{margin:0}
h2{font-size:19px;line-height:1.25;overflow-wrap:anywhere}
p{font-size:14px;line-height:1.4;overflow-wrap:anywhere}
#board,.tasks{display:grid;gap:8px}
.controls{display:flex;gap:6px;flex-wrap:wrap}
.controls button{flex:1;min-height:36px;padding:5px 8px}
button{border:0;border-radius:8px;background:var(--tg-theme-secondary-bg-color);color:var(--tg-theme-text-color)}
button:active{opacity:.75}
button:disabled{opacity:.55}
button.selected,button.primary{background:var(--tg-theme-button-color);color:var(--tg-theme-button-text-color)}
button.selected:disabled{opacity:1}
button.danger{color:var(--tg-theme-destructive-text-color)}
.task{display:grid;gap:6px;padding:7px 0;border-bottom:1px solid var(--tg-theme-section-separator-color)}
.title{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.hint{font-size:13px;color:var(--tg-theme-hint-color)}
#notice:empty{display:none}
</style>
<div id="board"></div>
<p id="notice" class="hint"></p>
<script>
const widget = window.TelegramWidget;
const board = document.getElementById('board');
const notice = document.getElementById('notice');
let pending;
let timeout;

function element(tag, text, style) {
  const node = document.createElement(tag);
  if (text) node.textContent = text;
  if (style) node.className = style;
  return node;
}
function draw() {
  let state;
  try { state = JSON.parse(widget?.chatData); } catch {}
  if (!state || state.r == null) {
    board.replaceChildren(element('p', 'Open /tasks in the bot chat.'));
    return;
  }
  function button(label, action, value, style, selected = false) {
    const item = element('button', label, style);
    item.disabled = !!pending || selected;
    item.addEventListener('click', () => {
      if (pending) return;
      const data = ['task', action, state.r, ...(value == null ? [] : [value])].join(':');
      const request = widget.request(data);
      pending = request;
      notice.textContent = 'Updating…';
      draw();
      request.then(({result}) => {
        if (pending !== request) return;
        if (result) {
          finish(result);
        } else {
          timeout = setTimeout(() => finish('Open /tasks if the board did not update.'), 5000);
        }
      }, () => {
        if (pending === request) finish('Could not update. Try again or open /tasks.');
      });
    });
    return item;
  }
  function controls(...buttons) {
    const group = element('div', '', 'controls');
    group.append(...buttons);
    return group;
  }

  if (state.v === 'board') {
    const tasks = element('div', '', 'tasks');
    for (const [id, title] of state.l) {
      const task = element('div', '', 'task');
      task.append(element('p', title, 'title'), controls(
        button(state.t === 1 ? 'Reopen' : 'Complete', state.t === 1 ? 'reopen' : 'complete', id),
        button('Details', 'details', id)
      ));
      tasks.append(task);
    }
    if (!state.l.length) {
      tasks.append(element('p', state.t === 1 ? 'Completed tasks will appear here.' : 'No open tasks. Add one to get started.', 'hint'));
    }
    const pagination = [];
    if (state.p > 0) pagination.push(button('‹ Previous', 'page', state.p - 1));
    if (state.p + 1 < state.n) pagination.push(button('Next ›', 'page', state.p + 1));
    board.replaceChildren(
      element('h2', state.h),
      controls(button('Open · ' + state.a, 'open', null, state.t === 0 ? 'selected' : '', state.t === 0),
               button('Completed · ' + state.d, 'completed', null, state.t === 1 ? 'selected' : '', state.t === 1)),
      tasks,
      ...(state.n > 1 ? [element('p', 'Page ' + (state.p + 1) + ' of ' + state.n, 'hint')] : []),
      ...(pagination.length ? [controls(...pagination)] : []),
      controls(button('+ Add task', 'add', null, 'primary'))
    );
  } else if (state.v === 'details') {
    board.replaceChildren(element('h2', state.h), element('p', state.status, 'hint'),
      controls(button('Rename', 'rename', state.i), button('Delete…', 'confirm', state.i, 'danger')),
      controls(button('Back to tasks', 'back')));
  } else if (state.v === 'delete') {
    board.replaceChildren(element('h2', 'Delete this task?'), element('p', state.h),
      controls(button('Cancel', 'details', state.i), button('Delete task', 'delete', state.i, 'danger')));
  } else {
    const rename = state.v === 'rename';
    board.replaceChildren(element('h2', rename ? 'Rename task' : 'Add a task'),
      ...(rename ? [element('p', state.h)] : []),
      element('p', rename ? 'Send the new name in this chat.' : 'Send the task name in this chat.', 'hint'),
      controls(button('Cancel', rename ? 'details' : 'back', state.i)));
  }
}
function finish(text = '') {
  clearTimeout(timeout);
  pending = undefined;
  notice.textContent = text;
  draw();
}
widget?.onEvent('chatDataChanged', () => finish());
draw();
widget?.ready?.();
</script>
''';
