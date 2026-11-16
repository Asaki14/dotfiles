require("configs")
require("keymaps")
require("plugins")
vim.api.nvim_create_autocmd("BufLeave", {
    callback = function(ev)
        if vim.bo[ev.buf].filetype == "snacks_dashboard" then
            vim.cmd("stopinsert")
            vim.cmd("redraw!")
        end
    end,
})
