return {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
        local toggleterm = require("toggleterm")
        toggleterm.setup({
            open_mapping = [[<c-t>]],
            direction = "vertical",
            size = function(term)
                if term.direction == "vertical" then
                    return vim.o.columns * 0.3 -- Use percentage instead of fixed size
                end
                return 15
            end,
            start_in_insert = false,
            close_on_exit = true,
            auto_scroll = true,
            persist_size = true,
            persist_mode = true,
            float_opts = {
                border = "single",
                winblend = 0,
            },
        })

        function _G.set_terminal_keymaps()
            local opts = { buffer = 0 }
            vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], opts)
            vim.keymap.set("t", "jk", [[<C-\><C-n>]], opts)
            vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-W>h]], opts)
            vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-W>j]], opts)
            vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-W>k]], opts)
            vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-W>l]], opts)
        end

        vim.api.nvim_create_autocmd("TermOpen", {
            pattern = "term://*",
            callback = set_terminal_keymaps,
        })
    end
}
