--!strict
-- omacosy-theme: re-runs tern-theme-fragment once per Tern window start.
--
-- After a Tern restart the terminal palette has been seen back on omp's
-- config.yml theme, leaving plain-ANSI programs off the desktop
-- palette until the next theme-set. Running the fragment here re-renders
-- ~/.omp/agent/themes/omacosy.json from the current omarchy palette (that file is
-- also synced between machines, so it may hold the other machine's theme) and
-- pins it again, without touching config.yml.

local home = tern.getenv("HOME")
if home == nil then
	tern.log.warn("omacosy-theme: HOME is unset, theme not re-applied")
	return
end
local FRAGMENT = home .. "/.local/bin/tern-theme-fragment"

tern.on("window_start", function(_cx: WindowCx)
	-- Spawn from a timer: the fragment waits for Tern to list the theme (up to
	-- ~3 s), and the window_start callback itself must return at once.
	tern.timer(0, function(_: WindowCx?)
		local ok, err = pcall(tern.process.run, { FRAGMENT }, { timeout_ms = 30000 }, function(result: ProcessResult, _: WindowCx?)
			if result.status ~= 0 then
				tern.log.warn("omacosy-theme: tern-theme-fragment failed", result.status, result.stderr)
			end
		end)
		if not ok then
			tern.log.warn("omacosy-theme: spawn failed", err)
		end
	end)
end)
