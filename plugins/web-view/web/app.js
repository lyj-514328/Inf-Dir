const params = new URLSearchParams(location.search);
const filePath = params.get('path') || '';
const documentUrl = params.get('document') || '';
const fileName = filePath.split(/[\\/]/).pop() || '网页查看器';
const frame = document.getElementById('document');
const error = document.getElementById('error');
document.getElementById('file-name').textContent = fileName;
document.getElementById('file-path').textContent = filePath;
document.title = `${fileName} - 网页查看器`;

function showError(message) {
  frame.hidden = true;
  error.hidden = false;
  error.textContent = message;
}

function extension(name) {
  const match = /\.([^.]+)$/.exec(name.toLowerCase());
  return match ? match[1] : '';
}

function fromBase64(value) {
  const binary = atob(value.replace(/\s+/g, ''));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeQuotedPrintable(value) {
  const normalized = value.replace(/=\r?\n/g, '');
  const bytes = [];
  for (let i = 0; i < normalized.length; i++) {
    if (normalized[i] === '=' && /^[0-9a-f]{2}$/i.test(normalized.slice(i + 1, i + 3))) {
      bytes.push(parseInt(normalized.slice(i + 1, i + 3), 16));
      i += 2;
    } else {
      bytes.push(normalized.charCodeAt(i) & 0xff);
    }
  }
  return new Uint8Array(bytes);
}

function parseHeaders(value) {
  const headers = new Map();
  let current = '';
  for (const line of value.split(/\r?\n/)) {
    if (/^[ \t]/.test(line) && current) {
      headers.set(current, `${headers.get(current) || ''} ${line.trim()}`);
      continue;
    }
    const index = line.indexOf(':');
    if (index < 0) continue;
    current = line.slice(0, index).trim().toLowerCase();
    headers.set(current, line.slice(index + 1).trim());
  }
  return headers;
}

function headerParameter(value, name) {
  const match = new RegExp(`${name}\\s*=\\s*(?:"([^"]+)"|([^;\\s]+))`, 'i').exec(value || '');
  return match ? (match[1] || match[2]) : '';
}

function decodeText(bytes, contentType) {
  const charset = headerParameter(contentType, 'charset') || 'utf-8';
  try { return new TextDecoder(charset).decode(bytes); } catch { return new TextDecoder('utf-8').decode(bytes); }
}

function decodePart(body, encoding) {
  if (/base64/i.test(encoding || '')) return fromBase64(body);
  if (/quoted-printable/i.test(encoding || '')) return decodeQuotedPrintable(body);
  const bytes = new Uint8Array(body.length);
  for (let i = 0; i < body.length; i++) bytes[i] = body.charCodeAt(i) & 0xff;
  return bytes;
}

function normalLocation(value) {
  try { return new URL(value || '', 'http://mhtml.local/').href; } catch { return value || ''; }
}

function resolvedResource(value, base, resources) {
  try { return resources.get(normalLocation(new URL(value, base).href)); } catch { return null; }
}

function rewriteMhtmlHtml(html, htmlLocation, resources) {
  const root = new DOMParser().parseFromString(html, 'text/html');
  root.querySelectorAll('script, object, embed, iframe, form, base').forEach((node) => node.remove());
  for (const element of root.querySelectorAll('[src], [href], [srcset], [style]')) {
    for (const attribute of ['src', 'href']) {
      const value = element.getAttribute(attribute);
      if (!value || /^(data:|https?:|mailto:|#)/i.test(value)) continue;
      const resolved = resolvedResource(value, htmlLocation, resources);
      if (resolved) element.setAttribute(attribute, resolved);
      else if (attribute === 'src') element.removeAttribute(attribute);
    }
    const srcset = element.getAttribute('srcset');
    if (srcset) {
      const rewritten = srcset.split(',').map((item) => {
        const [value, descriptor] = item.trim().split(/\s+/, 2);
        const resolved = resolvedResource(value, htmlLocation, resources);
        return resolved ? `${resolved}${descriptor ? ` ${descriptor}` : ''}` : '';
      }).filter(Boolean).join(', ');
      if (rewritten) element.setAttribute('srcset', rewritten); else element.removeAttribute('srcset');
    }
    const style = element.getAttribute('style');
    if (style) element.setAttribute('style', style.replace(/url\((['"]?)([^)'" ]+)\1\)/gi, (match, quote, value) => {
      if (/^(data:|https?:|#)/i.test(value)) return match;
      const resolved = resolvedResource(value, htmlLocation, resources);
      return resolved ? `url(${quote}${resolved}${quote})` : 'none';
    }));
  }
  return `<!doctype html>${root.documentElement.outerHTML}`;
}

async function renderMhtml() {
  const response = await fetch(`${location.origin}/file`, { cache: 'no-store' });
  if (!response.ok) throw new Error(await response.text());
  const bytes = new Uint8Array(await response.arrayBuffer());
  const raw = new TextDecoder('iso-8859-1').decode(bytes);
  const split = raw.indexOf('\r\n\r\n') >= 0 ? raw.indexOf('\r\n\r\n') : raw.indexOf('\n\n');
  if (split < 0) throw new Error('MHTML headers are invalid');
  const headerLength = raw.startsWith('\r\n', split) ? 4 : 2;
  const headers = parseHeaders(raw.slice(0, split));
  const boundary = headerParameter(headers.get('content-type'), 'boundary');
  if (!boundary) throw new Error('MHTML boundary is missing');
  const resources = new Map();
  let htmlPart = null;
  const marker = `--${boundary}`;
  for (const part of raw.slice(split + headerLength).split(marker)) {
    if (!part || part.startsWith('--')) continue;
    const partSplit = part.indexOf('\r\n\r\n') >= 0 ? part.indexOf('\r\n\r\n') : part.indexOf('\n\n');
    if (partSplit < 0) continue;
    const partHeaders = parseHeaders(part.slice(0, partSplit));
    const body = part.slice(partSplit + (part.includes('\r\n\r\n') ? 4 : 2)).replace(/\r?\n$/, '');
    const data = decodePart(body, partHeaders.get('content-transfer-encoding'));
    const type = partHeaders.get('content-type') || 'application/octet-stream';
    const location = partHeaders.get('content-location') || partHeaders.get('content-id')?.replace(/[<>]/g, '');
    if (location) resources.set(normalLocation(location), URL.createObjectURL(new Blob([data], { type: type.split(';')[0] })));
    if (!htmlPart && /^text\/html/i.test(type)) htmlPart = { data, location: normalLocation(location || 'index.html'), type };
  }
  if (!htmlPart) throw new Error('MHTML does not contain an HTML part');
  frame.srcdoc = rewriteMhtmlHtml(decodeText(htmlPart.data, htmlPart.type), htmlPart.location, resources);
}

async function open() {
  if (!documentUrl) throw new Error('document path is missing');
  if (/\.(mht|mhtml)$/i.test(filePath)) await renderMhtml();
  else frame.src = documentUrl;
}

document.getElementById('reload').addEventListener('click', () => {
  frame.src = '';
  open().catch((error) => showError(error?.message || String(error)));
});
open().catch((error) => showError(error?.message || String(error)));

export { decodeQuotedPrintable, parseHeaders };
