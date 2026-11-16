// Render interview videos from real device recordings and an explicit edit plan.
// Never invents UI frames: only trims/speeds actual footage and adds annotations.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'showcase');
const work = path.join(root, '.local/showcase/render');
const planPath = path.join(output, 'edit-plan.json');

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', windowsHide: true,
    maxBuffer: 4 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed:\n${result.stderr || result.stdout}`);
  return result.stdout;
}
function probe(file) {
  return JSON.parse(run('ffprobe', ['-v', 'error', '-show_format', '-show_streams', '-of', 'json', file]));
}
function time(seconds, ass = false) {
  const scale = ass ? 100 : 1000;
  const ticks = Math.round(seconds * scale);
  const h = Math.floor(ticks / (3600 * scale));
  const m = Math.floor(ticks / (60 * scale)) % 60;
  const s = Math.floor(ticks / scale) % 60;
  const rest = ticks % scale;
  return `${ass ? h : String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}${ass ? '.' : ','}${String(rest).padStart(ass ? 2 : 3, '0')}`;
}
function assText(value) {
  return String(value).replace(/\\/g, '／').replace(/[{}]/g, '').replace(/\r?\n/g, '\\N');
}
function line(start, end, style, text) {
  return `Dialogue: 0,${time(start, true)},${time(end, true)},${style},,0,0,0,,${text}`;
}
const assHeader = `[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0
ScaledBorderAndShadow: yes
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Base,Microsoft YaHei,34,&H00FFFFFF,&H000000FF,&H00101827,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,650,80,70,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
`;

if (!fs.existsSync(planPath)) throw new Error('Record the device flows and create showcase/edit-plan.json first.');
const plan = JSON.parse(fs.readFileSync(planPath, 'utf8'));
fs.mkdirSync(work, { recursive: true });
fs.mkdirSync(path.join(output, 'videos'), { recursive: true });
fs.mkdirSync(path.join(output, 'subtitles'), { recursive: true });
fs.mkdirSync(path.join(output, 'posters'), { recursive: true });
const manifest = { recordedOn: plan.recordedOn, format: 'H.264 MP4, 1920×1080, 30 fps, silent',
  editing: 'Real device footage. Waiting may be shortened as specified in the edit plan. No simulated UI.',
  videos: [] };

for (const item of plan.videos) {
  if (!/^(line|vk)$/.test(item.id)) throw new Error('Unsupported video id');
  const input = path.resolve(root, item.source);
  const relative = path.relative(root, input);
  if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('Input must stay inside the workspace');
  if (!fs.existsSync(input)) throw new Error(`Missing real recording: ${item.source}`);
  const inputInfo = probe(input);
  const inputDuration = Number(inputInfo.format.duration);
  if (!Number.isFinite(inputDuration) || inputDuration <= 0) throw new Error('Invalid input duration');
  let cursor = 0;
  const chapters = item.segments.map((segment, index) => {
    const speed = segment.speed ?? 1;
    if (![segment.from, segment.to, speed].every(Number.isFinite) || segment.from < 0 ||
      segment.to <= segment.from || segment.to > inputDuration + 0.1 || speed <= 0 || speed > 12) {
      throw new Error(`Invalid segment ${item.id} #${index + 1}`);
    }
    const start = cursor;
    const frames = Math.round((segment.to - segment.from) / speed * 30);
    cursor += frames / 30;
    return { start, end: cursor, title: segment.title, narration: segment.narration,
      note: segment.note || '', sourceFrom: segment.from, sourceTo: segment.to, speed, frames };
  });
  const duration = cursor;
  const events = [
    line(0, duration, 'Base', '{\\pos(650,76)\\fs26\\c&H00B1C6E5&}HARMONYOS  /  MINI APP CONTAINER'),
    line(0, duration, 'Base', `{\\pos(650,160)\\fs62\\b1}${assText(item.title)}`),
    line(0, duration, 'Base', `{\\pos(650,252)\\fs32\\c&H00B1C6E5&}${assText(item.subtitle)}`),
    line(0, duration, 'Base', '{\\pos(650,936)\\fs25\\c&H00B1C6E5&}ArkTS · ArkWeb · 独立 HAR · API 26 真机'),
    line(0, duration, 'Base', '{\\pos(650,982)\\fs23\\c&H00B1C6E5&}真实业务录屏 / 静音字幕版 / 等待处理见素材说明')
  ];
  chapters.forEach((chapter, index) => {
    events.push(line(chapter.start, chapter.end, 'Base',
      `{\\pos(650,365)\\fs43\\b1\\c&H00E1C38B&}${String(index + 1).padStart(2, '0')}  ${assText(chapter.title)}`));
    events.push(line(chapter.start, chapter.end, 'Base',
      `{\\pos(650,465)\\fs37}${assText(chapter.narration)}`));
    if (chapter.note) events.push(line(chapter.start, chapter.end, 'Base',
      `{\\pos(650,800)\\fs26\\c&H00B1C6E5&}${assText(chapter.note)}`));
  });
  const assRelative = `.local/showcase/render/${item.id}.ass`;
  fs.writeFileSync(path.join(root, assRelative), assHeader + events.join('\n') + '\n');
  const filters = [`[0:v]fps=30,split=${chapters.length}` + chapters.map((_, i) => `[s${i}]`).join('')];
  chapters.forEach((chapter, index) => {
    filters.push(`[s${index}]trim=start=${chapter.sourceFrom}:end=${chapter.sourceTo},` +
      `setpts=(PTS-STARTPTS)/${chapter.speed},fps=30,` +
      `tpad=stop_mode=clone:stop_duration=1,trim=end_frame=${chapter.frames},setpts=PTS-STARTPTS,` +
      `crop=iw:trunc(ih*0.9107/2)*2:0:trunc(ih*0.0563/2)*2,` +
      `scale=466:960:force_original_aspect_ratio=decrease,pad=466:960:(ow-iw)/2:(oh-ih)/2:white,setsar=1[p${index}]`);
  });
  filters.push(chapters.map((_, i) => `[p${i}]`).join('') + `concat=n=${chapters.length}:v=1:a=0[phone]`);
  filters.push(`color=c=0x101827:s=1920x1080:r=30:d=${duration}[bg]`);
  filters.push(`[bg][phone]overlay=84:60:eof_action=endall,` +
    `drawbox=x=82:y=58:w=470:h=964:color=0x40577A:t=2,ass='${assRelative}'[v]`);
  const filterFile = path.join(work, `${item.id}.filter`);
  fs.writeFileSync(filterFile, filters.join(';\n'));
  const destination = path.join(output, 'videos', `${item.id}-business.mp4`);
  run('ffmpeg', ['-hide_banner', '-loglevel', 'warning', '-y', '-i', input,
    '-filter_complex_script', filterFile, '-map', '[v]', '-an',
    '-frames:v', String(chapters.reduce((sum, chapter) => sum + chapter.frames, 0)),
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart', destination]);
  const actual = probe(destination);
  const streams = actual.streams.filter(stream => stream.codec_type === 'video');
  if (streams.length !== 1 || streams[0].width !== 1920 || streams[0].height !== 1080 ||
    actual.streams.some(stream => stream.codec_type === 'audio') ||
    Math.abs(Number(actual.format.duration) - duration) > 0.05) throw new Error('Unexpected rendered streams or chapter timing');
  const lastChapter = chapters[chapters.length - 1];
  lastChapter.end = Number(actual.format.duration);
  lastChapter.frames = Math.round((lastChapter.end - lastChapter.start) * 30);
  const srt = chapters.map((chapter, i) => `${i + 1}\n${time(chapter.start)} --> ${time(chapter.end)}\n${chapter.title}\n${chapter.narration.replace(/\n/g, ' ')}\n`).join('\n');
  fs.writeFileSync(path.join(output, 'subtitles', `${item.id}.srt`), srt, 'utf8');
  const vtt = 'WEBVTT\n\n' + srt.replace(/^\d+\n/gm, '').replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');
  fs.writeFileSync(path.join(output, 'subtitles', `${item.id}.vtt`), vtt, 'utf8');
  run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', destination, '-f', 'null', '-']);
  const poster = `posters/${item.id}.jpg`;
  run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-ss', String(item.posterTime || duration / 2),
    '-i', destination, '-frames:v', '1', path.join(output, poster)]);
  const bytes = fs.readFileSync(destination);
  manifest.videos.push({ id: item.id, title: item.title, subtitle: item.subtitle,
    file: `videos/${item.id}-business.mp4`, poster, duration: Number(actual.format.duration),
    size: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    sourceDuration: inputDuration, chapters, boundaries: item.boundaries || [] });
  console.log(`${item.id}: rendered and decoded ${actual.format.duration}s, ${(bytes.length / 1048576).toFixed(1)} MiB`);
}
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
fs.writeFileSync(path.join(output, 'chapters.js'), 'window.SHOWCASE = ' + JSON.stringify(manifest, null, 2) + ';\n');
