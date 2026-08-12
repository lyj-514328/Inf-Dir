import {basicSetup, EditorView} from 'codemirror';
import {foldAll, unfoldAll} from '@codemirror/language';
import {languages} from '@codemirror/language-data';
import {gotoLine, openSearchPanel} from '@codemirror/search';
import {Compartment, EditorState} from '@codemirror/state';
import {oneDark} from '@codemirror/theme-one-dark';
import {
  Braces,
  FileCode2,
  FoldVertical,
  ListOrdered,
  Minus,
  Plus,
  RefreshCw,
  Search,
  SunMoon,
  UnfoldVertical,
  WrapText,
  createIcons,
} from 'lucide';

import {decodeText, directoryOf, fileNameOf, formatBytes} from './file_utils.js';

const params = new URLSearchParams(location.search);
const filePath = params.get('path') ?? '';
const fileName = fileNameOf(filePath) || 'Code View';

const elements = {
  editor: document.getElementById('editor'),
  loading: document.getElementById('loading'),
  loadingLabel: document.getElementById('loading-label'),
  fileName: document.getElementById('file-name'),
  filePath: document.getElementById('file-path'),
  searchButton: document.getElementById('search-button'),
  gotoButton: document.getElementById('goto-button'),
  wrapButton: document.getElementById('wrap-button'),
  foldButton: document.getElementById('fold-button'),
  unfoldButton: document.getElementById('unfold-button'),
  reloadButton: document.getElementById('reload-button'),
  languageSelect: document.getElementById('language-select'),
  themeSelect: document.getElementById('theme-select'),
  zoomOutButton: document.getElementById('zoom-out-button'),
  zoomInButton: document.getElementById('zoom-in-button'),
  zoomValue: document.getElementById('zoom-value'),
  cursorStatus: document.getElementById('cursor-status'),
  selectionStatus: document.getElementById('selection-status'),
  languageStatus: document.getElementById('language-status'),
  encodingStatus: document.getElementById('encoding-status'),
  documentStatus: document.getElementById('document-status'),
};

createIcons({
  icons: {
    Braces,
    FileCode2,
    FoldVertical,
    ListOrdered,
    Minus,
    Plus,
    RefreshCw,
    Search,
    SunMoon,
    UnfoldVertical,
    WrapText,
  },
});

elements.fileName.textContent = fileName;
elements.filePath.textContent = directoryOf(filePath);
elements.filePath.title = filePath;
document.title = `${fileName} - Code View`;

const languageCompartment = new Compartment();
const wrapCompartment = new Compartment();
const themeCompartment = new Compartment();
const systemTheme = matchMedia('(prefers-color-scheme: dark)');
const languageByValue = new Map();
let view = null;
let wordWrap = false;
let fontSize = 14;
let languageRequest = 0;
let sourceBytes = 0;

function populateLanguages() {
  const sorted = [...languages].sort((left, right) => left.name.localeCompare(right.name));
  for (const [index, language] of sorted.entries()) {
    const value = `language-${index}`;
    languageByValue.set(value, language);
    const option = document.createElement('option');
    option.value = value;
    option.textContent = language.name;
    elements.languageSelect.append(option);
  }
}

function detectLanguage() {
  const lowerName = fileName.toLowerCase();
  const dot = lowerName.lastIndexOf('.');
  const extension = dot >= 0 ? lowerName.slice(dot + 1) : '';
  return languages.find((language) => {
    if (language.filename?.test(lowerName)) return true;
    return extension && language.extensions?.includes(extension);
  }) ?? null;
}

function selectedLanguage() {
  if (elements.languageSelect.value === 'plain') return null;
  if (elements.languageSelect.value === 'auto') return detectLanguage();
  return languageByValue.get(elements.languageSelect.value) ?? null;
}

async function applyLanguage() {
  if (!view) return;
  const request = ++languageRequest;
  const description = selectedLanguage();
  if (!description) {
    view.dispatch({effects: languageCompartment.reconfigure([])});
    elements.languageStatus.textContent = 'Plain text';
    return;
  }

  elements.languageStatus.textContent = `Loading ${description.name}...`;
  try {
    const support = await description.load();
    if (request !== languageRequest || !view) return;
    view.dispatch({effects: languageCompartment.reconfigure(support)});
    elements.languageStatus.textContent = description.name;
  } catch (error) {
    if (request !== languageRequest) return;
    console.error('[code-view] language load failed:', error);
    view.dispatch({effects: languageCompartment.reconfigure([])});
    elements.languageStatus.textContent = 'Plain text';
  }
}

function effectiveTheme() {
  const selected = elements.themeSelect.value;
  if (selected === 'system') return systemTheme.matches ? 'dark' : 'light';
  return selected;
}

function applyTheme() {
  const theme = effectiveTheme();
  document.documentElement.dataset.theme = theme;
  if (view) {
    view.dispatch({
      effects: themeCompartment.reconfigure(theme === 'dark' ? oneDark : []),
    });
  }
}

function applyWrap() {
  elements.wrapButton.setAttribute('aria-pressed', String(wordWrap));
  if (view) {
    view.dispatch({
      effects: wrapCompartment.reconfigure(wordWrap ? EditorView.lineWrapping : []),
    });
  }
}

function setFontSize(next) {
  fontSize = Math.min(24, Math.max(10, next));
  document.documentElement.style.setProperty('--editor-font-size', `${fontSize}px`);
  elements.zoomValue.textContent = `${Math.round((fontSize / 14) * 100)}%`;
  elements.zoomOutButton.disabled = fontSize <= 10;
  elements.zoomInButton.disabled = fontSize >= 24;
}

function updateSelectionStatus(state) {
  const selection = state.selection.main;
  const line = state.doc.lineAt(selection.head);
  elements.cursorStatus.textContent = `Ln ${line.number}, Col ${selection.head - line.from + 1}`;
  const length = selection.to - selection.from;
  elements.selectionStatus.hidden = length === 0;
  elements.selectionStatus.textContent = length === 0 ? '' : `${length.toLocaleString()} selected`;
}

function createEditor(text) {
  view?.destroy();
  const initialTheme = effectiveTheme();
  view = new EditorView({
    parent: elements.editor,
    doc: text,
    extensions: [
      basicSetup,
      EditorState.readOnly.of(true),
      EditorView.editable.of(false),
      EditorView.contentAttributes.of({tabindex: '0', 'aria-readonly': 'true'}),
      languageCompartment.of([]),
      wrapCompartment.of(wordWrap ? EditorView.lineWrapping : []),
      themeCompartment.of(initialTheme === 'dark' ? oneDark : []),
      EditorView.updateListener.of((update) => {
        if (update.selectionSet || update.docChanged) updateSelectionStatus(update.state);
      }),
    ],
  });
  updateSelectionStatus(view.state);
  applyLanguage();
  view.focus();
}

async function loadFile() {
  elements.loading.classList.remove('hidden', 'error');
  elements.loadingLabel.textContent = 'Opening file...';
  try {
    const response = await fetch(`${location.origin}/file`, {cache: 'no-store'});
    if (!response.ok) throw new Error(await response.text());
    const buffer = await response.arrayBuffer();
    sourceBytes = buffer.byteLength;
    const decoded = decodeText(buffer);
    createEditor(decoded.text);
    elements.encodingStatus.textContent = decoded.encoding;
    elements.documentStatus.textContent =
      `${view.state.doc.lines.toLocaleString()} lines, ${formatBytes(sourceBytes)}`;
    elements.loading.classList.add('hidden');
  } catch (error) {
    console.error('[code-view] file load failed:', error);
    elements.loading.classList.add('error');
    elements.loadingLabel.textContent = error?.message || String(error);
  }
}

elements.searchButton.addEventListener('click', () => {
  if (view) openSearchPanel(view);
});
elements.gotoButton.addEventListener('click', () => {
  if (view) gotoLine(view);
});
elements.wrapButton.addEventListener('click', () => {
  wordWrap = !wordWrap;
  applyWrap();
  view?.focus();
});
elements.foldButton.addEventListener('click', () => {
  if (view) foldAll(view);
});
elements.unfoldButton.addEventListener('click', () => {
  if (view) unfoldAll(view);
});
elements.reloadButton.addEventListener('click', loadFile);
elements.languageSelect.addEventListener('change', applyLanguage);
elements.themeSelect.addEventListener('change', applyTheme);
elements.zoomOutButton.addEventListener('click', () => setFontSize(fontSize - 1));
elements.zoomInButton.addEventListener('click', () => setFontSize(fontSize + 1));
systemTheme.addEventListener('change', () => {
  if (elements.themeSelect.value === 'system') applyTheme();
});

window.addEventListener('keydown', (event) => {
  if (event.altKey && !event.ctrlKey && !event.metaKey && event.key.toLowerCase() === 'z') {
    event.preventDefault();
    wordWrap = !wordWrap;
    applyWrap();
    return;
  }
  if (!(event.ctrlKey || event.metaKey)) return;
  if (event.key === '+' || event.key === '=') {
    event.preventDefault();
    setFontSize(fontSize + 1);
  } else if (event.key === '-') {
    event.preventDefault();
    setFontSize(fontSize - 1);
  } else if (event.key === '0') {
    event.preventDefault();
    setFontSize(14);
  }
});

populateLanguages();
setFontSize(fontSize);
applyTheme();
applyWrap();

if (filePath) {
  loadFile();
} else {
  elements.loading.classList.add('error');
  elements.loadingLabel.textContent = 'Missing file path';
}
