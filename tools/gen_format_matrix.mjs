// Inf-Dir 格式总表生成器。
// 数据源：docs/file-type-reference/（FVP）+ docs/uvviewer-formats/（UV）。
// 支持面判定：FFmpeg demuxer 清单（libavformat/allformats.c，shinchiro mpv-dev 全量构建）
// 与 ImageMagick 实测输出（magick -list format）。本脚本读取缓存于 %TEMP% 的
// ffmpeg_demuxers.txt / magick_formats.txt（获取方式见文件头注释）；
// 若缺失可重新拉取：https://raw.githubusercontent.com/FFmpeg/FFmpeg/master/libavformat/allformats.c
// 与 `magick -list format`。
// 用法：node tools/gen_format_matrix.mjs
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import os from 'node:os';

const temp = os.tmpdir();
const demuxerFile = join(temp, 'ffmpeg_demuxers.txt');
const magickFile = join(temp, 'magick_formats.txt');
const demuxers = existsSync(demuxerFile)
  ? new Set(readFileSync(demuxerFile, 'utf8').split(/\s+/).filter(Boolean))
  : new Set();
const magickText = existsSync(magickFile) ? readFileSync(magickFile, 'utf8') : '';
const magickNames = new Set(
  [...magickText.matchAll(/^\s*([A-Z0-9]+)\*?\s/gm)].map((m) => m[1]),
);

// ---------------------------------------------------------------------------
// 参考清单解析
// ---------------------------------------------------------------------------

const parseDoc = (file) => {
  const rows = [];
  let cat = '?';
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const h = /^## ([^\r\n]+)/.exec(line);
    if (h) {
      cat = h[1].trim();
      continue;
    }
    const m = /^\|\s*(\.[a-z0-9]+(?:\.[a-z0-9]+)*)\s*\|\s*([^|]+)\s*\|/.exec(line);
    if (m && cat !== '分类汇总') rows.push({ cat, ext: m[1], name: m[2].trim() });
  }
  return rows;
};

const FVP = parseDoc('docs/file-type-reference/file-type-reference.md');
const UV = parseDoc('docs/uvviewer-formats/uvviewer-formats.md');

const normalizeCat = (cat) => {
  switch (cat) {
    case 'Camera Raw':
      return 'RAW';
    case 'Images':
      return 'Image';
    case 'RAW Images':
      return 'RAW';
    case 'Internet':
      return 'Web';
    default:
      return cat;
  }
};

// 合并：键 = (ext, 归一化类别)。FVP 类别优先；差异格式名合并在说明里。
const merge = (list, source) => {
  const out = new Map();
  for (const row of list) {
    const cat = normalizeCat(row.cat);
    const key = `${row.ext}\u0000${cat}`;
    const existing = out.get(key);
    if (!existing) {
      out.set(key, { ext: row.ext, cat, names: { [source]: row.name }, sources: [source] });
    } else {
      existing.names[source] = row.name;
      if (!existing.sources.includes(source)) existing.sources.push(source);
    }
  }
  return out;
};

const merged = merge(FVP, 'FVP');
for (const [key, row] of merge(UV, 'UV')) {
  // 同 (ext, 类别) 已在 FVP 则跳过（FVP 类别优先）；UV 自定义类别保留。
  if (merged.has(key)) {
    const existing = merged.get(key);
    existing.names.UV = row.names.UV;
    if (!existing.sources.includes('UV')) existing.sources.push('UV');
  } else {
    merged.set(key, row);
  }
}

// ---------------------------------------------------------------------------
// 覆盖状态
// ---------------------------------------------------------------------------

const config = JSON.parse(readFileSync('plugins/quick-view.default.json', 'utf8'));
const ruleByExt = new Map();
const walk = (rule) => {
  if (rule.type === 'extension' || rule.type === 'fileName') {
    ruleByExt.set(rule.value, rule);
  }
  rule.rules.forEach(walk);
};
config.rules.forEach(walk);
const viewName = (id) => id.replace('inf-dir.', '').replace('-view', '');

const PSEUDO = new Set([
  '.mpeg1video .mpeg2video .mpegts .mpegtsraw .mpegvideo .mpjpeg .cavsvideo .vc1test',
  '.rawvideo .yuv4mpegpipe .image2 .image2pipe .ffm .ffmetadata .framecrc .framemd5',
  '.md5 .crc .null .matroska .avm2 .applehttp .msnwctcp .vfwcap .filmstrip',
].join(' ').trim().split(/\s+/));
const PCM = new Set(
  ['.alaw .mulaw .s8 .u8 .s16be .s16le .s24be .s24le .s32be .s32le .f32be .f32le',
   '.f64be .f64le .u16be .u16le .u24be .u24le .u32be .u32le'].join(' ').split(/\s+/),
);
const SUBTITLES = new Set(['.ass', '.srt']);
const NETWORK = new Set(['.rtp', '.rtsp', '.sap', '.sdp', '.hls']);
const RAW_SLUG = (ext) => ext.slice(1).toUpperCase();

const statusFor = (row) => {
  const { ext, cat } = row;
  const rule = ruleByExt.get(ext);
  if (rule !== undefined) {
    const viewers = rule.viewers.map((v) => viewName(v.id)).join('、');
    return `✅ ${viewers}（${rule.type === 'fileName' ? '文件名' : '扩展名'}规则）`;
  }
  // .dat：常见语义 = 默认 viewer，其他语义 = MIME/内容嗅探子类
  if (ext === '.dat') {
    return cat === 'Email'
      ? '✅ email（扩展名规则默认语义；winmail.dat/win.dat 另有文件名规则增强）'
      : '🔮 默认规则下的 MIME 子类（video/* → 媒体查看器），待内容嗅探器命中';
  }
  if (ext === '.dd') return '❌ 非压缩包（原始磁盘镜像），libarchive 不处理';
  if (cat === 'Audio' || cat === 'Video' || cat === 'Audio/Video') {
    const name = ext.slice(1);
    if (PSEUDO.has(ext)) return '❌ 非文件类型（FFmpeg 流/管线名），无需覆盖';
    if (PCM.has(ext)) return '❌ 原始采样流（扩展名不含编码参数）';
    if (SUBTITLES.has(ext)) return '❌ 字幕文件（播放时内嵌显示）';
    if (NETWORK.has(ext)) return '❌ 网络协议，非文件';
    if (demuxers.has(name)) return '⚠️ FFmpeg 可解，未在配置声明（待实测）';
    return '❌ FFmpeg 无对应 demuxer';
  }
  if (cat === 'Image') {
    return magickNames.has(RAW_SLUG(ext)) || ext === '.jpe' || ext === '.jfif'
      ? '⚠️ ImageMagick 可解，未在配置声明（待实测）'
      : '❌ ImageMagick 无对应 decoder';
  }
  if (cat === 'RAW') {
    return magickNames.has(RAW_SLUG(ext))
      ? '⚠️ ImageMagick 可解，未在配置声明（待实测）'
      : '❌ rawloader/ImageMagick 无对应 coder';
  }
  return '❌ 未支持（待评估）';
};

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------

const CAT_ORDER = [
  'Text', 'PDF & XPS', 'Spreadsheet', 'Presentation', 'Visio', 'Project',
  'CAD', 'Email', 'Image', 'RAW', 'Audio', 'Video', 'Archive', 'Source Code',
  'Web', 'Documents/Spreadsheets', 'Audio/Video',
];
const rows = [...merged.values()].sort((a, b) => {
  const ca = CAT_ORDER.indexOf(a.cat);
  const cb = CAT_ORDER.indexOf(b.cat);
  const order = (ca < 0 ? 99 : ca) - (cb < 0 ? 99 : cb);
  return order !== 0 ? order : a.ext.localeCompare(b.ext);
});

const describe = (row) => {
  const parts = [];
  if (row.names.FVP) parts.push(row.names.FVP);
  if (row.names.UV && row.names.UV !== row.names.FVP) parts.push(row.names.UV);
  return parts.join(' / ');
};

const table = rows
  .map(
    (row) =>
      `| ${row.cat} | ${row.ext} | ${describe(row)} | ${statusFor(row)} |`,
  )
  .join('\n');

const doc = `# Inf-Dir Viewer 格式总表

> 本表为 Quick View 格式覆盖的**唯一追踪表**，替代原 \`docs/viewer-format-roadmap.md\`。
> 数据源：\`docs/file-type-reference/\`（File Viewer Plus，FVP）与
> \`docs/uvviewer-formats/\`（Universal Viewer，UV）。同名不同义的后缀分多行列出
> （如 \`.dat\`：Winmail 邮件 / VCD 视频；\`.cin\`：Cineon 位图 / Delphine 视频）。
>
> 状态列图例：
> - \`✅\` 已支持（同时给出 viewer 与命中方式：扩展名/文件名规则或 MIME 子类）；
> - \`🔮\` 依赖更强的内容/MIME 嗅探器（规则体系已就绪，嗅探器上线后自动命中）；
> - \`⚠️\` 后端可解但未在配置声明（待实测后补 manifest 与默认配置）；
> - \`❌\` 后端无对应能力或非文件类型（伪格式、网络协议、原始采样流、字幕等）。
>
> 支持面判定依据：FFmpeg \`libavformat/allformats.c\` 的 368 个 demuxer（对应
> shinchiro \`mpv-dev\` 全量构建）与 ImageMagick 实测 \`magick -list format\` 输出。
> 注：无扩展名规则的文件可能经 \`image/*\`、\`video/*\`、\`audio/*\`、\`text/*\`
> MIME 兜底命中（依赖系统注册的 Content Type 与后端解码能力）；同名冲突后缀的
> 常见语义作为默认 viewer、其余语义作为 MIME 子类表达。重新生成：
> \`node tools/gen_format_matrix.mjs\`。

| 类别 | 后缀名 | 格式说明 | 是否支持，如何支持 |
| --- | --- | --- | --- |
${table}
`;

writeFileSync('docs/viewer-format-matrix.md', doc, 'utf8');
const covered = rows.filter((r) => statusFor(r).startsWith('✅')).length;
console.log(
  `wrote docs/viewer-format-matrix.md: ${rows.length} rows, ` +
    `covered ${covered} (${(covered / rows.length * 100).toFixed(1)}%)`,
);
