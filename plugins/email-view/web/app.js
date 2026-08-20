import DOMPurify from 'dompurify';
import {
  Download,
  FileText,
  FileWarning,
  ListCollapse,
  Mail,
  Paperclip,
  createIcons,
} from 'lucide';

createIcons({
  icons: {Download, FileText, FileWarning, ListCollapse, Mail, Paperclip},
});

const elements = {
  viewer: document.getElementById('viewer'),
  loading: document.getElementById('loading'),
  error: document.getElementById('error'),
  errorMessage: document.getElementById('error-message'),
  fileName: document.getElementById('file-name'),
  filePath: document.getElementById('file-path'),
  subject: document.getElementById('subject'),
  date: document.getElementById('date'),
  details: document.getElementById('message-details'),
  detailsButton: document.getElementById('details-button'),
  from: document.getElementById('from'),
  to: document.getElementById('to'),
  cc: document.getElementById('cc'),
  ccLabel: document.getElementById('cc-label'),
  bcc: document.getElementById('bcc'),
  bccLabel: document.getElementById('bcc-label'),
  htmlMode: document.getElementById('html-mode'),
  textMode: document.getElementById('text-mode'),
  bodyStatus: document.getElementById('body-status'),
  bodyFrame: document.getElementById('body-frame'),
  attachments: document.getElementById('attachments'),
  attachmentCount: document.getElementById('attachment-count'),
  attachmentList: document.getElementById('attachment-list'),
};

let email = null;
let mode = 'html';

elements.htmlMode.addEventListener('click', () => setMode('html'));
elements.textMode.addEventListener('click', () => setMode('text'));
elements.detailsButton.addEventListener('click', () => {
  const expanded = elements.detailsButton.getAttribute('aria-pressed') !== 'true';
  elements.detailsButton.setAttribute('aria-pressed', String(expanded));
  elements.details.hidden = !expanded;
});

window.chrome.webview.addEventListener('message', event => {
  if (event.data?.type === 'attachmentSaved') {
    markAttachmentSaved(event.data.id);
    return;
  }
  renderEmail(event.data);
});

window.chrome.webview.postMessage({type: 'ready'});

function renderEmail(data) {
  email = data;
  elements.loading.hidden = true;
  elements.fileName.textContent = data.sourceFileName || 'Email View';
  elements.filePath.textContent = data.sourcePath || '';
  elements.filePath.title = data.sourcePath || '';
  document.title = `${data.subject || data.sourceFileName || 'Email View'} - Email View`;

  if (data.error) {
    elements.errorMessage.textContent = data.error;
    elements.error.hidden = false;
    return;
  }

  elements.subject.textContent = data.subject || '（无主题）';
  elements.from.textContent = formatAddresses(data.from);
  elements.to.textContent = formatAddresses(data.to);
  setOptionalAddress(elements.ccLabel, elements.cc, data.cc);
  setOptionalAddress(elements.bccLabel, elements.bcc, data.bcc);
  setDate(data.date);
  renderAttachments(data.attachments || []);

  elements.htmlMode.disabled = !data.htmlBody;
  elements.textMode.disabled = !data.textBody;
  mode = data.htmlBody ? 'html' : 'text';
  elements.viewer.hidden = false;
  if (!data.htmlBody && !data.textBody) {
    elements.bodyStatus.textContent = '无正文';
    elements.bodyFrame.srcdoc = frameDocument('<p>此邮件没有可显示的正文。</p>');
    return;
  }
  setMode(mode);
}

function setMode(nextMode) {
  if (!email || (nextMode === 'html' && !email.htmlBody) || (nextMode === 'text' && !email.textBody)) {
    return;
  }
  mode = nextMode;
  elements.htmlMode.setAttribute('aria-pressed', String(mode === 'html'));
  elements.textMode.setAttribute('aria-pressed', String(mode === 'text'));
  elements.bodyStatus.textContent = mode === 'html' ? 'HTML 正文' : '纯文本正文';
  renderBody();
}

function renderBody() {
  if (mode === 'text') {
    elements.bodyFrame.srcdoc = frameDocument(`<pre>${escapeHtml(email.textBody || '')}</pre>`);
    return;
  }

  const prepared = prepareHtml(email.htmlBody || '', email.attachments || []);
  elements.bodyFrame.srcdoc = frameDocument(prepared);
  elements.bodyFrame.addEventListener('load', bindFrameLinks, {once: true});
}

function prepareHtml(raw, attachments) {
  const clean = DOMPurify.sanitize(raw, {
    FORBID_TAGS: ['script', 'base', 'form', 'input', 'button', 'textarea', 'select', 'option', 'object', 'embed', 'iframe', 'frame', 'meta'],
    FORBID_ATTR: ['srcset'],
  });
  const parsed = new DOMParser().parseFromString(clean, 'text/html');
  const cidMap = new Map(
    attachments
      .filter(attachment => attachment.contentId)
      .map(attachment => [attachment.contentId.toLowerCase(), attachment.id]),
  );
  for (const image of parsed.querySelectorAll('img[src]')) {
    const source = image.getAttribute('src')?.trim() || '';
    if (source.toLowerCase().startsWith('cid:')) {
      const contentId = decodeCid(source.slice(4));
      const id = cidMap.get(contentId);
      if (id !== undefined) {
        image.setAttribute('src', `https://email-view.local/inline/${encodeURIComponent(id)}`);
      } else {
        image.remove();
      }
      continue;
    }
    if (/^https?:/i.test(source) || source.startsWith('//') || source.startsWith('data:')) {
      continue;
    }
    image.remove();
  }

  for (const link of parsed.querySelectorAll('a[href]')) {
    const href = link.getAttribute('href')?.trim() || '';
    if (!/^(https?:|mailto:)/i.test(href)) {
      link.removeAttribute('href');
    }
  }

  return parsed.body.innerHTML;
}

function frameDocument(body) {
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
  const colors = dark
    ? {background: '#282c34', text: '#e7e9ed', muted: '#a0a7b2', link: '#65a9e6', border: '#414752'}
    : {background: '#ffffff', text: '#20242a', muted: '#69717d', link: '#1769aa', border: '#d9dde3'};
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src http: https: data:; style-src 'unsafe-inline'; font-src http: https: data:"><style>
    html { color-scheme: ${dark ? 'dark' : 'light'}; }
    body { margin: 0; padding: 24px 28px 48px; color: ${colors.text}; background: ${colors.background}; font: 14px/1.62 "Segoe UI", "Microsoft YaHei UI", sans-serif; overflow-wrap: anywhere; }
    img { max-width: 100%; height: auto; }
    table { max-width: 100%; border-collapse: collapse; }
    td, th { border-color: ${colors.border}; }
    a { color: ${colors.link}; cursor: pointer; }
    pre { margin: 0; color: ${colors.text}; background: transparent; font: 13px/1.65 "Cascadia Mono", Consolas, monospace; white-space: pre-wrap; overflow-wrap: anywhere; }
    blockquote { margin-left: 0; padding-left: 16px; color: ${colors.muted}; border-left: 3px solid ${colors.border}; }
  </style></head><body>${body}</body></html>`;
}

function bindFrameLinks() {
  const frameDocument = elements.bodyFrame.contentDocument;
  if (!frameDocument) return;
  frameDocument.addEventListener('click', event => {
    const link = event.target.closest?.('a[href]');
    if (!link) return;
    event.preventDefault();
    window.chrome.webview.postMessage({type: 'openLink', url: link.href});
  });
}

function renderAttachments(attachments) {
  elements.viewer.classList.toggle('has-attachments', attachments.length > 0);
  elements.attachments.hidden = attachments.length === 0;
  elements.attachmentCount.textContent = String(attachments.length);
  elements.attachmentList.replaceChildren();
  for (const attachment of attachments) {
    const row = document.createElement('div');
    row.className = 'attachment-row';
    row.dataset.id = attachment.id;

    const icon = document.createElement('span');
    icon.className = 'attachment-icon';
    icon.innerHTML = '<i data-lucide="file-text" aria-hidden="true"></i>';

    const copy = document.createElement('div');
    copy.className = 'attachment-copy';
    const name = document.createElement('strong');
    name.textContent = attachment.name;
    name.title = attachment.name;
    const meta = document.createElement('span');
    meta.textContent = `${formatBytes(attachment.size)}${attachment.inline ? ' · 内嵌' : ''}`;
    copy.append(name, meta);

    const save = document.createElement('button');
    save.className = 'icon-button';
    save.type = 'button';
    save.title = '保存附件';
    save.setAttribute('aria-label', `保存 ${attachment.name}`);
    save.innerHTML = '<i data-lucide="download" aria-hidden="true"></i>';
    save.addEventListener('click', () => {
      window.chrome.webview.postMessage({type: 'saveAttachment', id: attachment.id});
    });

    row.append(icon, copy, save);
    elements.attachmentList.append(row);
  }
  createIcons({icons: {Download, FileText}});
}

function markAttachmentSaved(id) {
  const row = [...elements.attachmentList.children].find(item => item.dataset.id === id);
  if (!row) return;
  row.classList.add('saved');
  setTimeout(() => row.classList.remove('saved'), 1200);
}

function setOptionalAddress(label, value, addresses) {
  const visible = Array.isArray(addresses) && addresses.length > 0;
  label.hidden = !visible;
  value.hidden = !visible;
  value.textContent = formatAddresses(addresses);
}

function formatAddresses(addresses) {
  if (!Array.isArray(addresses) || addresses.length === 0) return '—';
  return addresses.map(item => item.name && item.address ? `${item.name} <${item.address}>` : item.name || item.address).join('; ');
}

function setDate(value) {
  if (!value) {
    elements.date.textContent = '';
    return;
  }
  const date = new Date(value);
  elements.date.dateTime = value;
  elements.date.textContent = Number.isNaN(date.valueOf()) ? value : new Intl.DateTimeFormat('zh-CN', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

function formatBytes(size) {
  if (!Number.isFinite(size) || size <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  const index = Math.min(Math.floor(Math.log(size) / Math.log(1024)), units.length - 1);
  const value = size / (1024 ** index);
  return `${value.toFixed(index === 0 || value >= 10 ? 0 : 1)} ${units[index]}`;
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);
}

function decodeCid(value) {
  try {
    return decodeURIComponent(value).replace(/^<|>$/g, '').toLowerCase();
  } catch {
    return value.replace(/^<|>$/g, '').toLowerCase();
  }
}
