// Appended to declarations extracted from helper/bar.swift by run-proxy-health.py.
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
    checks += 1
}

// delay results are keyed by the group's direct member, not the leaf node
expect(aiProbeHealth(selected: "Relay", delays: ["Relay": 120], status: 200) == .healthy, "direct member delay found")
expect(aiProbeHealth(selected: "Relay", delays: ["Leaf": 120], status: 200) == .failed, "leaf name is not the key")
expect(aiProbeHealth(selected: "Relay", delays: ["Relay": 0], status: 200) == .failed, "zero delay is a failure")
expect(aiProbeHealth(selected: nil, delays: nil, status: nil) == .unavailable, "no selection is unreadable")

// a failure needs a second failure on the same node
var c = AIFailureConfirmation()
expect(c.outcome(health: .failed, node: "A", confirming: nil, current: .healthy) == .retry(generation: 1), "first failure retries")
expect(c.outcome(health: .failed, node: "A", confirming: 1, current: .healthy) == .apply(.failed), "same node confirms")

c = AIFailureConfirmation()
_ = c.outcome(health: .failed, node: "A", confirming: nil, current: .healthy)
expect(c.outcome(health: .failed, node: "B", confirming: 1, current: .healthy) == .retry(generation: 2),
       "a switched node restarts the confirmation")
expect(c.outcome(health: .failed, node: "B", confirming: 1, current: .healthy) == .discard, "the old generation is stale")
expect(c.outcome(health: .failed, node: "B", confirming: 2, current: .healthy) == .apply(.failed), "restarted confirmation confirms")

c = AIFailureConfirmation()
_ = c.outcome(health: .failed, node: "A", confirming: nil, current: .healthy)
expect(c.outcome(health: .healthy, node: "A", confirming: nil, current: .healthy) == .apply(.healthy), "recovery applies")
expect(c.outcome(health: .failed, node: "A", confirming: 1, current: .healthy) == .discard, "recovery cancels the pending retry")

// groups: nested AI member keeps its own key; the Fallback group is found without a configured name
let proxies: [String: [String: Any]] = [
    "AI": ["type": "Selector", "now": "Relay", "all": ["Relay"]],
    "Relay": ["type": "Selector", "now": "SGP", "all": ["SGP"]],
    "SGP": ["type": "Trojan", "alive": true, "history": [["delay": 88]]],
    "Auto": ["type": "Fallback", "now": "JP2", "all": ["JP1", "JP2"]],
    "JP1": ["type": "Trojan", "alive": false, "history": [["delay": 0]]],
    "JP2": ["type": "Trojan", "alive": true, "history": [["delay": 140]]],
]
let groups = parseProxyGroups(proxies)
expect(groups.count == 2, "two groups")
expect(groups[0].nodes.first?.key == "Relay" && groups[0].nodes.first?.name == "SGP", "nested member keeps key and leaf")
expect(groups[0].nodes.first?.delay == 88, "leaf delay")
expect(groups[1].nodes.map(\.name) == ["JP2"], "automatic group lists only its current node")
expect(groups[1].nodes.first?.delay == 140, "current node delay")
print("proxy-health: \(checks) checks passed")
