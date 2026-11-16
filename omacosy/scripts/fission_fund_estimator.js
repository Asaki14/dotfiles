#!/usr/bin/env node
'use strict';

// 唯一持仓来源：本目录的 fission_fund_wallet.json（个人持仓，不入库；从 fission_fund_wallet.example.json 复制）；
// 缺失或无效时显示错误，不读取 Fishing Funds。
// 按实际持仓详情更新基金代码、名称和持有份额（cyfe），金额不能代替份额。
// 支付宝持仓不会自动同步。修改后重启 com.omacosy.bar，使休市期间也立即刷新。
// 不再支持 --export，避免旧应用钱包覆盖最新持仓。
// 今日合计排除上一净值；回归检查：node --test ~/.config/omacosy/scripts/fission_fund_estimator.test.js
// 006484 使用 159650（0-3年国开债）价格涨幅粗估；期限不同且含折溢价，不作股票仓位校准。
// 标的说明：https://www.bosera.com/fund/159650.html；正式净值发布后自动替换估算。

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CACHE_DIR = '/tmp/sketchybar_daemon';
const HOLDINGS_CACHE = path.join(CACHE_DIR, 'fission_fund_holdings.json');
const HOLIDAY_CACHE = path.join(CACHE_DIR, 'cn_holidays.json');
const MARKET_CACHE = path.join(CACHE_DIR, 'fission_fund_market_cache.json');
const DETAIL_CACHE = path.join(CACHE_DIR, 'fission_fund_detail.json');
const WALLET_FILE = path.join(__dirname, 'fission_fund_wallet.json');
const TZ = 'Asia/Shanghai';
const MARKET_OPEN_MINUTES = 9 * 60 + 30;
const PROXIES = {
  '006484': { secid: '0.159650', code: '159650', name: '博时0-3年国开债ETF', confidence: '低', defaultExposure: 1, calibrate: false, usePriceRate: true, note: '0-3年代理1-3年，期限与折溢价有误差，仅供盘中参考' },
  '021550': { secid: '0.159307', code: '159307', name: '博时红利低波100ETF', confidence: '高', defaultExposure: 0.95 },
  '008142': { secid: '1.518660', code: '518660', name: '工银黄金ETF', confidence: '高', defaultExposure: 0.95 },
  '022434': { secid: '0.159352', code: '159352', name: '南方A500ETF', confidence: '高', defaultExposure: 0.95 },
  '011839': { secid: '1.515070', code: '515070', name: '人工智能ETF', confidence: '中', defaultExposure: 0.95, note: '中证人工智能主题指数代理' },
  '007467': { secid: '1.512890', code: '512890', name: '华泰红利低波ETF', confidence: '高', defaultExposure: 0.95 },
  '012349': { secid: '1.520920', code: '520920', name: '天弘恒生科技ETF', confidence: '高', defaultExposure: 0.95 },
  '017091': { secid: '0.159509', code: '159509', name: '景顺纳指科技ETF', confidence: '低', defaultExposure: 0.95, qdii: true, note: '人民币ETF已内含隔夜美股与汇率，盘中价格另含折溢价' },
  '021740': { secid: '0.159812', code: '159812', name: '前海开源黄金ETF', confidence: '高', defaultExposure: 0.95 }
};


function readSyncedWallet() {
  const data = JSON.parse(fs.readFileSync(WALLET_FILE, 'utf8'));
  const valid = Array.isArray(data?.funds) && data.funds.every(fund =>
    /^\d{6}$/.test(String(fund?.code)) && typeof fund.name === 'string' && Number.isFinite(fund.cyfe) && fund.cyfe >= 0);
  if (!valid) throw new Error(`${path.basename(WALLET_FILE)} 格式无效`);
  return data;
}

function loadHoldings() {
  const source = 'sync';
  const funds = readSyncedWallet().funds;
  const key = crypto.createHash('sha1')
    .update(JSON.stringify([source, funds.map(fund => [fund.code, fund.cyfe])])).digest('hex').slice(0, 12);
  return { funds, source, key };
}

function summarizeToday(rows) {
  const usable = rows.filter(row => Number.isFinite(row.rate)
    && (row.valuationType === '今日估算' || row.valuationType === '今日净值'));
  const totalProfit = usable.reduce((sum, row) => sum + row.profit, 0);
  const totalBase = usable.reduce((sum, row) => sum + row.base, 0);
  const totalRate = totalBase ? totalProfit / totalBase * 100 : NaN;
  const types = new Set(usable.map(row => row.valuationType));
  const summaryType = !usable.length ? '不可用' : types.size === 1 ? [...types][0] : '今日混合';
  return { usable, totalProfit, totalRate, summaryType };
}

function dateInChina(value = new Date()) {
  return new Intl.DateTimeFormat('sv-SE', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(value);
}

function timeInChina(value = new Date()) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ, month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false
  }).formatToParts(value).filter(part => part.type !== 'literal').map(part => [part.type, part.value]));
  return `${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`;
}

function minutesInChina(value = new Date()) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: TZ, hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
  }).formatToParts(value).filter(part => part.type !== 'literal').map(part => [part.type, part.value]));
  return Number(parts.hour) * 60 + Number(parts.minute);
}

function weekdayInChina(value = new Date()) {
  return new Intl.DateTimeFormat('en-US', { timeZone: TZ, weekday: 'short' }).format(value);
}

function isWeekend(value = new Date()) {
  return ['Sat', 'Sun'].includes(weekdayInChina(value));
}

// A股法定节假日（NateScarlet/holiday-cn），按年缓存 7 天；拉取失败时退化为仅周末判断。
async function loadHolidays() {
  let cache = {};
  try { cache = JSON.parse(fs.readFileSync(HOLIDAY_CACHE, 'utf8')); } catch {}
  cache.years = cache.years || {};
  cache.fetchedAt = cache.fetchedAt || {};
  const year = Number(dateInChina().slice(0, 4));
  const month = Number(dateInChina().slice(5, 7));
  const wanted = month === 12 ? [year, year + 1] : [year];
  let dirty = false;
  for (const y of wanted) {
    if (cache.years[y] && Date.now() - Number(cache.fetchedAt[y] || 0) < 7 * 24 * 3600 * 1000) continue;
    for (const url of [
      `https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/${y}.json`,
      `https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/${y}.json`
    ]) {
      try {
        const json = JSON.parse(await fetchText(url, 10000));
        cache.years[y] = (json.days || []).filter(day => day.isOffDay).map(day => day.date);
        cache.fetchedAt[y] = Date.now();
        dirty = true;
        break;
      } catch {}
    }
  }
  if (dirty) try { fs.writeFileSync(HOLIDAY_CACHE, JSON.stringify(cache)); } catch {}
  return new Set(Object.values(cache.years).flat());
}

// 净值序列与日 K 线一天只变一次，按（中国）自然日缓存，把每轮常态请求压到 1 个实时行情。
function loadMarketCache() {
  try {
    const cache = JSON.parse(fs.readFileSync(MARKET_CACHE, 'utf8'));
    return { officials: cache.officials || {}, klines: cache.klines || {} };
  } catch { return { officials: {}, klines: {} }; }
}

function saveMarketCache(cache) {
  try { fs.writeFileSync(MARKET_CACHE, JSON.stringify(cache)); } catch {}
}

function nextTradingDayFrom(value, holidays) {
  for (let i = 1; i <= 30; i++) {
    const candidate = new Date(value.getTime() + i * 24 * 3600 * 1000);
    const date = dateInChina(candidate);
    if (!isWeekend(candidate) && !holidays.has(date)) return date;
  }
  return dateInChina(new Date(value.getTime() + 24 * 3600 * 1000));
}

function previousTradingDayFrom(value, holidays) {
  for (let i = 1; i <= 30; i++) {
    const candidate = new Date(value.getTime() - i * 24 * 3600 * 1000);
    const date = dateInChina(candidate);
    if (!isWeekend(candidate) && !holidays.has(date)) return date;
  }
  return dateInChina(new Date(value.getTime() - 24 * 3600 * 1000));
}

// 与支付宝口径一致：QDII 的 T 日净值在下一个 A 股交易日公布，并计入公布当天的收益；
// 其余基金的 T 日净值计入 T 日。
function navCountsToday(code, navDate, today, holidays) {
  if (!PROXIES[code]?.qdii) return navDate === today;
  return navDate >= previousTradingDayFrom(new Date(`${today}T12:00:00+08:00`), holidays);
}

function shortName(name) {
  const clean = String(name || '').replace(/ETF联接/g, '').replace(/\(QDII\)/g, '').replace(/人民币/g, '').replace(/\s+/g, '');
  return clean.length > 13 ? `${clean.slice(0, 12)}…` : clean;
}

function signed(value, digits = 2) {
  const n = Number(value);
  if (!Number.isFinite(n)) return '—';
  const text = Math.abs(n).toFixed(digits);
  return n > 0 ? `+${text}` : n < 0 ? `-${text}` : text;
}

function rowColor(value) {
  return value > 0 ? 'up' : value < 0 ? 'down' : 'flat';
}

// 东财接口有偶发连接抖动，默认重试 1 次；实时行情等关键请求传更大的 attempts。
async function fetchText(url, timeout = 10000, referer = 'https://fund.eastmoney.com/', attempts = 2) {
  let lastError;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(timeout),
        headers: { 'User-Agent': 'Mozilla/5.0', Referer: referer }
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}: ${url}`);
      return await response.text();
    } catch (error) {
      lastError = error;
      if (attempt < attempts - 1) await new Promise(resolve => setTimeout(resolve, 1000 + attempt * 500));
    }
  }
  throw lastError;
}

// 东财行情 CDN（push2 / push2his）的 DNS 池里时常混着坏节点，且 node 在进程内复用解析结果，
// 对同一域名重试会反复撞上同一个坏 IP。用随机编号子域轮换（官方前端同款负载均衡域名）绕开。
function balancedHosts(base) {
  const nums = new Set();
  while (nums.size < 5) nums.add(1 + Math.floor(Math.random() * 99));
  const hosts = [`${base}.eastmoney.com`, ...[...nums].map(n => `${n}.${base}.eastmoney.com`)];
  return hosts.map(host => [Math.random(), host]).sort((a, b) => a[0] - b[0]).map(([, host]) => host);
}

async function fetchTextRotating(makeUrl, hosts, timeout = 10000) {
  let lastError;
  for (const host of hosts) {
    try { return await fetchText(makeUrl(host), timeout, 'https://fund.eastmoney.com/', 1); }
    catch (error) { lastError = error; }
  }
  throw lastError;
}

function extractVariable(script, name) {
  const marker = `var ${name} = `;
  const start = script.indexOf(marker);
  if (start < 0) return null;
  const valueStart = start + marker.length;
  const end = script.indexOf(';', valueStart);
  if (end < 0) return null;
  try { return JSON.parse(script.slice(valueStart, end)); } catch { return null; }
}

async function fetchOfficial(fund) {
  const script = await fetchText(`https://fund.eastmoney.com/pingzhongdata/${fund.code}.js?v=${Date.now()}`, 12000);
  const trend = extractVariable(script, 'Data_netWorthTrend');
  const positions = extractVariable(script, 'Data_fundSharesPositions') || [];
  if (!Array.isArray(trend) || !trend.length) throw new Error('净值序列为空');
  const points = trend.filter(item => Number.isFinite(Number(item.y))).slice(-80);
  const latest = points.at(-1);
  const previous = points.at(-2);
  const date = dateInChina(new Date(Number(latest.x)));
  const nav = Number(latest.y);
  const previousNav = previous ? Number(previous.y) : nav;
  const rate = Number.isFinite(Number(latest.equityReturn))
    ? Number(latest.equityReturn)
    : (previousNav ? (nav / previousNav - 1) * 100 : 0);
  return {
    date, nav, previousNav, rate, points,
    stockExposure: positions.length ? Number(positions.at(-1)[1]) / 100 : null
  };
}

async function fetchQuotes(secids) {
  if (!secids.length) return new Map();
  const fields = 'f12,f13,f14,f2,f3,f4,f18,f124';
  const json = JSON.parse(await fetchTextRotating(
    host => `https://${host}/api/qt/ulist.np/get?fltt=2&invt=2&fields=${fields}&secids=${encodeURIComponent(secids.join(','))}&_=${Date.now()}`,
    balancedHosts('push2')));
  const map = new Map();
  for (const item of json?.data?.diff || []) {
    const timestamp = Number(item.f124);
    map.set(String(item.f12), {
      code: String(item.f12), name: item.f14, rate: Number(item.f3),
      price: Number(item.f2), previous: Number(item.f18),
      timestamp, date: Number.isFinite(timestamp) ? dateInChina(new Date(timestamp * 1000)) : '',
      time: Number.isFinite(timestamp) ? timeInChina(new Date(timestamp * 1000)) : ''
    });
  }
  return map;
}

async function fetchKlines(proxy) {
  const fields2 = 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61';
  const json = JSON.parse(await fetchTextRotating(
    host => `https://${host}/api/qt/stock/kline/get?secid=${proxy.secid}&klt=101&fqt=1&lmt=45&end=20500101&fields1=f1,f2,f3&fields2=${fields2}`,
    balancedHosts('push2his')));
  const map = new Map();
  for (const line of json?.data?.klines || []) {
    const cells = line.split(',');
    map.set(cells[0], Number(cells[8]));
  }
  return map;
}

function calibratedExposure(official, klines, proxy) {
  if (proxy.calibrate === false || proxy.qdii || !klines?.size) return { value: proxy.defaultExposure, calibrated: false };
  const pairs = official.points.map(point => {
    const date = dateInChina(new Date(Number(point.x)));
    return [Number(point.equityReturn), klines.get(date)];
  }).filter(([fundRate, proxyRate]) => Number.isFinite(fundRate) && Number.isFinite(proxyRate) && Math.abs(proxyRate) > 0.05);
  if (pairs.length < 8) return { value: proxy.defaultExposure, calibrated: false };
  const beta = pairs.reduce((sum, [y, x]) => sum + x * y, 0) / pairs.reduce((sum, [, x]) => sum + x * x, 0);
  if (!Number.isFinite(beta)) return { value: proxy.defaultExposure, calibrated: false };
  return { value: Math.max(0.80, Math.min(1.02, beta)), calibrated: true };
}

function parseHoldingRows(text) {
  const firstTable = text.match(/<table[^>]*>([\s\S]*?)<\/table>/i)?.[1] || '';
  const rows = [];
  for (const tr of firstTable.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const cells = [...tr[1].matchAll(/<td[^>]*>([\s\S]*?)<\/td>/gi)].map(match => match[1].replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim());
    const code = cells.find(cell => /^\d{6}$/.test(cell));
    const weightText = cells.find(cell => /^\d+(?:\.\d+)?%$/.test(cell));
    if (code && weightText) rows.push({ code, weight: Number(weightText.slice(0, -1)) / 100 });
    if (rows.length === 10) break;
  }
  const period = text.match(/(20\d{2})年([1-4])季度股票投资明细/)?.slice(1, 3);
  return { rows, period: period ? `${period[0]}Q${period[1]}` : '' };
}

async function fetchLatestHoldings() {
  try {
    const cached = JSON.parse(fs.readFileSync(HOLDINGS_CACHE, 'utf8'));
    if (Date.now() - Number(cached.updatedAt) < 24 * 3600 * 1000 && cached.rows?.length) return cached;
  } catch {}
  const now = new Date();
  const year = Number(new Intl.DateTimeFormat('en', { timeZone: TZ, year: 'numeric' }).format(now));
  const candidates = [];
  for (const y of [year, year - 1]) for (const month of [12, 9, 6, 3]) candidates.push([y, month]);
  for (const [y, month] of candidates) {
    try {
      const url = `https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=002834&topline=10&year=${y}&month=${month}`;
      const parsed = parseHoldingRows(await fetchText(url, 12000, 'https://fundf10.eastmoney.com/ccmx_002834.html'));
      if (parsed.rows.length >= 5) {
        const result = { ...parsed, updatedAt: Date.now() };
        fs.writeFileSync(HOLDINGS_CACHE, JSON.stringify(result));
        return result;
      }
    } catch {}
  }
  throw new Error('最新持仓不可用');
}

function resultFromRate(fund, official, rate, meta) {
  const shares = Number(fund.cyfe || 0);
  const isOfficial = meta.valuationType === '今日净值' || meta.valuationType === '上一净值';
  const profit = isOfficial
    ? shares * (official.nav - official.previousNav)
    : shares * official.nav * rate / 100;
  const base = isOfficial ? shares * official.previousNav : shares * official.nav;
  const label = `${signed(rate)}%  ${signed(profit)}`;
  return {
    code: fund.code, name: shortName(fund.name), rate, profit, base, label,
    color: rowColor(profit), navDate: official.date, ...meta
  };
}

async function estimatePassive(fund, official, quote, proxy, klines, today, navToday) {
  if (navToday) {
    return resultFromRate(fund, official, official.rate, {
      valuationType: '今日净值', confidence: '正式', source: `东方财富正式净值 ${official.date}`,
      dataTime: official.date, proxy: null, exposure: 1
    });
  }
  if (proxy.usePriceRate && quote && Number.isFinite(quote.price) && quote.price > 0
    && Number.isFinite(quote.previous) && quote.previous > 0) {
    quote = { ...quote, rate: (quote.price / quote.previous - 1) * 100 };
  }
  if (!quote || quote.date !== today || !Number.isFinite(quote.rate)) {
    return resultFromRate(fund, official, official.rate, {
      valuationType: '上一净值', confidence: '正式', source: `东方财富正式净值；实时代理不可用`,
      dataTime: official.date, proxy: proxy.code, exposure: null
    });
  }
  const exposure = calibratedExposure(official, klines, proxy);
  return resultFromRate(fund, official, quote.rate * exposure.value, {
    valuationType: '今日估算', confidence: proxy.confidence,
    source: `${proxy.name} ${proxy.code} × ${(exposure.value * 100).toFixed(0)}%${exposure.calibrated ? '（近45日校准）' : ''}${proxy.note ? `；${proxy.note}` : ''}`,
    dataTime: quote.time, proxy: proxy.code, proxyRate: quote.rate, exposure: exposure.value
  });
}

async function estimateActive(fund, official, holdings, quotes, today) {
  if (official.date === today) {
    return resultFromRate(fund, official, official.rate, {
      valuationType: '今日净值', confidence: '正式', source: `东方财富正式净值 ${official.date}`,
      dataTime: official.date, proxy: null, exposure: 1
    });
  }
  const available = holdings.rows.map(item => ({ ...item, quote: quotes.get(item.code) }))
    .filter(item => item.quote?.date === today && Number.isFinite(item.quote.rate));
  const coveredWeight = available.reduce((sum, item) => sum + item.weight, 0);
  if (available.length < 5 || coveredWeight <= 0) {
    return resultFromRate(fund, official, official.rate, {
      valuationType: '上一净值', confidence: '正式', source: '东方财富正式净值；持仓行情不足，未生成盘中估值',
      dataTime: official.date, proxy: null, exposure: null
    });
  }
  const representativeRate = available.reduce((sum, item) => sum + item.weight * item.quote.rate, 0) / coveredWeight;
  const stockExposure = Number.isFinite(official.stockExposure) ? Math.max(0, Math.min(1, official.stockExposure)) : 0.90;
  const rate = representativeRate * stockExposure;
  const latestTime = available.map(item => item.quote.time).sort().at(-1);
  return resultFromRate(fund, official, rate, {
    valuationType: '今日估算', confidence: '中',
    source: `${holdings.period || '最新'}前十大持仓归一加权 × ${(stockExposure * 100).toFixed(0)}%股票仓位测算；覆盖${available.length}/10`,
    dataTime: latestTime, proxy: '前十大持仓', exposure: stockExposure, holdingsCoverage: available.length
  });
}

async function main() {
  if (process.argv.length > 2) {
    console.error('不支持命令行参数；请直接更新 fission_fund_wallet.json 中的实际持仓份额。');
    process.exitCode = 1;
    return;
  }
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    const { funds, source: holdingsSource, key: holdingsKey } = loadHoldings();
    const now = new Date();
    const today = process.env.FISSION_FUND_TODAY || dateInChina(now);
    const todayNoon = new Date(`${today}T12:00:00+08:00`);
    const minutes = Number(process.env.FISSION_FUND_MINUTES || minutesInChina(now));
    const holidays = await loadHolidays();
    let marketStatus;
    if (isWeekend(todayNoon) || holidays.has(today)) marketStatus = 'closed';
    else if (minutes < MARKET_OPEN_MINUTES) marketStatus = 'pre-open';
    else marketStatus = 'open';

    const marketCache = loadMarketCache();

    // 官方净值当日缓存：净值只在傍晚更新一次。当天缓存里已是今日净值则直接用；
    // 否则 18:00 前也用缓存（盘中不会更新），18:00 后每轮重拉直到今日净值落地。
    const officialPairs = await Promise.all(funds.map(async fund => {
      const cached = marketCache.officials[fund.code];
      const sameDay = cached && cached.cachedDate === today;
      if (sameDay && (navCountsToday(fund.code, cached.data.date, today, holidays) || minutes < 18 * 60)) return [fund.code, cached.data];
      try {
        const data = await fetchOfficial(fund);
        marketCache.officials[fund.code] = { cachedDate: today, data };
        return [fund.code, data];
      } catch (error) {
        if (sameDay) return [fund.code, cached.data];
        return [fund.code, { error: error.message }];
      }
    }));
    const officials = new Map(officialPairs);

    let holdings = { rows: [], period: '' };
    try { holdings = await fetchLatestHoldings(); } catch {}
    const stockSecids = holdings.rows.map(item => `${item.code.startsWith('6') || item.code.startsWith('68') ? 1 : 0}.${item.code}`);
    const proxySecids = funds.map(fund => PROXIES[fund.code]?.secid).filter(Boolean);
    let quotes = new Map();
    try { quotes = await fetchQuotes([...new Set([...proxySecids, ...stockSecids])]); } catch {}

    // 节假日名单不可用时的兜底：开盘时间已过 15 分钟而交易所行情仍停留在上个交易日，说明今天休市。
    if (marketStatus === 'open' && minutes >= MARKET_OPEN_MINUTES + 15 && quotes.size
      && ![...quotes.values()].some(quote => quote.date === today)) {
      marketStatus = 'closed';
    }

    // 日 K 线当日缓存：只用于仓位校准，晚一天无感知；失败退回任意旧缓存。
    const klinePairs = await Promise.all(Object.entries(PROXIES).map(async ([code, proxy]) => {
      const cached = marketCache.klines[code];
      if (cached && cached.cachedDate === today) return [code, new Map(Object.entries(cached.data))];
      try {
        const map = await fetchKlines(proxy);
        marketCache.klines[code] = { cachedDate: today, data: Object.fromEntries(map) };
        return [code, map];
      } catch {
        return [code, cached ? new Map(Object.entries(cached.data)) : new Map()];
      }
    }));
    const klines = new Map(klinePairs);
    saveMarketCache(marketCache);

    const rows = await Promise.all(funds.map(async fund => {
      const official = officials.get(fund.code);
      if (!official || official.error) return {
        code: fund.code, name: shortName(fund.name), rate: null, profit: 0, base: 0,
        label: '获取失败', color: 'flat', valuationType: '不可用', confidence: '无',
        source: official?.error || '净值不可用', dataTime: '', navDate: ''
      };
      if (fund.code === '002834') return estimateActive(fund, official, holdings, quotes, today);
      const proxy = PROXIES[fund.code];
      if (!proxy) return resultFromRate(fund, official, official.rate, {
        valuationType: official.date === today ? '今日净值' : '上一净值', confidence: '正式', source: '未配置可靠盘中代理', dataTime: official.date
      });
      return estimatePassive(fund, official, quotes.get(proxy.code), proxy, klines.get(fund.code), today,
        navCountsToday(fund.code, official.date, today, holidays));
    }));

    rows.sort((a, b) => (Number.isFinite(b.rate) ? b.rate : -Infinity) - (Number.isFinite(a.rate) ? a.rate : -Infinity));
    // 旧净值仅保留在明细；今日合计及收益率分母只包含今日数据。
    const { usable, totalProfit, totalRate, summaryType } = summarizeToday(rows);
    const summaryDisplay = usable.length ? '今日' : '不可用';
    // 近 SPARK_DAYS 个交易日净值曲线；今日估算作为末点接在最近正式净值之后。
    const SPARK_DAYS = 20;
    const seriesByCode = new Map();
    for (const row of rows) {
      const official = officials.get(row.code);
      if (!official || official.error || !Array.isArray(official.points)) continue;
      const series = official.points.map(p => [dateInChina(new Date(Number(p.x))), Number(p.y)]);
      if (row.valuationType === '今日估算') {
        series.push([today, official.nav * (1 + row.rate / 100)]);
      }
      seriesByCode.set(row.code, series.slice(-SPARK_DAYS));
    }
    // 合计曲线：各基金按当前持仓金额折算，只取所有基金共有的日期。
    let totalSpark = [];
    const held = rows.filter(row => seriesByCode.has(row.code) && row.base > 0);
    if (held.length) {
      const common = held.map(row => new Set(seriesByCode.get(row.code).map(p => p[0])))
        .reduce((a, b) => new Set([...a].filter(d => b.has(d))));
      const dates = seriesByCode.get(held[0].code).map(p => p[0]).filter(d => common.has(d));
      totalSpark = dates.map(d => held.reduce((sum, row) => {
        const series = seriesByCode.get(row.code);
        return sum + row.base * series.find(p => p[0] === d)[1] / series.at(-1)[1];
      }, 0));
    }
    const displayRows = rows.map(row => ({
      name: row.name,
      label: row.label,
      color: row.color,
      rate: row.rate,
      profit: row.profit,
      spark: (seriesByCode.get(row.code) || []).map(p => p[1])
    })).slice(0, 16);

    // 主栏永不显示上一交易日的金额：休市显示「休息」，交易日开盘前显示「未开盘」，
    // 盘中拿不到任何今日数据时显示「—」。弹窗明细仍保留上一交易日数据供参考。
    let main = usable.length ? signed(totalProfit) : '—';
    let mainColor = rowColor(totalProfit);
    let summaryIcon = `${summaryDisplay} ${timeInChina().slice(6)}`;
    if (marketStatus === 'closed') {
      main = '休息'; mainColor = 'muted'; summaryIcon = '休息 · 上一交易日';
    } else if (marketStatus === 'pre-open') {
      main = '未开盘'; mainColor = 'muted'; summaryIcon = '未开盘 · 上一交易日';
    } else if (summaryType === '上一净值' || !usable.length) {
      // 行情连重试都失败时，30 分钟内沿用上一次成功的今日估算，避免主栏闪「—」。
      let previous = null;
      try { previous = JSON.parse(fs.readFileSync(DETAIL_CACHE, 'utf8')); } catch {}
      if (previous && previous.tradeDate === today
        && previous.holdingsKey === holdingsKey
        && String(previous.valuationType || '').includes('今日')
        && Date.now() - Date.parse(previous.fetchedAt || 0) < 30 * 60 * 1000) {
        process.stdout.write(JSON.stringify({ ...previous, staleReuse: true }));
        return;
      }
      main = '—'; mainColor = 'muted';
    }
    const nextTrading = marketStatus === 'closed' ? nextTradingDayFrom(todayNoon, holidays) : undefined;

    process.stdout.write(JSON.stringify({
      schemaVersion: 2, ok: usable.length > 0 || marketStatus !== 'open',
      fetchedAt: new Date().toISOString(), tradeDate: today,
      marketStatus, nextTradingDay: nextTrading, holdingsSource, holdingsKey,
      valuationType: summaryType, main,
      summary: usable.length ? `${signed(totalRate)}%  ${signed(totalProfit)}` : '无可靠数据',
      summaryIcon, color: mainColor,
      totalProfit, totalRate, totalSpark, rows, displayRows
    }));
  } catch (error) {
    process.stdout.write(JSON.stringify({
      schemaVersion: 2, ok: false, fetchedAt: new Date().toISOString(), main: '—',
      summary: '读取或估值失败', summaryIcon: '错误', color: 'flat', rows: [], displayRows: [], error: error.message
    }));
  }
}

module.exports = { loadHoldings, summarizeToday, navCountsToday };
if (require.main === module) main();
