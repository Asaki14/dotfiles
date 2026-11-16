'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { summarizeToday, navCountsToday } = require('./fission_fund_estimator');

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
    const result = spawnSync(process.execPath, [script], { encoding: 'utf8' });
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
  const result = spawnSync(process.execPath, [script, '--export'], { encoding: 'utf8' });
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
