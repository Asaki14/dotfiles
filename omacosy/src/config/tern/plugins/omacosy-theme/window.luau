--!strict
-- Daytime preferences belong to Tern's theme picker, not the desktop palette.
local home = tern.getenv("HOME")
if home == nil then
	return
end
local fragment = home .. "/.local/bin/tern-theme-fragment"
local css_path = home .. "/.omp/agent/themes/omacosy.tern.css"
local applied: string? = nil
local css: string? = nil
local mode: string? = nil

local function profile(cx: WindowCx): any
	return {
		theme = cx.settings:get("theme"),
		theme_dark = cx.settings:get("theme_dark") or tern.json.null,
		theme_light = cx.settings:get("theme_light") or tern.json.null,
	}
end

local function remember(cx: WindowCx)
	local current = profile(cx)
	local saved = tern.kv.get("day")
	if saved == nil or current.theme ~= saved.theme
		or current.theme_dark ~= saved.theme_dark or current.theme_light ~= saved.theme_light then
		tern.kv.set("day", current)
	end
end

local function apply(cx: WindowCx, next_mode: string)
	local previous = tern.kv.get("active_mode")
	if tern.kv.get("day") == nil then
		remember(cx)
	end
	if previous == "day" and next_mode == "night" then
		remember(cx)
	end
	if previous ~= next_mode then
		if next_mode == "day" then
			cx.settings:set_many(tern.kv.get("day"))
		else
			cx.settings:set_many({ theme = "System", theme_dark = "omacosy", theme_light = "omacosy" })
		end
		tern.kv.set("active_mode", next_mode)
	end
	local material = if next_mode == "day" then "Solid" else "Clear"
	if cx.settings:get("material") ~= material then
		cx.settings:set("material", material)
	end
	local density = if next_mode == "day" then "Compact" else "Islands"
	if cx.settings:get("density") ~= density then
		cx.settings:set("density", density)
	end
	mode = next_mode
	if next_mode == "day" then
		remember(cx)
	end
	local source = ""
	if next_mode == "night" and tern.fs.exists(css_path) then
		source = tern.fs.read(css_path)
	end
	if css ~= source or applied ~= next_mode then
		tern.css("palette", source)
		css = source
		applied = next_mode
	end
end

local function check()
	tern.process.run({ "/bin/date", "+%H%M%S" }, { timeout_ms = 5000 }, function(result: ProcessResult, cx: WindowCx?)
		if result.status ~= 0 or cx == nil then
			tern.log.warn("omacosy-theme: cannot read local time", result.stderr)
			tern.timer(1000, check)
			return
		end
		local h, m, s = string.match(result.stdout, "(%d%d)(%d%d)(%d%d)")
		if h == nil or m == nil or s == nil then
			tern.log.warn("omacosy-theme: invalid local time", result.stdout)
			tern.timer(1000, check)
			return
		end
		local seconds = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
		apply(cx, if seconds >= 28800 and seconds < 70200 then "day" else "night")
		-- Recheck the wall clock after sleep or a timezone change, and land on the boundary.
		local boundary = if seconds < 28800 then 28800 else if seconds < 70200 then 70200 else 115200
		tern.timer(math.min(30000, (boundary - seconds) * 1000), check)
	end)
end

tern.command({
	id = "refresh",
	title = "Refresh scheduled desktop theme",
	run = function(cx: WindowCx)
		-- The desktop renderer only refreshes the night palette. Never pins daytime themes.
		if mode ~= nil then
			apply(cx, mode)
		end
	end,
})

local function observe(cx: WindowCx?)
	if cx ~= nil and mode == "day" and tern.kv.get("active_mode") == "day" then
		remember(cx)
	end
	tern.timer(1000, observe)
end

tern.timer(0, check)
tern.timer(1000, observe)
tern.on("window_start", function(_: WindowCx)
	tern.timer(0, function(_: WindowCx?)
		tern.process.run({ fragment }, { timeout_ms = 30000, env = { TERN_THEME_NO_RELOAD = "1" } }, function(result: ProcessResult, cx: WindowCx?)
			if result.status ~= 0 then
				tern.log.warn("omacosy-theme: render failed", result.stderr)
			elseif cx ~= nil and mode ~= nil then
				apply(cx, mode)
			end
		end)
	end)
end)
