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

// FFmpeg 可判定音频/视频家族的 demuxer 集合（只用于 UV 合并类目的拆分）。
const AUDIO_FAMILY = new Set([
  'act', 'adts', 'aea', 'afc', 'aiff', 'aac', 'ac3', 'amr', 'amrnb', 'amrwb',
  'ape', 'apm', 'aptx', 'aptx_hd', 'au', 'bonk', 'caf', 'daud', 'dfpwm',
  'dsf', 'dss', 'dts', 'dtshd', 'eac3', 'flac', 'g722', 'g723_1', 'g726',
  'g726le', 'g728', 'g729', 'gsm', 'hca', 'hcom', 'htk', 'ilbc', 'ircam',
  'loas', 'mlp', 'mmf', 'mods', 'mp3', 'mpc', 'mpc8', 'mtaf', 'msf', 'musx',
  'oma', 'osq', 'paf', 'qcp', 'rka', 'rso', 'sbc', 'shn', 'sln', 'sol',
  'sox', 'spdif', 'tak', 'tta', 'vqf', 'w64', 'wav', 'wsaud', 'wv', 'xa',
  'xwma',
]);
const VIDEO_FAMILY = new Set([
  '4xm', 'avs', 'bethsoftvid', 'bfi', 'bink', 'bmv', 'c93', 'cam',
  'cavsvideo', 'cdxl', 'cine', 'cmv', 'dfa', 'dirac', 'dnxhd', 'dv',
  'dvdvideo', 'dxa', 'flic', 'gdv', 'h261', 'h263', 'h264', 'hevc', 'hnm',
  'idcin', 'ifv', 'ingenient', 'iv8', 'ivf', 'jv', 'lvf', 'lxf', 'm4v',
  'mjpeg', 'mlv', 'moflex', 'mtv', 'mv', 'mvi', 'mxg', 'nuv', 'pmp',
  'psxstr', 'r3d', 'rl2', 'siff', 'smacker', 'smjpeg', 'thp', 'tiertexseq',
  'tmv', 'truehd', 'vmd', 'vivo', 'wc3movie', 'wsvqa', 'yop',
]);
// 未判定家族的非文件类型（伪格式/协议/原始流/字幕）→ 附录，不占主表。
const audioVideoCat = (ext) => {
  const name = ext.slice(1);
  if (AUDIO_FAMILY.has(name)) return 'Audio';
  return 'Video';
};

// 解析 FVP 的 Audio/Video 归属，供 UV 合并类目归一化。
const fvpAV = new Map();
for (const row of FVP) {
  if (row.cat === 'Audio' || row.cat === 'Video') {
    fvpAV.set(row.ext, row.cat);
  }
}
const splitAV = (cat, ext) => {
  if (cat !== 'Audio/Video') return cat;
  return fvpAV.get(ext) ?? audioVideoCat(ext);
};
const splitDocs = (cat, ext) => {
  if (cat !== 'Documents/Spreadsheets') return cat;
  for (const row of FVP) {
    if (row.ext === ext) {
      return normalizeCat(row.cat);
    }
  }
  return cat;
};

// 合并：键 = (ext, 归一化类别)。FVP 类别优先；差异格式名合并在说明里。
const merge = (list, source) => {
  const out = new Map();
  for (const row of list) {
    const cat = splitDocs(splitAV(normalizeCat(row.cat), row.ext), row.ext);
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

// 同扩展名合并：跨来源同格式名的合并；"Source Code/Web" 视为等价类别
// （如 .asp/.css/.php/.xml/.xsl 在两份参考里归类不一致）合并为一行。
const nameKey = (name) => name.toLowerCase().replace(/\s+/g, ' ').trim();
const byExt = new Map();
for (const [key, row] of merged) {
  if (!byExt.has(row.ext)) byExt.set(row.ext, []);
  byExt.get(row.ext).push({ key, row });
}
for (const group of byExt.values()) {
  if (group.length <= 1) continue;
  const cats = new Set(group.map((item) => item.row.cat));
  const equivalent =
    cats.size === 2 &&
    cats.has('Source Code') &&
    cats.has('Web');
  const sameName = new Set(
    group.map((item) => nameKey(item.row.names.FVP ?? item.row.names.UV)),
  ).size === 1;
  if (!equivalent && !sameName) continue;
  // 同格式名合并：优先 FVP 归类；等价类别（Source Code/Web）才合并类别名。
  const mergedCats = equivalent
      ? [...cats].sort().join(' / ')
      : group.find((item) => item.row.names.FVP)?.row.cat ??
        [...cats].find((cat) => cat !== 'Audio/Video') ??
        [...cats][0];
  const names = Object.assign({}, ...group.map((item) => item.row.names));
  const sources = [...new Set(group.flatMap((item) => item.row.sources))];
  const keep = { ext: group[0].row.ext, cat: mergedCats, names, sources };
  for (const item of group) merged.delete(item.key);
  merged.set(`n\u0000${group[0].row.ext}`, keep);
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
// 非文件类型（伪格式/协议/原始流/字幕）→ 附录，不占主表。
const NON_FILE = new Set([
  ...PSEUDO, ...PCM, ...NETWORK, ...SUBTITLES,
]);
const RAW_SLUG = (ext) => ext.slice(1).toUpperCase();
// FFmpeg demuxer 注册名与文件扩展名不一致的别名。
const DEMUXER_ALIAS = { '.dvd': 'dvdvideo', '.ipod': 'mov', '.psp': 'mov', '.cin': 'cine' };

// 同名不同义后缀的非默认语义行：状态手动说明（默认规则属于另一语义）。
const SEMANTIC_OVERRIDES = {
  '.iss|Audio':
    '🔮 默认 .iss 规则为 Inno Setup（code）；Funcom ISS 音频属 MIME/内容嗅探子类，待嗅探器',
  '.vst|Image':
    '🔮 默认 .vst 规则为 Visio 模板（onlyoffice）；Truevision 图像属 MIME/内容嗅探子类，待嗅探器',
  '.cin|Video':
    '⚠️ 默认 .cin 规则为 Cineon 位图（image）；Delphine CIN 视频可由 FFmpeg（cine）解码，待实测/嗅探',
  '.vb|Video':
    '❌ 默认 .vb 规则为 VBScript（code）；Beam SIFF 视频无对应 demuxer',
  '.vhd|Archive':
    '🔮 默认 .vhd 规则为 VHDL（code）；虚拟硬盘属 MIME/内容嗅探子类，待嗅探器',
  '.ani|Image':
    '❌ WIC/ImageMagick 无对应 codec；Windows 光标 API（GDI）可读，image-view 未接入（待评估）',
  '.icl|Image':
    '❌ WIC/ImageMagick 无对应 codec；Windows 图标资源 API（GDI）可读，image-view 未接入（待评估）',
  '.emz|Image':
    '⚠️ gzip 压缩的 EMF；ImageMagick EMF 渲染器已就绪，image-view 未做解压包装（低成本可支持）',
  '.wmz|Image':
    '⚠️ gzip 压缩的 WMF；ImageMagick WMF 渲染器已就绪，image-view 未做解压包装（低成本可支持）',
};

const statusFor = (row) => {
  const { ext, cat } = row;
  const semantic = SEMANTIC_OVERRIDES[`${ext}|${cat}`];
  if (semantic) return semantic;
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
    const name = DEMUXER_ALIAS[ext] ?? ext.slice(1);
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
  'Web', 'Source Code / Web', 'Documents/Spreadsheets',
];
const rows = [...merged.values()].sort((a, b) => {
  const ca = CAT_ORDER.indexOf(a.cat);
  const cb = CAT_ORDER.indexOf(b.cat);
  const order = (ca < 0 ? 99 : ca) - (cb < 0 ? 99 : cb);
  return order !== 0 ? order : a.ext.localeCompare(b.ext);
});

// 拆出非文件类型行（附录），主表只保留文件格式。
const APPENDIX_CAT = (ext) => PSEUDO.has(ext)
    ? 'FFmpeg 伪格式'
    : PCM.has(ext)
    ? '原始 PCM 流'
    : NETWORK.has(ext)
    ? '网络协议'
    : '字幕';
const mainRows = [];
const appendixRows = [];
for (const row of rows) {
  if (NON_FILE.has(row.ext)) {
    appendixRows.push({ ...row, cat: APPENDIX_CAT(row.ext) });
  } else {
    mainRows.push(row);
  }
}

const describe = (row) => {
  const parts = [];
  if (row.names.FVP) parts.push(row.names.FVP);
  if (row.names.UV && row.names.UV !== row.names.FVP) parts.push(row.names.UV);
  return parts.join(' / ');
};

// 同名不同义/双语义后缀：多行列出，这里汇总为表头说明。
const dupExts = new Map();
for (const row of mainRows) {
  if (!dupExts.has(row.ext)) dupExts.set(row.ext, []);
  dupExts.get(row.ext).push(row);
}
const dupNote = [...dupExts.entries()]
  .filter(([, group]) => group.length > 1)
  .map(
    ([ext, group]) =>
      `- \`.${ext.replace('.', '')}\`：${group
        .map((row) => `${row.cat}（${describe(row)}）`)
        .join('；')}`,
  )
  .join('\n');

const table = mainRows
  .map(
    (row) =>
      `| ${row.cat} | ${row.ext} | ${describe(row)} | ${statusFor(row)} |`,
  )
  .join('\n');

const appendixTable = appendixRows
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
> 支持面判定依据（image-view 的解码链：原生 image/rawloader → ImageMagick 子进程 →
> Windows WIC 子进程；video-view：mpv/FFmpeg）：
> - FFmpeg \`libavformat/allformats.c\` 的 368 个 demuxer（对应 shinchiro \`mpv-dev\`
>   全量构建）；
> - ImageMagick 实测 \`magick -list format\` 输出；
> - Windows WIC：系统内置 codec（JXR、HEIF[+扩展]、WMF/EMF、DIB 等），仅作兜底，
>   随 OS 版本/厂商 codec 安装情况浮动，不作为覆盖判定的确定性依据。
>
> 注：无扩展名规则的文件可能经 \`image/*\`、\`video/*\`、\`audio/*\`、\`text/*\`
> MIME 兜底命中（依赖系统注册的 Content Type 与后端解码能力）；同名冲突后缀的
> 常见语义作为默认 viewer、其余语义作为 MIME 子类表达。重新生成：
> \`node tools/gen_format_matrix.mjs\`。
>
> 同名不同义/双语义的后缀（按参考清单分多行列出）：
${dupNote}

| 类别 | 后缀名 | 格式说明 | 是否支持，如何支持 |
| --- | --- | --- | --- |
${table}

## 附录：非文件类型项（不追踪）

> UV 参考清单照搬了 FFmpeg 的 demuxer/muxer 清单，包含非文件的格式名：伪格式（流/管线/
> 调试输出）、网络协议、无编码参数的原始采样流、字幕。它们不是文件类型，不参与关联，
> 仅留档备查。

| 类别 | 后缀名 | 格式说明 | 是否支持，如何支持 |
| --- | --- | --- | --- |
${appendixTable}
`;

writeFileSync('docs/viewer-format-matrix.md', doc, 'utf8');
const covered = mainRows.filter((r) => statusFor(r).startsWith('✅')).length;
console.log(
  `wrote docs/viewer-format-matrix.md: ${mainRows.length} rows, ` +
    `covered ${covered} (${(covered / mainRows.length * 100).toFixed(1)}%), ` +
    `appendix ${appendixRows.length}`,
);
