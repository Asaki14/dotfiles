#!/usr/bin/env node
// 把任意 omp 内置主题派生成 `<name>-status`：只改 toolSuccessBg（绿）与 toolErrorBg（红），
// 让工具块一眼区分成功与失败。其余 token 逐字保留。
//
// omp 没有跨主题的颜色覆盖层——settings 里只有 theme.dark / theme.light / symbolPreset /
// colorBlindMode，颜色只能整份主题替换。所以换主题就得为新主题再派生一份，这个脚本就是为此存在。
//
// 用法：
//   node derive-status-theme.mjs dark-tokyo-night light-catppuccin
//   node derive-status-theme.mjs --all          # 全部内置主题（omp 18.10.4 为 100 个）
//   OMP_BIN=/path/to/omp node derive-status-theme.mjs <name>
//   node derive-status-theme.mjs --file=<theme.json>  # 原地派生外部生成的主题，名字不变
//
// 内置主题 JSON 被 bundler 编进 omp 可执行文件，这里直接从二进制里把对象字面量抠出来。

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const SUFFIX = "-status";
// 成功=绿、失败=红。只借用色相与饱和度，明度取原底色的，见 tint()。
// 饱和度只要够分辨色相就行，高饱和会让工具块从正文里跳出来抢注意力；绿色对相对亮度
// 贡献最大（系数 0.7152），提饱和还会压低正文对比，由 tint() 的对比守卫回降明度补偿。
// 两个默认值可用 --sat=<0..1> 整体覆盖（深色底与浅色底按同一比例缩放）。
const SUCCESS_HUE = 140;
const ERROR_HUE = 356;
const SAT_DARK_DEFAULT = 0.2;
const SAT_LIGHT_DEFAULT = 0.14;
let SAT_DARK = SAT_DARK_DEFAULT;
let SAT_LIGHT = SAT_LIGHT_DEFAULT;
// 底色过于接近纯黑/纯白时色相看不出来，给明度一个下限/上限。
const MIN_L_DARK = 0.085;
const MAX_L_LIGHT = 0.93;
// 着色后正文对底色的对比度不得低于原底色的这个比例，也不得低于绝对下限。
const CONTRAST_KEEP = 0.95;
const CONTRAST_FLOOR = 1.8;
// 工具块和页面底的明度差下限：低于这个值，半透明终端里色相被壁纸冲淡后块就看不见了。
const TOOL_BG_MIN_RATIO = 1.25;
// 思考过程与正文同色时读者分不清哪段是给自己看的（内置主题里 thinkingText 往往直接
// 等于 muted，也就是接近正文的浅灰）。按对比度而不是按混合比例定目标：不同主题的正文
// 对比度差出好几倍，固定混合比例在高对比主题上不够淡、在低对比主题上直接混没。
// 目标 = 正文对底色的对比度 × THINKING_KEEP，可用 --thinking=<0..1> 覆盖。
const THINKING_KEEP_DEFAULT = 0.2;
let THINKING_KEEP = THINKING_KEEP_DEFAULT;
// 淡到读不出来就失去意义，无论比例算出什么，对底色的对比度不低于这个值。
const THINKING_CONTRAST_FLOOR = 1.9;
// 正文（text）默认是空字符串 = 终端默认前景色，多数暗色终端配的是接近纯白的浅色，
// 长时间读刺眼。同样按对比度定目标压暗，可用 --text=<0..1> 覆盖；1 = 不动。
// 注意：一旦写成具体色值，正文就不再跟随终端配色，换 Ghostty 主题也不会变。
const TEXT_KEEP_DEFAULT = 0.5;
let TEXT_KEEP = TEXT_KEEP_DEFAULT;
// 正文压暗不能压到费劲。7:1（AAA）实测看不出差别，降到 5.5：仍高于 AA 的 4.5，
// 且这是对主题自己的页面底算的，真实终端底更暗，实际落地对比度还要更高一档。
const TEXT_CONTRAST_FLOOR = 5.5;
// 多数内置主题把 userMessageBg 设成和页面底同色（tokyo-night 与 copper 都是），于是
// 「我说的话」根本没有块感，旁边带色的工具块反倒最显眼。把它压成中性暗带：不带色相，
// 和染过色的成功/失败块天然分得开。--user=<0..1> 覆盖，0 = 不动。
const USER_BG_DARKEN_DEFAULT = 0.45;
let USER_BG_DARKEN = USER_BG_DARKEN_DEFAULT;
// 压到看不出边界就白做了，和页面底的对比度至少要到这个值。
const USER_BG_MIN_RATIO = 1.35;

function ompBinary() {
  if (process.env.OMP_BIN) return realpathSync(process.env.OMP_BIN);
  const which = execFileSync("/usr/bin/which", ["omp"], { encoding: "utf8" }).trim();
  if (!which) throw new Error("找不到 omp 可执行文件，用 OMP_BIN 指定");
  return realpathSync(which);
}

function builtinNames(buf) {
  const names = new Set();
  const re = /src\/(?:modes\/)?theme\/defaults\/([a-z0-9-]+)\.json/g;
  const text = buf.toString("latin1");
  let m;
  while ((m = re.exec(text))) names.add(m[1]);
  return [...names].sort();
}

// 二进制里的形状（omp 18.10 起主题挪到 packages/tui，且不再包懒加载闭包）：
//   // packages/tui/src/theme/defaults/<name>.json
//   var ct = { ... };
// 旧版本是 packages/coding-agent/src/modes/theme/defaults/<name>.json，对象字面量包在
//   var Rxo = R(() => { Sxo = { ... }; });
// 里。两种形状下标记之后第一个 `= {` 都是对象字面量的开头。
function extractTheme(buf, name) {
  const marker = Buffer.from(`defaults/${name}.json`);
  const at = buf.indexOf(marker);
  if (at === -1) throw new Error(`二进制里没有内置主题 ${name}`);
  const window = buf.slice(at, at + 40_000).toString("utf8");
  const open = window.indexOf("= {");
  if (open === -1) throw new Error(`无法定位 ${name} 的对象字面量`);
  let depth = 0;
  let end = -1;
  for (let i = open + 2; i < window.length; i++) {
    const ch = window[i];
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end === -1) throw new Error(`${name} 的对象字面量括号不配平`);
  const literal = window.slice(open + 2, end + 1);
  // 对象字面量里只有字符串、数字与标识符键，没有表达式或调用。
  return new Function(`return (${literal});`)();
}

const hexRe = /^#[0-9a-fA-F]{6}$/;

function resolveValue(value, vars, seen = new Set()) {
  if (value === "" || value == null) return null;
  if (typeof value === "number") return xterm256(value);
  if (hexRe.test(value)) return hexToRgb(value);
  if (seen.has(value)) throw new Error(`vars 循环引用: ${value}`);
  if (!(value in vars)) return null;
  seen.add(value);
  return resolveValue(vars[value], vars, seen);
}

function xterm256(n) {
  if (n < 16) {
    const base = [
      [0, 0, 0], [205, 0, 0], [0, 205, 0], [205, 205, 0], [0, 0, 238], [205, 0, 205], [0, 205, 205], [229, 229, 229],
      [127, 127, 127], [255, 0, 0], [0, 255, 0], [255, 255, 0], [92, 92, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255],
    ];
    return base[n];
  }
  if (n < 232) {
    const i = n - 16;
    const level = (v) => (v === 0 ? 0 : 55 + v * 40);
    return [level(Math.floor(i / 36)), level(Math.floor((i % 36) / 6)), level(i % 6)];
  }
  const v = 8 + (n - 232) * 10;
  return [v, v, v];
}

const hexToRgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const rgbToHex = (rgb) => "#" + rgb.map((v) => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, "0")).join("");

function rgbToHsl([r, g, b]) {
  const [R, G, B] = [r / 255, g / 255, b / 255];
  const max = Math.max(R, G, B);
  const min = Math.min(R, G, B);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === R) h = ((G - B) / d + (G < B ? 6 : 0)) / 6;
  else if (max === G) h = ((B - R) / d + 2) / 6;
  else h = ((R - G) / d + 4) / 6;
  return [h * 360, s, l];
}

function hslToRgb([h, s, l]) {
  const H = ((h % 360) + 360) % 360 / 360;
  if (s === 0) return [l * 255, l * 255, l * 255];
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const channel = (t) => {
    let T = t;
    if (T < 0) T += 1;
    if (T > 1) T -= 1;
    if (T < 1 / 6) return p + (q - p) * 6 * T;
    if (T < 1 / 2) return q;
    if (T < 2 / 3) return p + (q - p) * (2 / 3 - T) * 6;
    return p;
  };
  return [channel(H + 1 / 3) * 255, channel(H) * 255, channel(H - 1 / 3) * 255];
}

function luminance([r, g, b]) {
  const lin = (v) => {
    const c = v / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

function contrast(a, b) {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

// 保留原底色的明度、只注入色相与饱和度；若因明度钳制导致正文对比变差，
// 就把明度往远离正文的方向推回来，直到对比不低于原底色（或撞上绝对下限）。
// 最后还要和页面底拉开明度：多数主题的 toolSuccessBg 就等于页面底，只换色相的话，
// 块和页面底的对比是 1.0x，半透明终端里壁纸一冲色相就没了，块也就消失了。
function tint(base, fg, hue, isDark, page) {
  const [, , l0] = rgbToHsl(base);
  const sat = isDark ? SAT_DARK : SAT_LIGHT;
  const l1 = isDark ? Math.max(l0, MIN_L_DARK) : Math.min(l0, MAX_L_LIGHT);
  const want = fg ? Math.max(contrast(base, fg) * CONTRAST_KEEP, CONTRAST_FLOOR) : 0;
  let l = l1;
  let best = hslToRgb([hue, sat, l]);
  if (fg) {
    for (let step = 0; step <= 20; step++) {
      l = isDark ? l1 - step * 0.006 : l1 + step * 0.006;
      if (l < 0 || l > 1) break;
      best = hslToRgb([hue, sat, l]);
      if (contrast(best, fg) >= want) break;
    }
  }
  if (!page) return rgbToHex(best);
  for (let step = 0; step <= 30 && contrast(best, page) < TOOL_BG_MIN_RATIO; step++) {
    const lifted = isDark ? l + step * 0.008 : l - step * 0.008;
    if (lifted < 0 || lifted > 1) break;
    best = hslToRgb([hue, sat, lifted]);
  }
  return rgbToHex(best);
}

// 往页面底色混，混到对底色的对比度刚好落到 target 为止：取满足 target 的最大混合量，
// 这样「淡」的程度由对比度说了算，与主题原本的正文亮度无关。
function fadeToward(color, page, target) {
  const mix = (t) => color.map((c, i) => c + (page[i] - c) * t);
  let best = color;
  for (let t = 0.05; t <= 0.95; t += 0.05) {
    const next = mix(t);
    if (contrast(next, page) < target) break;
    best = next;
  }
  return rgbToHex(best);
}

// 中性分离：只沿明度轴走，不引入色相，直到和页面底拉开 USER_BG_MIN_RATIO。
// 暗色主题先往黑压（用户要的「黑块」），但页面底本身接近纯黑时压不出对比
// （tokyo-night 的 #16161e 压到底也只有 1.15），这时改为往白提；浅色主题方向相反，
// 先提亮，否则中灰块会把默认深色正文的对比吃掉。
function separateNeutral(color, page, amount, isDark) {
  const darker = (t) => color.map((c) => c * (1 - t));
  const lighter = (t) => color.map((c) => c + (255 - c) * t);
  const [primary, fallback] = isDark ? [darker, lighter] : [lighter, darker];
  let best = primary(amount);
  if (contrast(best, page) >= USER_BG_MIN_RATIO) return rgbToHex(best);
  // 主方向从 amount 起步（它就是「压多深」的意图），回退方向必须从最小步长起步，
  // 否则一上来就跨过目标，把暗块提成刺眼的亮带。
  for (const [step, start] of [[primary, amount], [fallback, 0.05]]) {
    for (let t = start; t <= 0.9; t += 0.05) {
      const candidate = step(t);
      if (contrast(candidate, page) >= USER_BG_MIN_RATIO) return rgbToHex(candidate);
      best = candidate;
    }
  }
  return rgbToHex(best);
}

function derive(theme, keepName = false) {
  const vars = theme.vars ?? {};
  const colors = theme.colors;
  const base =
    resolveValue(colors.toolSuccessBg, vars) ??
    resolveValue(colors.userMessageBg, vars) ??
    resolveValue(colors.selectedBg, vars) ??
    [26, 27, 38];
  const fg = resolveValue(colors.toolOutput, vars) ?? resolveValue(colors.muted, vars);
  const page = resolveValue(theme.export?.pageBg, vars) ?? base;
  const isDark = luminance(page) < 0.25;

  const successBg = tint(base, fg, SUCCESS_HUE, isDark, page);
  const errorBg = tint(base, fg, ERROR_HUE, isDark, page);
  // text 为空字符串（= 终端默认前景）时不碰它：omp 的 markdown 只给标题/链接/代码上色，
  // 助手正文段落不带 SGR，压暗正文的正确旋钮是终端前景色（见 omacosy 的 ghostty-fg-dim），
  // 在这里替一个 muted 进去只会把输入框单独压暗，还会在 muted 本身很暗的主题上把它压没。
  const textBase = resolveValue(colors.text, vars);
  const bodyText =
    textBase && TEXT_KEEP < 1
      ? fadeToward(textBase, page, Math.max(contrast(textBase, page) * TEXT_KEEP, TEXT_CONTRAST_FLOOR))
      : null;
  // 思考基于压暗后的正文算，否则正文一暗、两者的差距就被吃掉了
  const thinkingBase = resolveValue(colors.thinkingText, vars) ?? fg;
  const thinkingRef = bodyText ? hexToRgb(bodyText) : thinkingBase;
  const thinkingTarget = thinkingRef
    ? Math.max(contrast(thinkingRef, page) * THINKING_KEEP, THINKING_CONTRAST_FLOOR)
    : 0;
  const thinkingText = thinkingBase ? fadeToward(thinkingBase, page, thinkingTarget) : null;
  // 中性暗带：和页面底拉开层次，又不和染过色的工具块抢色相。去饱和后再分离，
  // 否则 osaka-jade 这类 surface 本身是绿色的主题，用户块会和成功块撞色
  const userRaw = resolveValue(colors.userMessageBg, vars);
  const userBase = userRaw && hslToRgb([0, 0, rgbToHsl(userRaw)[2]]);
  const userBg = userBase && USER_BG_DARKEN > 0 ? separateNeutral(userBase, page, USER_BG_DARKEN, isDark) : null;

  const next = structuredClone(theme);
  if (keepName === false) next.name = `${theme.name}${SUFFIX}`;
  next.colors.toolSuccessBg = successBg;
  next.colors.toolErrorBg = errorBg;
  if (thinkingText) next.colors.thinkingText = thinkingText;
  if (bodyText) next.colors.text = bodyText;
  if (userBg) next.colors.userMessageBg = userBg;
  return {
    theme: next,
    report: {
      name: next.name,
      mode: isDark ? "dark" : "light",
      base: rgbToHex(base),
      fg: fg ? rgbToHex(fg) : "(终端默认)",
      successBg,
      errorBg,
      baseContrast: fg ? contrast(base, fg).toFixed(2) : "-",
      userBg: userBg ?? "(未改)",
      userRatio: userBg ? contrast(hexToRgb(userBg), page).toFixed(2) : "-",
      successContrast: fg ? contrast(hexToRgb(successBg), fg).toFixed(2) : "-",
      errorContrast: fg ? contrast(hexToRgb(errorBg), fg).toFixed(2) : "-",
      bodyText: bodyText ?? "(未改)",
      bodyContrast: bodyText ? contrast(hexToRgb(bodyText), page).toFixed(2) : "-",
      thinkingText: thinkingText ?? "(未改)",
      thinkingContrast: thinkingText ? contrast(hexToRgb(thinkingText), page).toFixed(2) : "-",
      textContrast: textBase ? contrast(textBase, page).toFixed(2) : "-",
    },
  };
}

const argv = process.argv.slice(2);

// --key=<0..1>：取值、校验、并从待处理的主题名里摘掉
const flags = [];
function ratioFlag(name) {
  const raw = argv.find((a) => a.startsWith(`--${name}=`));
  if (!raw) return null;
  flags.push(raw);
  const value = Number(raw.slice(name.length + 3));
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    console.error(`--${name} 需要 0..1 之间的数: ${raw}`);
    process.exit(1);
  }
  return value;
}

const sat = ratioFlag("sat");
if (sat !== null) {
  // 浅色底本来就用更低的饱和度（同样的色相在白底上更扎眼），按默认比例跟着缩放
  SAT_DARK = sat;
  SAT_LIGHT = sat * (SAT_LIGHT_DEFAULT / SAT_DARK_DEFAULT);
}
const thinking = ratioFlag("thinking");
if (thinking !== null) THINKING_KEEP = thinking;
const text = ratioFlag("text");
if (text !== null) TEXT_KEEP = text;
const user = ratioFlag("user");
if (user !== null) USER_BG_DARKEN = user;

const fileArg = argv.find((a) => a.startsWith("--file="));
if (fileArg) {
  // 外部生成的主题（omacosy 的 tern-theme-fragment）原地派生，名字不变
  const path = fileArg.slice("--file=".length);
  const { theme } = derive(JSON.parse(readFileSync(path, "utf8")), true);
  writeFileSync(path, JSON.stringify(theme, null, 2) + "\n");
  process.exit(0);
}

const args = argv.filter((a) => !flags.includes(a));
const bin = ompBinary();
const buf = readFileSync(bin);
const available = builtinNames(buf);

if (args.length === 0 || args.includes("--help")) {
  console.log("用法: node derive-status-theme.mjs [--sat=0.3] [--thinking=0.2] [--text=0.5] [--user=0.45] <内置主题名>... | --all | --list");
  process.exit(args.length === 0 ? 1 : 0);
}
if (args.includes("--list")) {
  console.log(available.join("\n"));
  process.exit(0);
}

const targets = args.includes("--all") ? available : args;
const unknown = targets.filter((t) => !available.includes(t));
if (unknown.length) {
  console.error(`未知内置主题: ${unknown.join(", ")}\n可用: --list`);
  process.exit(1);
}

const themesDir = join(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".omp", "agent"), "themes");
if (!existsSync(themesDir)) mkdirSync(themesDir, { recursive: true });

const rows = [];
for (const name of targets) {
  const { theme, report } = derive(extractTheme(buf, name));
  writeFileSync(join(themesDir, `${theme.name}.json`), JSON.stringify(theme, null, 2) + "\n");
  rows.push(report);
}

const pad = (s, n) => String(s).padEnd(n);
console.log(
  pad("theme", 26), pad("mode", 6), pad("user", 9), pad("success", 9), pad("error", 9),
  pad("thinking", 9), "user/底  ok/err 对正文",
);
for (const r of rows) {
  console.log(
    pad(r.name, 26), pad(r.mode, 6), pad(r.userBg, 9), pad(r.successBg, 9), pad(r.errorBg, 9),
    pad(r.thinkingText, 9),
    `${r.userRatio}     ${r.successContrast}/${r.errorContrast}`,
  );
}
console.log(`\n写入 ${rows.length} 份到 ${themesDir}`);
console.log("启用：omp config set theme.dark <name>-status  /  theme.light <name>-status");
