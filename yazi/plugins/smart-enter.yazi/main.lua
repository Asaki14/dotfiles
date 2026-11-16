--- @since 25.5.31
--- @sync entry

local function setup(self, opts)
	self.open_multi = opts.open_multi
end

local function entry(self)
	local h = cx.active.current.hovered
	if h and h.cha.is_dir then
		ya.emit("enter", { hovered = true })
	else
		-- markdown/html 用浏览器打开
		local ext = h.url.ext or ""
		local path = tostring(h.url.path)
		if ext == "md" or ext == "mdx" or ext == "markdown" then
			ya.async(function() Command("mo"):arg({ path }):spawn() end)
		elseif ext == "html" or ext == "htm" then
			ya.async(function() Command("open"):arg({ path }):spawn() end)
		else
			ya.emit("open", { hovered = not self.open_multi })
		end
	end
end

return { entry = entry, setup = setup }
