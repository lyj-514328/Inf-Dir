// Coverage diff grouped by reference doc section.
import { readFileSync } from 'node:fs';

const parseSections = (file) => {
  const lines = readFileSync(file, 'utf8').split('\n');
  const sections = [];
  let current = '?';
  const bySection = new Map();
  for (const line of lines) {
    const h = /^## ([^\r\n]+)/.exec(line);
    if (h) {
      current = h[1];
      continue;
    }
    const m = /^\|\s*(\.[a-z0-9]+(?:\.[a-z0-9]+)*)\s*\|/.exec(line);
    if (m) {
      if (!bySection.has(current)) bySection.set(current, new Set());
      bySection.get(current).add(m[1]);
    }
  }
  return bySection;
};

const covered = new Set();
const defaultConfig = JSON.parse(
  readFileSync('plugins/quick-view.default.json', 'utf8'),
);
const walk = (rule) => {
  if (rule.type === 'extension' || rule.type === 'fileName') covered.add(rule.value);
  rule.rules.forEach(walk);
};
defaultConfig.rules.forEach(walk);

for (const label of ['FVP', 'UV']) {
  const file =
    label === 'FVP'
      ? 'docs/file-type-reference/file-type-reference.md'
      : 'docs/uvviewer-formats/uvviewer-formats.md';
  console.log(`\n===== ${label} gaps by category =====`);
  let total = 0;
  for (const [section, exts] of parseSections(file)) {
    const gaps = [...exts].filter((ext) => !covered.has(ext)).sort();
    if (gaps.length === 0) continue;
    total += gaps.length;
    console.log(`[${section}] (${gaps.length}/${exts.size}): ${gaps.join(' ')}`);
  }
  console.log(`=> total gaps: ${total}`);
}
