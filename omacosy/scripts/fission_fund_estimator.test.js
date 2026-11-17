'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { summarizeToday, navCountsToday, returnDate, summarizeRecent, resultFromRate } = require('./fission_fund_estimator');

function isolated(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fund-regression-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const script = path.join(dir, 'fission_fund_estimator.js');
  fs.copyFileSync(path.join(__dirname, 'fission_fund_estimator.js'), script);
  return { dir, script, wallet: path.join(dir, 'fission_fund_wallet.json') };
}

test('missing or invalid wallet fails without returning old holdings', t => {
  const { script, wallet } = isolated(t);
  for (const content of [null, '{', '{"funds":[{"code":"006484","name":"债基","cyfe":-1}]}']) {
    if (content !== null) fs.writeFileSync(wallet, content);
    const result = spawnSync(process.execPath, [script], { encoding: 'utf8', env: { ...process.env, HOME: path.dirname(script) } });
    const data = JSON.parse(result.stdout);
    assert.equal(data.ok, false);
    assert.equal(data.main, '—');
    assert.deepEqual(data.rows, []);
    assert.equal(typeof data.error, 'string');
  }
});

test('legacy export cannot overwrite an existing wallet', t => {
  const { script, wallet } = isolated(t);
  const original = '{"funds":[{"code":"006484","name":"债基","cyfe":1000}]}';
  fs.writeFileSync(wallet, original);
  const result = spawnSync(process.execPath, [script, '--export'], { encoding: 'utf8', env: { ...process.env, HOME: path.dirname(script) } });
  assert.equal(result.status, 1);
  assert.equal(fs.readFileSync(wallet, 'utf8'), original);
});

test('today total excludes prior NAV profit and principal without removing details', () => {
  const rows = [
    { valuationType: '今日估算', rate: 2, profit: 20, base: 1000 },
    { valuationType: '今日净值', rate: -1, profit: -5, base: 500 },
    { valuationType: '上一净值', rate: 1, profit: 250, base: 25000 }
  ];
  const result = summarizeToday(rows);
  assert.equal(result.totalProfit, 15);
  assert.equal(result.totalRate, 1);
  assert.equal(result.summaryType, '今日混合');
  assert.equal(rows[2].profit, 250);
  assert.equal(summarizeToday([rows[2]]).summaryType, '不可用');
  assert.equal(summarizeToday([rows[2]]).totalProfit, 0);
});

test('QDII NAV counts on the next A-share trading day, like Alipay', () => {
  const holidays = new Set();
  // 017091 的 11-05（周四）净值在 11-06（周五）公布并计入当日。
  assert.equal(navCountsToday('017091', '2026-11-05', '2026-11-06', holidays), true);
  assert.equal(navCountsToday('017091', '2026-11-04', '2026-11-06', holidays), false);
  // 周五净值计入下周一。
  assert.equal(navCountsToday('017091', '2026-11-06', '2026-11-09', holidays), true);
  // 非 QDII 只认当日净值。
  assert.equal(navCountsToday('021550', '2026-11-05', '2026-11-06', holidays), false);
  assert.equal(navCountsToday('021550', '2026-11-06', '2026-11-06', holidays), true);
});

const fund = (code = '021550', cyfe = 100) => ({ code, name: code, cyfe });
const point = (date, y, equityReturn) => ({
  x: Date.parse(`${date}T00:00:00+08:00`), y, equityReturn
});
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-8, `${actual} != ${expected}`);

test('historical profit and percentage use the same dates and opening holdings value', () => {
  const officials = new Map([
    ['021550', { points: [point('2026-11-12', 1), point('2026-11-13', 1.01), point('2026-11-16', 1.02)] }],
    ['008142', { points: [point('2026-11-12', 2), point('2026-11-13', 1.99), point('2026-11-16', 2.01)] }]
  ]);
  const recent = summarizeRecent([fund(), fund('008142', 200)], officials, [], '2026-11-16', new Set(), 'open');
  assert.deepEqual(recent.dates, ['2026-11-13', '2026-11-16']);
  close(recent.profit, 4);
  close(recent.rate, 0.8);
  close(recent.rows.find(row => row.code === '021550').rate, 2);
  close(recent.rows.find(row => row.code === '008142').rate, 0.5);
  close(recent.values.at(-1), recent.rows.reduce((sum, row) => sum + row.profit, 0));
});

test('today estimate appends once and official dividend return supersedes it', () => {
  const points = [point('2026-11-13', 2), point('2026-11-16', 2.02)];
  const officials = new Map([['021550', { points }]]);
  const rows = [{ code: '021550', valuationType: '今日估算', profit: 5, base: 202 }];
  const estimated = summarizeRecent([fund()], officials, rows, '2026-11-17', new Set(), 'open');
  assert.deepEqual(estimated.dates, ['2026-11-16', '2026-11-17']);
  close(estimated.profit, 7);
  close(estimated.rate, 3.5);
  assert.equal(estimated.estimated, true);
  points.push(point('2026-11-17', 1.9, 1));
  const official = summarizeRecent([fund()], officials, rows, '2026-11-17', new Set(), 'open');
  close(official.profit, 4.02);
  assert.equal(official.estimated, false);
  assert.equal(official.dates.length, 2);
});

test('history is capped at twenty shared trading dates and missing funds are not zero', () => {
  const points = [];
  for (let date = new Date('2026-10-01T12:00:00Z'); date <= new Date('2026-11-17T12:00:00Z'); date.setUTCDate(date.getUTCDate() + 1)) {
    if ([0, 6].includes(date.getUTCDay())) continue;
    points.push(point(date.toISOString().slice(0, 10), 1 + points.length / 100));
  }
  const officials = new Map([['021550', { points }]]);
  const recent = summarizeRecent([fund()], officials, [], '2026-11-17', new Set(), 'open');
  assert.equal(recent.dates[0], '2026-10-21');
  assert.equal(recent.dates.at(-1), '2026-11-17');
  close(recent.profit, 20);
  const missing = summarizeRecent([fund(), fund('008142')], officials, [], '2026-11-17', new Set(), 'open');
  assert.equal(missing.profit, null);
  assert.equal(missing.rate, null);
});

test('QDII aligns Friday NAV to Monday without duplication or future leakage', () => {
  const officials = new Map([
    ['017091', { points: [point('2026-11-05', 2), point('2026-11-06', 2.1, 5)] }],
    ['021550', { points: [point('2026-11-06', 1), point('2026-11-09', 1.01, 1)] }]
  ]);
  const recent = summarizeRecent([fund('017091'), fund()], officials, [], '2026-11-10', new Set(), 'open');
  assert.deepEqual(recent.dates, ['2026-11-09']);
  close(recent.profit, 11);
  close(recent.rate, 11 / 300 * 100);
  assert.equal(summarizeRecent([fund('017091')], officials, [], '2026-11-06', new Set(), 'open').profit, null);
  assert.equal(returnDate('017091', '2026-11-06', new Set(['2026-11-09'])), '2026-11-10');
});

test('today official profit includes dividend-adjusted return', () => {
  const row = resultFromRate(fund(), { nav: 1.9, previousNav: 2, date: '2026-11-16' },
    1, { valuationType: '今日净值' });
  assert.equal(row.profit, 2);
  assert.equal(row.base, 200);
});
