--!strict
local home = tern.getenv("HOME")
if home == nil then
	return
end
local fragment = home .. "/.local/bin/tern-theme-fragment"
local css_path = home .. "/.omp/agent/themes/omacosy.tern.css"
local css: string? = nil

local function apply(cx: WindowCx)
	cx.settings:set_many({
		theme = "System",
		theme_dark = "omacosy",
		theme_light = "omacosy",
		material = "Clear",
	})
	local source = ""
	if tern.fs.exists(css_path) then
		source = tern.fs.read(css_path)
	end
	if css ~= source then
		tern.css("palette", source)
		css = source
	end
end

tern.command({
	id = "refresh",
	title = "Refresh desktop theme",
	run = apply,
})

tern.timer(0, function(cx: WindowCx?)
	if cx ~= nil then
		apply(cx)
	end
end)

tern.on("window_start", function(_: WindowCx)
	tern.timer(0, function(_: WindowCx?)
		tern.process.run({ fragment }, { timeout_ms = 30000, env = { TERN_THEME_NO_RELOAD = "1" } }, function(result: ProcessResult, cx: WindowCx?)
			if result.status ~= 0 then
				tern.log.warn("omacosy-theme: render failed", result.stderr)
			elseif cx ~= nil then
				apply(cx)
			end
		end)
	end)
end)
