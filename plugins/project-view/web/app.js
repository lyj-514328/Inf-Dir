const state = {
  project: null,
  tasks: [],
  taskById: new Map(),
  selectedId: null,
  query: '',
  scale: 'week',
  gantt: null,
  ganttReady: false,
};

const elements = {
  title: document.getElementById('project-title'),
  file: document.getElementById('project-file'),
  scale: document.getElementById('scale-select'),
  fit: document.getElementById('fit-button'),
  search: document.getElementById('search-input'),
  ganttPanel: document.getElementById('gantt-panel'),
  ganttChart: document.getElementById('gantt-chart'),
  errorPanel: document.getElementById('error-panel'),
  errorTitle: document.getElementById('error-title'),
  errorMessage: document.getElementById('error-message'),
  loading: document.getElementById('loading-panel'),
  loadingMessage: document.getElementById('loading-message'),
  taskStatus: document.getElementById('task-status'),
  selectionStatus: document.getElementById('selection-status'),
};

function escapeLabel(value) {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[character]));
}

function dateValue(value) {
  if (!value) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function formatDate(value) {
  const timestamp = dateValue(value);
  if (timestamp === null) return 'No date';
  return new Intl.DateTimeFormat(undefined, {year: 'numeric', month: 'short', day: 'numeric'}).format(timestamp);
}

function formatPercent(value) {
  return `${Math.round(Number(value) || 0)}%`;
}

function normalizeTasks(rawTasks) {
  const tasks = rawTasks.map((task, index) => ({
    ...task,
    id: String(task.id || task.uid || index + 1),
    uid: String(task.uid || task.id || index + 1),
    parentId: task.parentId == null || task.parentId === '' ? null : String(task.parentId),
    outlineLevel: Number(task.outlineLevel) || 1,
    percentComplete: Math.max(0, Math.min(100, Number(task.percentComplete) || 0)),
    predecessors: Array.isArray(task.predecessors) ? task.predecessors : [],
  }));
  const taskById = new Map(tasks.map((task) => [task.uid, task]));
  const ranges = new Map();
  for (const task of tasks) {
    const start = dateValue(task.start);
    const finish = dateValue(task.finish) ?? start;
    if (start !== null) ranges.set(task.uid, {start, finish: finish ?? start});
  }
  for (let index = tasks.length - 1; index >= 0; index -= 1) {
    const task = tasks[index];
    if (!task.parentId) continue;
    const own = ranges.get(task.uid);
    if (!own) continue;
    const parent = ranges.get(task.parentId);
    ranges.set(task.parentId, parent
      ? {start: Math.min(parent.start, own.start), finish: Math.max(parent.finish, own.finish)}
      : own);
  }
  for (const task of tasks) {
    const range = ranges.get(task.uid);
    if (!task.start && range) task.start = new Date(range.start).toISOString();
    if (!task.finish && range) task.finish = new Date(range.finish).toISOString();
  }
  state.taskById = taskById;
  return tasks;
}

function visibleTasks() {
  if (!state.query) return state.tasks;
  const matches = state.tasks.filter((task) => task.name.toLowerCase().includes(state.query));
  if (matches.length === 0) return [];
  const visible = new Map(matches.map((task) => [task.uid, task]));
  for (const task of matches) {
    let parentId = task.parentId;
    while (parentId) {
      const parent = state.taskById.get(parentId);
      if (!parent) break;
      visible.set(parent.uid, parent);
      parentId = parent.parentId;
    }
  }
  return state.tasks.filter((task) => visible.has(task.uid));
}

function chartColors() {
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
  return {
    text: dark ? '#e7e9ed' : '#20242a',
    muted: dark ? '#9aa4b2' : '#68727f',
    grid: dark ? '#343b46' : '#e1e5ea',
    bar: dark ? '#5e9ee6' : '#3683d8',
    summary: dark ? '#8c98a8' : '#596576',
    progress: dark ? '#b8d8ff' : '#125ba8',
    selected: dark ? '#f3c969' : '#b56c00',
    background: dark ? '#1d2128' : '#ffffff',
  };
}

function syncTheme() {
  document.documentElement.dataset.theme = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function ganttDate(value) {
  if (!value || dateValue(value) === null) return null;
  const match = String(value).match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (match) return `${match[1]}-${match[2]}-${match[3]}`;
  const date = new Date(dateValue(value));
  const pad = (part) => String(part).padStart(2, '0');
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

function ganttTaskId(task) {
  return `task-${String(task.uid).replace(/[^a-zA-Z0-9_-]+/g, '_')}`;
}

function taskDuration(task) {
  if (task.milestone) return 0;
  const start = dateValue(task.start);
  const finish = dateValue(task.finish) ?? start;
  if (start === null || finish === null) return 1;
  return Math.max(1, Math.ceil((finish - start) / 86400000));
}

function dependencySourceId(predecessor) {
  return predecessor && typeof predecessor === 'object'
    ? predecessor.taskId ?? predecessor.id ?? predecessor.uid
    : predecessor;
}

function dependencyType(value) {
  const type = String(value || '').toUpperCase();
  if (type.includes('SS')) return '1';
  if (type.includes('FF')) return '2';
  if (type.includes('SF')) return '3';
  return '0';
}

function toDhtmlxData(rows) {
  const idBySource = new Map();
  for (const task of rows) {
    const id = ganttTaskId(task);
    idBySource.set(String(task.uid), id);
  }
  for (const task of rows) {
    const id = ganttTaskId(task);
    if (!idBySource.has(String(task.id))) idBySource.set(String(task.id), id);
  }
  const data = rows.map((task) => {
    const start = ganttDate(task.start);
    if (!start) return null;
    const parent = task.parentId ? idBySource.get(String(task.parentId)) || 0 : 0;
    return {
      id: ganttTaskId(task),
      uid: task.uid,
      text: task.name,
      start_date: start,
      duration: taskDuration(task),
      progress: task.percentComplete / 100,
      parent,
      type: task.milestone ? 'milestone' : (task.summary ? 'project' : 'task'),
      open: true,
      projectTaskSummary: Boolean(task.summary),
      projectTaskMilestone: Boolean(task.milestone),
      sourceStart: task.start,
      sourceFinish: task.finish,
      sourcePercent: task.percentComplete,
    };
  }).filter(Boolean);
  const links = [];
  for (const task of rows) {
    const target = idBySource.get(String(task.uid));
    if (!target) continue;
    task.predecessors.forEach((predecessor, index) => {
      const source = idBySource.get(String(dependencySourceId(predecessor)));
      if (!source || source === target) return;
      links.push({
        id: `link-${target}-${index}`,
        source,
        target,
        type: dependencyType(predecessor?.type),
      });
    });
  }
  return {data, links};
}

function ganttScaleConfig() {
  if (state.scale === 'day') {
    return {scales: [{unit: 'day', step: 1, format: '%d %M'}]};
  }
  if (state.scale === 'month') {
    return {scales: [
      {unit: 'month', step: 1, format: '%F %Y'},
      {unit: 'week', step: 1, format: 'W%W'},
    ]};
  }
  return {scales: [
    {unit: 'week', step: 1, format: 'Week %W'},
    {unit: 'day', step: 1, format: '%D'},
  ]};
}

function configureGantt() {
  const gantt = window.dhtmlxgantt?.gantt || window.gantt;
  if (!gantt) return null;
  const colors = chartColors();
  const scale = ganttScaleConfig();
  gantt.config.date_format = '%Y-%m-%d';
  gantt.config.readonly = true;
  gantt.config.select_task = true;
  gantt.config.drag_move = false;
  gantt.config.drag_resize = false;
  gantt.config.drag_progress = false;
  gantt.config.details_on_dblclick = false;
  gantt.config.dblclick_create = false;
  gantt.config.show_progress = true;
  gantt.config.show_links = true;
  gantt.config.preserve_scroll = true;
  gantt.config.row_height = 32;
  gantt.config.bar_height = 20;
  gantt.config.scale_height = 42;
  gantt.config.min_column_width = state.scale === 'month' ? 90 : 70;
  gantt.config.scales = scale.scales;
  gantt.templates.task_class = (start, end, task) => [
    task.projectTaskSummary ? 'project-task-summary' : '',
    task.projectTaskMilestone ? 'project-task-milestone' : '',
  ].filter(Boolean).join(' ');
  gantt.templates.tooltip_text = (start, end, task) => {
    const source = task.uid ? state.taskById.get(String(task.uid)) : null;
    if (!source) return escapeLabel(task.text);
    return `<b>${escapeLabel(source.name)}</b><br>${escapeLabel(formatDate(source.start))} - ${escapeLabel(formatDate(source.finish))}<br>${escapeLabel(formatPercent(source.percentComplete))} complete`;
  };
  if (!state.ganttReady) {
    gantt.config.grid_width = 310;
    gantt.config.keep_grid_width = true;
    gantt.config.columns = [
      {name: 'text', label: 'Task', tree: true, width: '*'},
      {name: 'start_date', label: 'Start', align: 'center', width: 92},
      {name: 'duration', label: 'Days', align: 'center', width: 58},
    ];
    gantt.plugins({tooltip: true});
    gantt.attachEvent('onTaskClick', (id) => {
      const task = gantt.getTask(id);
      if (task) selectTask(task.uid || id);
      return true;
    });
    gantt.init(elements.ganttChart);
    state.ganttReady = true;
    state.gantt = gantt;
  }
  elements.ganttChart.style.setProperty('--project-bar-color', colors.bar);
  elements.ganttChart.style.setProperty('--project-summary-color', colors.summary);
  elements.ganttChart.style.setProperty('--project-progress-color', colors.progress);
  elements.ganttChart.style.setProperty('--project-selected-color', colors.selected);
  elements.ganttChart.style.setProperty('--project-grid-color', colors.grid);
  elements.ganttChart.style.setProperty('--project-text-color', colors.text);
  elements.ganttChart.style.setProperty('--project-muted-color', colors.muted);
  return gantt;
}

function renderGantt() {
  const gantt = configureGantt();
  if (!gantt) return;
  const scroll = typeof gantt.getScrollState === 'function' ? gantt.getScrollState() : null;
  const rows = visibleTasks();
  const data = toDhtmlxData(rows);
  gantt.config.scales = ganttScaleConfig().scales;
  gantt.config.min_column_width = state.scale === 'month' ? 90 : 70;
  gantt.clearAll();
  gantt.parse(data);
  gantt.render();
  if (state.selectedId) {
    const selectedId = ganttTaskId({uid: state.selectedId});
    if (gantt.isTaskExists(selectedId)) gantt.selectTask(selectedId);
  }
  if (scroll && typeof gantt.scrollTo === 'function') {
    requestAnimationFrame(() => gantt.scrollTo(scroll.x, scroll.y));
  }
}

function selectTask(id) {
  const previousId = state.selectedId;
  state.selectedId = String(id);
  const task = state.taskById.get(state.selectedId);
  elements.selectionStatus.textContent = task ? `${task.name} - ${formatPercent(task.percentComplete)}` : 'No task selected';
  const gantt = state.gantt;
  if (!gantt || !state.ganttReady || state.query) {
    renderGantt();
    return;
  }
  const taskId = ganttTaskId({uid: state.selectedId});
  if (typeof gantt.unselectTask === 'function' && previousId !== state.selectedId) gantt.unselectTask();
  if (gantt.isTaskExists(taskId)) {
    gantt.selectTask(taskId);
  }
}

function fitGantt() {
  if (!state.gantt) return;
  const minDate = state.gantt.getState().min_date;
  if (minDate) state.gantt.showDate(minDate);
}

async function loadProject() {
  for (;;) {
    try {
      const response = await fetch('/api/project', {cache: 'no-store'});
      const payload = await response.json();
      if (response.status === 202 || payload.status === 'loading') {
        await new Promise((resolve) => setTimeout(resolve, 120));
        continue;
      }
      if (!response.ok || payload.status === 'error') throw new Error(payload.message || 'Project parser failed');
      state.project = payload;
      state.tasks = normalizeTasks(Array.isArray(payload.tasks) ? payload.tasks : []);
      elements.title.textContent = payload.title || 'Project View';
      elements.file.textContent = payload.fileName || '';
      elements.taskStatus.textContent = `${state.tasks.length.toLocaleString()} tasks`;
      elements.loading.classList.add('hidden');
      renderGantt();
      return;
    } catch (error) {
      elements.loading.classList.add('hidden');
      elements.errorPanel.classList.remove('hidden');
      elements.errorTitle.textContent = 'Unable to open project';
      elements.errorMessage.textContent = error?.message || String(error);
      return;
    }
  }
}

elements.scale.addEventListener('change', () => { state.scale = elements.scale.value; renderGantt(); });
elements.fit.addEventListener('click', fitGantt);
elements.search.addEventListener('input', () => {
  state.query = elements.search.value.trim().toLowerCase();
  renderGantt();
});
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { syncTheme(); renderGantt(); });

const ganttAvailable = Boolean(window.dhtmlxgantt?.gantt || window.gantt);
if (!ganttAvailable) {
  elements.loading.classList.add('hidden');
  elements.errorPanel.classList.remove('hidden');
  elements.errorMessage.textContent = 'dhtmlxGantt assets are missing from the plugin package.';
} else {
  syncTheme();
  loadProject();
}
