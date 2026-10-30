local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    -- 主题设置
    {
        "rose-pine/neovim",
        name = "rose-pine",
        config = function()
            require("rose-pine").setup({
                styles = { transparency = true, },
            })
            vim.cmd("colorscheme rose-pine")
        end,
    },

-- Telescope 插件 (搜索功能)
    {
        'nvim-telescope/telescope.nvim', 
        tag = '0.1.8',
        dependencies = { 
            'nvim-lua/plenary.nvim',
            'nvim-tree/nvim-web-devicons' 
        },
        config = function()
            require('telescope').setup({
                pickers = {
                    -- 文件搜索配置
                    find_files = {
                        hidden = true, -- 允许搜索以 . 开头的文件 (.config, .zshrc 等)
                    },
                    -- 内容搜索配置
                    live_grep = {
                        -- 让 ripgrep 也能搜索隐藏文件里的内容
                        additional_args = function(opts)
                            return { "--hidden" }
                        end
                    },
                },
            })
        end
    },
    -- Snacks.nvim (Dashboard)
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        opts = {
            dashboard = {
                preset = {
                    header = "", -- 为空
                    keys = {
                        { icon = "􀀡 ", key = "o", desc = "Open", action = ":lua Snacks.dashboard.pick('files')" },
                        { icon = "􀀟 ", key = "n", desc = "New", action = ":ene | startinsert" },
                        { icon = "􀀧 ", key = "r", desc = "Recent", action = ":lua Snacks.dashboard.pick('oldfiles')" },
                        { icon = "􀀉 ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
                        { icon = "􀀭 ", key = "u", desc = "Update", action = ":Lazy sync", enabled = package.loaded.lazy ~= nil },
                        { icon = "􀀥 ", key = "q", desc = "Quit", action = ":qa!" },
                    },
                },
                sections = {
                    {
                        section = "terminal",
                        cmd = "chafa " .. vim.fn.stdpath("config") .. "/assets/nyde.jpeg --format=symbols --size=60x80 && sleep 0.1",
                        height = 20,
                        width = 70,
                        pane = 1,
                        gap = 1,
                        padding = 1,
                        align="center"
                    },
                    {
                        section = "keys",
                        gap = 1,
                        padding = 1,
                        pane = 2,          
                    },

                    { 
                        section = "startup",
                        padding = 1 
                    },
                },
            },
        },
    },
    {
        "nvim-tree/nvim-tree.lua",
        version = "*",
        lazy = false,
        dependencies = { "nvim-tree/nvim-web-devicons", },
        config = function()
            require("nvim-tree").setup {}
        end,
    },

    -- 标签栏
    {
        'akinsho/bufferline.nvim',
        version = "*",
        dependencies = 'nvim-tree/nvim-web-devicons',
        config = function()
            require("bufferline").setup {}
        end
    },

    {
        "hrsh7th/nvim-cmp",
        dependencies = {
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
        },
        config = function()
            local cmp = require("cmp")
            cmp.setup({
                mapping = {
                    ["<C-n>"] = cmp.mapping.select_next_item(),
                    ["<C-p>"] = cmp.mapping.select_prev_item(),
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                },
                sources = {
                    { name = "buffer" },
                    { name = "path" },
                },
            })
        end,
    },
})
