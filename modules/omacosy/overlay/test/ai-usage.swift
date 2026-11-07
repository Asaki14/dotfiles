// Appended to declarations extracted from helper/bar.swift by run-ai-usage.py.
let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
let aiCacheDir = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("cache")
let aiStaleAfter: TimeInterval = 900
try FileManager.default.createDirectory(at: aiCacheDir, withIntermediateDirectories: true)
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
    checks += 1
}
func cache(_ provider: String, _ usage: [String: Any]) throws {
    try JSONSerialization.data(withJSONObject: [["usage": usage]])
        .write(to: aiCacheURL(provider), options: .atomic)
}
func fixture(_ provider: String) throws -> [String: Any] {
    let data = try Data(contentsOf: fixtures.appendingPathComponent("\(provider).json"))
    try data.write(to: aiCacheURL(provider), options: .atomic)
    return aiCachedUsage(provider)!
}
func signature(_ row: AIRow) -> String {
    [row.target, row.iconColor, row.labelColor, row.left, row.right].joined(separator: "\t")
}
let pro = try fixture("codex")
let now = ISO8601DateFormatter().date(from: "2026-09-08T04:02:18Z")!
expect(aiPrimary("codex")?.pct == 0, "Pro weekly zero is a real reading, not nil")
expect(aiPrimary("codex")?.stale == false, "fresh weekly cache")
let proRows = aiCodexRows(pro, now: now)
expect(proRows.count == 3, "Pro header, weekly window and reset credits")
expect(proRows[0].right == "Codex  ·  Pro", "friendly Pro title")
expect(proRows[1].left == "7d", "actual duration, no phantom 5h")
expect(proRows[1].right == "░░░░░░░░░░░░ 0%  ↻6d23h", "weekly gauge and reset")
expect(proRows[2].left == "重置机会"
       && proRows[2].right == "3 次可用 · 最近到期 12d20h",
       "fixture reset credit count and earliest expiry")
expect(aiPillLabel(pro) == "—", "weekly-only pill has no 5h window")
let oldRows = """
sep	MUTED	MUTED	ON	●
title	TEXT	TEXT	●	Claude
c.1	MUTED	TEXT	5h	░░░░░░░░░░░░ 1%  ↻4h57m
c.2	MUTED	TEXT	7d	████░░░░░░░░ 30%  ↻6d0h
c.3	MUTED	TEXT	Fable	████░░░░░░░░ 37%  ↻6d0h
c.4	MUTED	MUTED	__OFF__	●
head2	TEXT	TEXT	●	Codex  ·  Self_serve_business_prolite
x.1	MUTED	TEXT	5h	bogus old slot
x.2	MUTED	TEXT	7d	bogus old slot
not a TSV row
"""
let parsed = aiParsedUsage(oldRows)
expect(parsed.codex?.pct == 0, "bar pill reads the personal Codex account")
expect(parsed.rows.map(\.target) == ["title", "head2", "x.1", "x.2"],
       "script Claude slots ignored; uncached Claude is one unavailable head")
expect(parsed.rows[0].right == "Claude 用量暂不可用" && parsed.claude == nil
       && parsed.claudeLabel == "—", "missing Claude cache is unavailable, not zero")

let claude = try fixture("claude")
let claudeRows = aiClaudeRows(claude, now: now)
expect(claudeRows.map(\.left) == ["", "5h", "7d", "Fable only"], "Claude windows and scoped title")
expect(claudeRows[0].right == "Claude", "no plan, no dangling separator")
expect(claudeRows[1].right == "░░░░░░░░░░░░ 1%  ↻4h57m", "Claude 5h gauge and reset")
expect(aiPillLabel(claude) == "5h 1%", "Claude pill shows only the 5h window")
var claudePro = claude
claudePro["loginMethod"] = "Claude Pro"
expect(aiClaudeRows(claudePro)[0].right == "Claude  ·  Pro", "brand prefix trimmed from plan")
let both = aiParsedUsage(oldRows)
expect(both.rows.map(\.target) == ["title", "c.1", "c.2", "c.3", "head2", "x.1", "x.2"],
       "Claude section first, from the cache rather than the script")
expect(both.claude?.pct == 1 && both.claude?.stale == false && both.claudeLabel == "5h 1%",
       "Claude pill segment")
try FileManager.default.removeItem(at: aiCacheURL("claude"))

try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-901)],
                                      ofItemAtPath: aiCacheURL("codex").path)
expect(aiPrimary("codex")?.pct == 0 && aiPrimary("codex")?.stale == true, "weekly fallback keeps stale flag")

var dual = pro
dual.removeValue(forKey: "codexResetCredits")
let short: [String: Any] = ["usedPercent": 61.9, "windowMinutes": 300]
dual["primary"] = short
dual["loginMethod"] = "Codex Plus"
try cache("codex", dual)
expect(aiPrimary("codex")?.pct == 61, "primary wins on normal dual-window plan")
let dualRows = aiCodexRows(dual, now: now)
expect(aiPillLabel(dual) == "5h 61%", "pill shows only the 5h window")
expect(dualRows[0].right == "Codex  ·  Plus", "legacy plan trimming preserved")
expect(dualRows[1].labelColor == "GOLD", "warning threshold")
var withResetCredits = dual
withResetCredits["codexResetCredits"] = [
    "credits": [
        ["reset_type": "codex_rate_limits", "status": "available",
         "expires_at": "2026-09-15T04:01:17Z"],
        ["reset_type": "codex_rate_limits", "status": "available",
         "expires_at": "2026-10-04T02:22:38Z"],
        ["reset_type": "codex_rate_limits", "status": "used",
         "expires_at": "2026-09-10T00:00:00Z"],
        ["reset_type": "other", "status": "available",
         "expires_at": "2026-09-10T00:00:00Z"]
    ]
]
let resetRows = aiCodexRows(withResetCredits, now: now)
expect(resetRows.last?.left == "重置机会"
       && resetRows.last?.right == "2 次可用 · 最近到期 6d23h",
       "available Codex reset credits and nearest expiry")
var claudeWithResets = claude
claudeWithResets["claudeResetCredits"] = [
    "credits": [
        ["reset_type": "claude_rate_limits", "status": "available",
         "expires_at": "2026-09-15T04:01:17Z"],
        ["reset_type": "claude_rate_limits", "status": "redeemed",
         "expires_at": "2026-09-10T00:00:00Z"],
        ["reset_type": "codex_rate_limits", "status": "available",
         "expires_at": "2026-09-10T00:00:00Z"]
    ]
]
let claudeResetRows = aiClaudeRows(claudeWithResets, now: now)
expect(claudeResetRows.last?.left == "重置机会"
       && claudeResetRows.last?.right == "1 次可用 · 最近到期 6d23h",
       "available Claude reset credits counted by type and status")
expect(aiClaudeRows(claude, now: now).allSatisfy { $0.left != "重置机会" },
       "no Claude reset row without credits")
claudeWithResets["claudeResetCredits"] = [
    "credits": [
        ["reset_type": "claude_rate_limits", "status": "available", "remaining_count": 3,
         "expires_at": "2026-09-15T04:01:17Z"]
    ]
]
expect(aiClaudeRows(claudeWithResets, now: now).last?.right == "3 次可用 · 最近到期 6d23h",
       "one Claude grant with remainingCount 3 counts as 3")
dual["secondary"] = NSNull()
expect(aiWindows(dual).map(\.name) == ["5h"], "primary-only plan")
dual["primary"] = ["usedPercent": 81, "windowMinutes": 120]
dual["tertiary"] = ["usedPercent": 60, "windowMinutes": 90]
dual["extraRateWindows"] = [["title": "Review", "window": ["usedPercent": 100, "windowMinutes": 10080]]]
let dynamicRows = aiCodexRows(dual, now: now)
expect(dynamicRows.map(\.left) == ["", "2h", "90m", "Review"], "dynamic durations and scoped titles, no two-slot cap")
expect(dynamicRows[1].labelColor == "LOVE" && dynamicRows[2].labelColor == "TEXT", "red and neutral thresholds")
expect(dynamicRows[3].right == "████████████ 100%", "full gauge without invented reset")

for bad: Any in [NSNull(), "oops", true, -1, 101, Double.nan, Double.infinity] {
    var invalid = pro
    invalid["primary"] = ["usedPercent": bad]
    expect(aiWindows(invalid).map(\.name) == ["7d"], "invalid primary must not hide a valid weekly window")
}
expect(aiWindows(["primary": ["usedPercent": 12]]).first?.name == "Primary", "unknown duration is not labelled 5h")
var pillWindows = dual
pillWindows["primary"] = short
pillWindows.removeValue(forKey: "tertiary")
pillWindows.removeValue(forKey: "extraRateWindows")
pillWindows["secondary"] = NSNull()
expect(aiPillLabel(pillWindows) == "5h 61%", "pill unaffected by missing weekly window: \(aiPillLabel(pillWindows))")
pillWindows["primary"] = NSNull()
pillWindows["tertiary"] = ["usedPercent": 45, "windowMinutes": 90]
expect(aiPillLabel(pillWindows) == "—", "unrequested durations are not mislabeled")
var nested = pro
nested.removeValue(forKey: "loginMethod")
expect(aiCodexRows(nested)[0].right == "Codex  ·  Pro", "nested identity plan")
expect(aiCodexRows([:]).count == 1 && aiCodexRows(nil)[0].labelColor == "MUTED", "missing usage is unavailable, not zero")
try cache("codex", [:])
expect(aiPrimary("codex") == nil && aiParsedUsage(oldRows).rows.count == 2,
       "no windows clears Codex reading and stale provider rows")
try Data("not JSON".utf8).write(to: aiCacheURL("codex"))
expect(aiPrimary("codex") == nil, "malformed cache is unavailable")
try FileManager.default.removeItem(at: aiCacheURL("codex"))
expect(aiPrimary("codex") == nil, "absent cache is unavailable")
print("PASS: \(checks) AI usage checks")
