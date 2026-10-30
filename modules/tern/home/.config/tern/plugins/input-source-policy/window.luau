--!strict
-- input-source-policy: picks the macOS input source from what the focused Tern
-- pane runs.
--
--   title starts with an ASCII app (yazi, dooit, rmpc) -> ascii (US Extended)
--   an agent block (PaneInfo.kind == "agent")          -> cjk (remembered source)
--   anything else                                      -> ascii
--
-- The ASCII-app check runs first, so a TUI stays ASCII whatever else the pane
-- reports. Agent detection uses Tern's block kind, not the title: Tern marks
-- every agent block (native omp, firstmate's launch scripts, PI_TUI_NATIVE=0
-- workers) as kind "agent", while yazi/rmpc report their shell as `program`.
--
-- Event-driven: `focus` and `title` feed an edge detector, nothing polls. The
-- policy applies only when the focused (pane, class) pair changes — a new pane
-- got focus, or the focused pane's class changed in place (yazi launched or
-- quit). Agent spinners retitle about twice a second; those title events keep
-- the class, so they never re-apply and a manual switch to US Extended inside an agent
-- pane sticks.
--
-- A pair only counts once it has held for SETTLE_MS. Programmatic focus blips
-- (focus a tab, act, restore) are shorter than any real switch, and following
-- them flapped the input source under the user's hands.
--
-- The switch itself is scripts/input-source-policy (Swift, src/main.swift),
-- which selects, verifies after TIS settles, retries once and traces to
-- ~/.local/state/tern-input-source-policy/policy.log.

local SETTLE_MS = 700
local POLICY = tern.plugin.dir .. "/scripts/input-source-policy"

--- Terminal titles of keyboard-driven TUIs that must always type ASCII, matched
--- case-insensitively as the whole title or a prefix followed by `:` or a space:
--- "dooit ~", "Yazi: Downloads", "rmpc ~".
local ASCII_APPS = { "yazi", "dooit", "rmpc" }

type Focus = { pane: number, reason: string, desired: "ascii" | "cjk" }

local applied: Focus? = nil
local candidate: Focus? = nil
local settle_timer: TimerHandle? = nil
local running = false
local queued: Focus? = nil

local function ascii_app(title: string): string?
	local lowered = string.lower(title)
	for _, name in ASCII_APPS do
		if string.sub(lowered, 1, #name) == name then
			local rest = string.sub(lowered, #name + 1, #name + 1)
			if rest == "" or rest == ":" or rest == " " then
				return name
			end
		end
	end
	return nil
end

local function classify(p: PaneInfo): Focus
	local app = ascii_app(p.title)
	if app ~= nil then
		return { pane = p.pane, reason = app, desired = "ascii" }
	end
	if p.kind == "agent" then
		return { pane = p.pane, reason = "agent", desired = "cjk" }
	end
	return { pane = p.pane, reason = "other", desired = "ascii" }
end

local function same(a: Focus?, b: Focus?): boolean
	return a ~= nil and b ~= nil and a.pane == b.pane and a.reason == b.reason
end

-- Scans panes() rather than calling cx.session:pane(id): in Tern 0.8.3 pane(id)
-- returns nil for some focused blocks (seen for a tab opened with `tern new
-- tab`) that panes() does list, and the focus edge would be lost.
local function focused(cx: WindowCx): Focus?
	local id = cx.session:focused()
	if id == nil then
		return nil
	end
	for _, p in cx.session:panes() do
		if p.pane == id then
			return classify(p)
		end
	end
	return nil
end

-- One switch at a time: a switch takes ~300-600 ms (verify and retry), and two
-- overlapping ones could finish in either order. The latest edge waits instead.
local function run(f: Focus)
	if running then
		queued = f
		return
	end
	running = true
	local argv = { POLICY, f.desired, "--pane", tostring(f.pane), "--reason", f.reason }
	local ok, err = pcall(tern.process.run, argv, { timeout_ms = 60000 }, function(result: ProcessResult, _cx: WindowCx?)
		running = false
		if result.status ~= 0 then
			tern.log.warn("input-source-policy: switch failed", f.desired, result.status, result.stderr)
		end
		local nxt = queued
		queued = nil
		if nxt ~= nil then
			run(nxt)
		end
	end)
	if not ok then
		running = false
		tern.log.warn("input-source-policy: spawn failed", err)
	end
end

local settled: (cx: WindowCx?) -> ()

local function observe(f: Focus?)
	if f == nil or same(f, candidate) then
		return
	end
	candidate = f
	if settle_timer ~= nil then
		settle_timer:cancel()
	end
	settle_timer = tern.timer(SETTLE_MS, settled)
end

settled = function(cx: WindowCx?)
	settle_timer = nil
	if cx == nil then
		return
	end
	local f = focused(cx)
	if f == nil then
		return
	end
	if not same(f, candidate) then
		-- Moved again without an event reaching us: settle on the new pair.
		observe(f)
		return
	end
	if same(f, applied) then
		-- Focus left and came back within the settle window: a blip.
		return
	end
	applied = f
	-- The spawn gets its own timer call: Tern disables a plugin's timer once a
	-- call runs past its budget, and a spawn alone can take tens of ms.
	tern.timer(0, function(_cx: WindowCx?)
		run(f)
	end)
end

tern.on("focus", function(_ev: FocusEvent, cx: WindowCx)
	observe(focused(cx))
end)

tern.on("title", function(ev: TitleEvent, cx: WindowCx)
	if cx.session:focused() ~= ev.pane then
		return
	end
	observe(focused(cx))
end)

-- Load (also a reload, which does not re-run window_start) applies the policy
-- once for whatever is focused now.
tern.timer(0, function(cx: WindowCx?)
	if cx ~= nil then
		observe(focused(cx))
	end
end)
