const statusEl = document.getElementById('status');
const contentEl = document.getElementById('content');
const params = new URLSearchParams(location.search);

function ipc(msg) {
  try {
    window.ipc?.postMessage(JSON.stringify(msg));
  } catch (err) {
    console.error('[markdown-view] ipc failed:', err);
  }
}

/* ---------- markdown-it + GFM 任务列表 ---------- */

function taskListsPlugin(md) {
  const CHECKBOX = /^\[( |x|X)\][ \u00A0]/;
  md.core.ruler.after('inline', 'gfm-task-lists', (state) => {
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'list_item_open') continue;
      const inline = tokens[i + 1];
      if (!inline || inline.type !== 'inline') continue;
      const children = inline.children;
      if (!children || !children.length || children[0].type !== 'text') continue;
      const m = CHECKBOX.exec(children[0].content);
      if (!m) continue;
      const checked = m[1].toLowerCase() === 'x';
      children[0].content = children[0].content.slice(m[0].length);
      const box = new state.Token('html_inline', '', 0);
      box.content =
        `<input type="checkbox" class="task-list-item-checkbox" disabled${checked ? ' checked' : ''}> `;
      children.unshift(box);
      tokens[i].attrJoin('class', 'task-list-item');
      for (let j = i - 1; j >= 0; j--) {
        const t = tokens[j];
        if (
          (t.type === 'bullet_list_open' || t.type === 'ordered_list_open') &&
          t.level === tokens[i].level - 1
        ) {
          t.attrJoin('class', 'contains-task-list');
          break;
        }
      }
    }
  });
}

const md = window.markdownit({
  html: false,
  linkify: true,
  highlight(str, lang) {
    if (lang && window.hljs && window.hljs.getLanguage(lang)) {
      try {
        const value = window.hljs.highlight(str, { language: lang, ignoreIllegals: true }).value;
        return `<pre class="hljs"><code>${value}</code></pre>`;
      } catch {
        /* 回退默认转义 */
      }
    }
    return '';
  },
});
md.use(taskListsPlugin);

/* ---------- Windows 路径工具 ---------- */

function dirOf(path) {
  const i = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return i > 0 ? path.slice(0, i) : '';
}

function fileNameOf(path) {
  const i = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return i >= 0 ? path.slice(i + 1) : path;
}

function isAbsolute(p) {
  return /^[a-zA-Z]:[\\/]/.test(p) || /^[\\/]{2}/.test(p);
}

function normalizePath(p) {
  const unc = /^[\\/]{2}/.test(p);
  const out = [];
  for (const seg of p.split(/[\\/]+/)) {
    if (!seg || seg === '.') continue;
    if (seg === '..') {
      if (out.length && !/^[a-zA-Z]:$/.test(out[out.length - 1])) out.pop();
      continue;
    }
    out.push(seg);
  }
  let joined = out.join('\\');
  if (unc) joined = `\\\\${joined}`;
  return joined;
}

/// 把 href/src 解析为 Windows 绝对路径；外部协议返回 null
function resolveRelative(docPath, rel) {
  rel = rel.split(/[?#]/)[0];
  if (!rel) return null;
  if (/^(https?|mailto|data|file|javascript):/i.test(rel)) return null;
  try {
    rel = decodeURI(rel);
  } catch {
    /* 保留原样 */
  }
  if (isAbsolute(rel)) return normalizePath(rel);
  return normalizePath(`${dirOf(docPath)}\\${rel}`);
}

/* ---------- GFM Alerts ---------- */

const ALERT_RE = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(\r?\n)?/;

function renderAlerts(root) {
  for (const bq of root.querySelectorAll('blockquote')) {
    const firstP = bq.querySelector(':scope > p');
    if (!firstP) continue;
    const walker = document.createTreeWalker(firstP, NodeFilter.SHOW_TEXT);
    const node = walker.nextNode();
    if (!node) continue;
    const m = ALERT_RE.exec(node.textContent);
    if (!m) continue;
    node.textContent = node.textContent.slice(m[0].length);
    const type = m[1].toLowerCase();
    bq.classList.add('markdown-alert', `markdown-alert-${type}`);
    const title = document.createElement('p');
    title.className = 'markdown-alert-title';
    title.textContent = m[1][0] + m[1].slice(1).toLowerCase();
    bq.insertBefore(title, firstP);
    if (!node.textContent.trim() && firstP.childNodes.length === 1) firstP.remove();
  }
}

/* ---------- KaTeX 数学公式 ---------- */

function renderMath(root) {
  if (typeof window.renderMathInElement !== 'function') return;
  window.renderMathInElement(root, {
    delimiters: [
      { left: '$$', right: '$$', display: true },
      { left: '$', right: '$', display: false },
    ],
    throwOnError: false,
  });
}

/* ---------- mermaid（懒加载） ---------- */

let mermaidLoader = null;

async function renderMermaid(root) {
  const codes = [...root.querySelectorAll('code.language-mermaid')];
  if (!codes.length) return;
  for (const code of codes) {
    const div = document.createElement('div');
    div.className = 'mermaid';
    div.textContent = code.textContent;
    (code.closest('pre') || code).replaceWith(div);
  }
  mermaidLoader ??= new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = './mermaid.min.js';
    s.onload = () => resolve(window.mermaid);
    s.onerror = () => reject(new Error('mermaid.min.js 加载失败'));
    document.head.appendChild(s);
  });
  let mermaid;
  try {
    mermaid = await mermaidLoader;
  } catch (err) {
    console.error('[markdown-view]', err.message);
    return;
  }
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: dark ? 'dark' : 'default',
  });
  try {
    await mermaid.run({ querySelector: '.mermaid' });
  } catch (err) {
    console.error('[markdown-view] mermaid 渲染失败:', err);
  }
}

/* ---------- 图片与链接 ---------- */

function fixImages(root, docPath) {
  for (const img of root.querySelectorAll('img')) {
    const resolved = resolveRelative(docPath, img.getAttribute('src') ?? '');
    if (resolved) {
      img.src = `${location.origin}/file?path=${encodeURIComponent(resolved)}`;
    }
  }
}

const MD_EXT = /\.(md|markdown|mdown|mkd)$/i;

contentEl.addEventListener('click', (e) => {
  const a = e.target.closest('a');
  if (!a) return;
  const href = a.getAttribute('href') ?? '';
  if (!href || href.startsWith('#')) return;
  e.preventDefault();
  if (/^(https?:|mailto:)/i.test(href)) {
    ipc({ kind: 'open-url', url: href });
    return;
  }
  const resolved = resolveRelative(currentPath, href);
  if (!resolved) return;
  if (MD_EXT.test(resolved)) {
    navigateTo(resolved);
  } else {
    ipc({ kind: 'open', path: resolved });
  }
});

/* ---------- 加载与导航 ---------- */

let currentPath = '';
const history = [];

async function renderFile(path) {
  currentPath = path;
  document.title = `${fileNameOf(path)} - Markdown 查看器`;
  statusEl.classList.remove('hidden', 'error');
  statusEl.textContent = '加载中…';
  try {
    const resp = await fetch(`${location.origin}/file?path=${encodeURIComponent(path)}`);
    if (!resp.ok) throw new Error(await resp.text());
    const text = new TextDecoder('utf-8').decode(await resp.arrayBuffer());
    contentEl.innerHTML = md.render(text);
    fixImages(contentEl, path);
    renderAlerts(contentEl);
    renderMath(contentEl);
    await renderMermaid(contentEl);
    statusEl.classList.add('hidden');
    window.scrollTo({ top: 0 });
  } catch (err) {
    statusEl.textContent = `无法打开 ${fileNameOf(path)}\n${err && err.message ? err.message : err}`;
    statusEl.classList.add('error');
  }
}

function navigateTo(path) {
  history.push(currentPath);
  renderFile(path);
}

window.addEventListener('keydown', (e) => {
  if (e.altKey && e.key === 'ArrowLeft' && history.length) {
    renderFile(history.pop());
  }
});

const initial = params.get('path') ?? '';
if (initial) {
  renderFile(initial);
} else {
  statusEl.textContent = '缺少 path 参数';
  statusEl.classList.add('error');
}
