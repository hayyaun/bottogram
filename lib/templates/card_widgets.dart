// Telegram supplies chat data and the theme. All dynamic values are rendered
// as text and all actions go through the same bot routes as the text views.
const _cardStyle = r'''
<style>
body{margin:0;padding:12px;color:var(--tg-theme-text-color);font:14px system-ui}
main{display:grid;gap:10px}
h2,p{margin:0;overflow-wrap:anywhere}
h2{font-size:20px;line-height:1.25}
small{color:var(--tg-theme-hint-color)}
.grid{display:grid;gap:6px}
.row{display:flex;align-items:center;justify-content:space-between;gap:12px}
.tile,button{padding:9px 11px;border-radius:8px;background:var(--tg-theme-secondary-bg-color)}
button{width:100%;min-height:38px;border:0;text-align:start;color:var(--tg-theme-text-color);font:inherit}
button.primary{background:var(--tg-theme-button-color);color:var(--tg-theme-button-text-color);text-align:center}
button:disabled{opacity:.55}
strong{font-variant-numeric:tabular-nums}
meter{width:100%;height:8px;accent-color:var(--tg-theme-button-color)}
#notice:empty{display:none}
</style>
<main></main><small id="notice" role="status"></small>
<script>
const api = window.TelegramWidget;
const main = document.querySelector('main');
const notice = document.getElementById('notice');
let state;
try { state = JSON.parse(api?.chatData); } catch {}
function el(tag, text, cls) {
  const node = document.createElement(tag);
  if (text != null) node.textContent = String(text);
  if (cls) node.className = cls;
  return node;
}
function action(text, data, cls) {
  const button = el('button', text, cls);
  button.onclick = async () => {
    const buttons = main.querySelectorAll('button:not(:disabled)');
    for (const item of buttons) item.disabled = true;
    notice.textContent = 'Working…';
    try {
      const response = await api.request(data);
      notice.textContent = response?.result || '';
    } catch {
      notice.textContent = 'Could not complete the request. Try again.';
    } finally {
      for (const item of buttons) item.disabled = false;
    }
  };
  return button;
}
''';

const quizQuestionWidget =
    _cardStyle +
    r'''
const item = state?.items?.[0];
if (item) {
  const [id, question, a, b, c] = item;
  const progress = el('meter');
  progress.max = state.total;
  progress.value = state.answered;
  progress.setAttribute('aria-label', 'Questions answered');
  const choices = el('div', null, 'grid');
  [a, b, c].forEach((label, index) => {
    const letter = 'ABC'[index];
    choices.append(action(letter + ' · ' + label, 'quiz:' + letter + ':' + id));
  });
  main.append(el('small', state.topic + ' · Question ' +
    (Number(state.answered) + 1) + ' of ' + state.total), progress,
    el('h2', question), choices, action('Back to topics', 'quiz:home'));
}
api?.ready?.();
</script>
''';

const marketSnapshotWidget =
    _cardStyle +
    r'''
if (state) {
  main.append(el('h2', 'Market snapshot'),
    el('small', 'Top five by market cap · ' + state.currency));
  const quotes = el('div', null, 'grid');
  const number = new Intl.NumberFormat(undefined, {maximumFractionDigits: 8});
  for (const [rank, name, symbol, price] of state.items) {
    const row = el('div', null, 'row tile');
    row.append(el('span', rank + ' · ' + name + ' (' +
      String(symbol).toUpperCase() + ')'),
      el('strong', number.format(price)));
    quotes.append(row);
  }
  main.append(quotes, el('small', 'Source: CoinGecko'),
    action('Refresh prices', 'prices:refresh', 'primary'));
}
api?.ready?.();
</script>
''';
