const state = {
  project: null,
  tasks: [],
  taskById: new Map(),
  selectedId: null,
  collapsed: new Set(),
  query: '',
  scale: 'week',
  gantt: null,
  wbs: null,
};

const elements = {
  title: document.getElementById('project-title'),
  file: document.getElementById('project-file'),
  view: document.getElementById('view-select'),
  scale: document.getElementById('scale-select'),
  fit: document.getElementById('fit-button'),
  collapse: document.getElementById('collapse-button'),
  search: document.getElementById('search-input'),
  ganttPanel: document.getElementById('gantt-panel'),
  wbsPanel: document.getElementById('wbs-panel'),
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

function childrenOf(parentId) {
  return state.tasks.filter((task) => task.parentId === parentId);
}

function visibleTasks() {
  const result = [];
  const visit = (parentId) => {
    for (const task of state.tasks) {
      if (task.parentId !== parentId) continue;
      if (state.query && !task.name.toLowerCase().includes(state.query)) continue;
      result.push(task);
      if (!state.collapsed.has(task.uid)) visit(task.uid);
    }
  };
  visit(null);
  if (result.length === 0 && state.query) {
    return state.tasks.filter((task) => task.name.toLowerCase().includes(state.query));
  }
  return result;
}

function taskTree() {
  const makeNode = (task) => ({
    name: task.name,
    value: task.uid,
    task,
    children: state.collapsed.has(task.uid) ? [] : childrenOf(task.uid).map(makeNode),
  });
  const roots = state.tasks.filter((task) => !task.parentId).map(makeNode);
  return {name: state.project?.title || 'Project', value: 'root', children: roots};
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

function renderGantt() {
  if (!window.echarts) return;
  const colors = chartColors();
  const rows = visibleTasks();
  const categories = rows.map((task) => task.name);
  const data = rows.map((task, index) => [index, dateValue(task.start), dateValue(task.finish), task.percentComplete, task.summary, task.milestone, task.uid]);
  const scaleInterval = {day: 86400000, week: 7 * 86400000, month: 30 * 86400000}[state.scale] || 7 * 86400000;
  const scaleFormat = state.scale === 'month'
    ? {year: 'numeric', month: 'short'}
    : state.scale === 'day'
      ? {month: 'short', day: 'numeric'}
      : {month: 'short', day: 'numeric'};
  const option = {
    animation: false,
    backgroundColor: colors.background,
    grid: {left: 220, right: 28, top: 44, bottom: 42},
    tooltip: {
      trigger: 'item',
      formatter: (params) => {
        const task = state.taskById.get(params.value?.[6]);
        if (!task) return '';
        return `<strong>${escapeLabel(task.name)}</strong><br>${formatDate(task.start)} - ${formatDate(task.finish)}<br>${formatPercent(task.percentComplete)} complete`;
      },
    },
    xAxis: {
      type: 'time',
      minInterval: scaleInterval,
      axisLabel: {color: colors.muted, formatter: (value) => new Intl.DateTimeFormat(undefined, scaleFormat).format(value)},
      axisLine: {lineStyle: {color: colors.grid}},
      splitLine: {show: true, lineStyle: {color: colors.grid}},
      min: (value) => value.min - 86400000 * 2,
      max: (value) => value.max + 86400000 * 2,
      axisPointer: {snap: true},
    },
    yAxis: {
      type: 'category',
      inverse: true,
      data: categories,
      axisLabel: {
        color: colors.text,
        width: 200,
        overflow: 'truncate',
        formatter: (value, index) => {
          const task = rows[index];
          return `${'  '.repeat(Math.max(0, task.outlineLevel - 1))}${task.summary ? '▰ ' : ''}${value}`;
        },
      },
      axisLine: {lineStyle: {color: colors.grid}},
      axisTick: {show: false},
    },
    series: [{
      type: 'custom',
      encode: {x: [1, 2], y: 0},
      data,
      renderItem: (params, api) => {
        const index = api.value(0);
        const start = api.value(1);
        const finish = api.value(2) ?? start;
        if (start == null) return null;
        const startPoint = api.coord([start, index]);
        const endPoint = api.coord([finish, index]);
        const width = Math.max(4, endPoint[0] - startPoint[0]);
        const height = api.size([0, 1])[1] * 0.52;
        const y = startPoint[1] - height / 2;
        const isSummary = Boolean(api.value(4));
        const isMilestone = Boolean(api.value(5));
        const selected = api.value(6) === state.selectedId;
        const fill = selected ? colors.selected : (isSummary ? colors.summary : colors.bar);
        if (isMilestone) {
          const center = [startPoint[0], startPoint[1]];
          return {type: 'polygon', shape: {points: [[center[0], center[1] - 7], [center[0] + 7, center[1]], [center[0], center[1] + 7], [center[0] - 7, center[1]]]}, style: {fill}};
        }
        const progressWidth = width * Math.max(0, Math.min(1, Number(api.value(3)) / 100));
        return {
          type: 'group',
          children: [
            {type: 'rect', shape: {x: startPoint[0], y, width, height}, style: {fill, opacity: 0.9, radius: 3}},
            {type: 'rect', shape: {x: startPoint[0], y: y + height - 4, width: progressWidth, height: 4}, style: {fill: colors.progress}},
          ],
        };
      },
    }],
  };
  if (!state.gantt) state.gantt = echarts.init(document.getElementById('gantt-chart'));
  state.gantt.setOption(option, true);
  state.gantt.off('click');
  state.gantt.on('click', (params) => {
    const id = params.value?.[6];
    if (id) selectTask(id);
  });
}

function renderWbs() {
  if (!window.echarts) return;
  const colors = chartColors();
  if (!state.wbs) state.wbs = echarts.init(document.getElementById('wbs-chart'));
  state.wbs.setOption({
    animationDuration: 220,
    backgroundColor: colors.background,
    tooltip: {formatter: (params) => {
      const task = params.data?.task;
      return task ? `<strong>${escapeLabel(task.name)}</strong><br>${formatDate(task.start)} - ${formatDate(task.finish)}<br>${formatPercent(task.percentComplete)} complete` : escapeLabel(params.name);
    }},
    series: [{
      type: 'tree',
      data: [taskTree()],
      top: '4%', left: '3%', bottom: '4%', right: '16%',
      orient: 'LR',
      symbol: 'roundRect',
      symbolSize: [10, 10],
      edgeShape: 'polyline',
      edgeForkPosition: '55%',
      initialTreeDepth: -1,
      label: {position: 'right', verticalAlign: 'middle', align: 'left', color: colors.text, fontSize: 12},
      leaves: {label: {position: 'right', color: colors.text}},
      lineStyle: {color: colors.grid, width: 1.2},
      itemStyle: {color: colors.bar, borderColor: colors.background},
      emphasis: {focus: 'descendant'},
      expandAndCollapse: true,
      roam: true,
    }],
  }, true);
  state.wbs.off('click');
  state.wbs.on('click', (params) => {
    if (params.data?.task?.uid) selectTask(params.data.task.uid);
  });
}

function selectTask(id) {
  state.selectedId = String(id);
  const task = state.taskById.get(state.selectedId);
  elements.selectionStatus.textContent = task ? `${task.name} · ${formatPercent(task.percentComplete)}` : 'No task selected';
  renderGantt();
}

function setView(view) {
  const gantt = view === 'gantt';
  elements.ganttPanel.classList.toggle('hidden', !gantt);
  elements.wbsPanel.classList.toggle('hidden', gantt);
  document.querySelectorAll('.gantt-only').forEach((element) => element.classList.toggle('hidden', !gantt));
  document.querySelectorAll('.wbs-only').forEach((element) => element.classList.toggle('hidden', gantt));
  if (gantt) { renderGantt(); state.gantt?.resize(); } else { renderWbs(); state.wbs?.resize(); }
}

function fitGantt() {
  if (state.gantt) state.gantt.dispatchAction({type: 'restore'});
}

function collapseAll() {
  state.collapsed = new Set(state.tasks.filter((task) => task.summary || childrenOf(task.uid).length > 0).map((task) => task.uid));
  renderWbs();
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
      renderWbs();
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

elements.view.addEventListener('change', () => setView(elements.view.value));
elements.scale.addEventListener('change', () => { state.scale = elements.scale.value; renderGantt(); });
elements.fit.addEventListener('click', fitGantt);
elements.collapse.addEventListener('click', collapseAll);
elements.search.addEventListener('input', () => {
  state.query = elements.search.value.trim().toLowerCase();
  renderGantt();
  renderWbs();
});
window.addEventListener('resize', () => { state.gantt?.resize(); state.wbs?.resize(); });
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { renderGantt(); renderWbs(); });

if (!window.echarts) {
  elements.loading.classList.add('hidden');
  elements.errorPanel.classList.remove('hidden');
  elements.errorMessage.textContent = 'ECharts assets are missing from the plugin package.';
} else {
  loadProject();
}
