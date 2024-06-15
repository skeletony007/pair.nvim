local data_stream = require("pair.data_stream")
local util = require("pair.util")

local M = {
    opts = {
        -- named pipe or socket address (see `:help remote`)
        server_addr = os.getenv("HOME") .. "/.cache/nvim/pair-server.pipe",
        client_addr = os.getenv("HOME") .. "/.cache/nvim/pair-client.pipe",

        virtual_cursor_blame_prefix = " remote ",
    },

    cursor_mark_ns = vim.api.nvim_create_namespace("pair-cursor"),
    virtual_cursor_mark_ns = vim.api.nvim_create_namespace("pair-virtual-cursor"),
    group = vim.api.nvim_create_augroup("pair-group", {}),
}

vim.api.nvim_set_hl(0, "PairVirtualCursor", vim.api.nvim_get_hl(0, { name = "Cursor" }))
vim.api.nvim_set_hl(0, "PairVirtualBlame", {
    fg = vim.api.nvim_get_hl(0, { name = "PairVirtualCursor" }).bg,
    bg = "none",
    bold = true,
})

--- Setup function.
---@param opts table|nil optional param for M.opts
function M.setup(opts)
    opts = opts or {}
    M.opts = vim.tbl_deep_extend("force", M.opts, opts)
end

--- Sets (replaces) a line-range in the local buffer so that the local buffer
--- is the same as the remote one.
---@param replacement table Array of lines to use as replacement
function M.set_lines(replacement)
    local local_lines = vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)

    local local_len = #local_lines
    local replacement_len = #replacement

    local start_index = 1
    local end_index_local = #local_lines
    local end_index_replacement = #replacement
    while
        start_index <= math.min(local_len, replacement_len)
        and local_lines[start_index] == replacement[start_index]
    do
        start_index = start_index + 1
    end
    while
        end_index_local >= start_index
        and end_index_replacement >= start_index
        and local_lines[end_index_local] == replacement[end_index_replacement]
    do
        end_index_local = end_index_local - 1
        end_index_replacement = end_index_replacement - 1
    end

    local cursor_row_local
    if vim.api.nvim_get_current_buf() == M.bufnr then
        cursor_row_local = vim.api.nvim_win_get_cursor(0)[1]

        -- prevent de-sync
        data_stream.streams["TextChanged"].seqnum = data_stream.streams["TextChanged"].seqnum - 1
    end

    vim.api.nvim_buf_set_lines(
        M.bufnr,
        start_index - 1,
        end_index_local,
        false,
        util.tbl.range(replacement, start_index, end_index_replacement)
    )

    if vim.api.nvim_get_current_buf() == M.bufnr then
        vim.fn.winrestview({
            topline = vim.fn.winsaveview().topline + vim.api.nvim_win_get_cursor(0)[1] - cursor_row_local,
        })
    end
end

--- Sets the (1,0)-indexed virtaul cursor position in the window.
---@param row integer the row index
---@param col integer the column index
---@param mode string the mode indicator
function M.set_virtual_cursor_mark(row, col, mode)
    local line = vim.api.nvim_buf_get_lines(M.bufnr, row - 1, row, true)[1]
    local char
    if col + 1 > #line then
        char = " "
    else
        char = line:sub(col + 1, col + 1)
    end

    vim.api.nvim_buf_clear_namespace(M.bufnr, M.virtual_cursor_mark_ns, 0, -1)
    M.virtual_cursor_mark_id = vim.api.nvim_buf_set_extmark(M.bufnr, M.virtual_cursor_mark_ns, row - 1, col, {
        virt_text = {
            {
                char,
                "PairVirtualCursor",
            },
        },
        virt_text_pos = "overlay",
    })
    vim.api.nvim_buf_set_extmark(M.bufnr, M.virtual_cursor_mark_ns, row - 1, 0, {
        virt_text = {
            { M.opts.virtual_cursor_blame_prefix, "PairVirtualBlame" },
            { mode, "PairVirtualBlame" },
        },
        virt_text_pos = "eol",
    })
end

--- Broadcast buffer changes to remote client.
--- @param this_addr string this server address
--- @param remote_addr string remote client address
function M.start(this_addr, remote_addr)
    M.bufnr = vim.api.nvim_get_current_buf()

    -- TODO: this should be a suggestion in the README, not hard-coded (use an autocmd for start)
    -- undofile gets too messy with single character changes
    vim.bo[M.bufnr].undofile = false

    data_stream.server.start(this_addr)
    data_stream.start({ remote_addr }, "TextChanged")
    data_stream.start({ remote_addr }, "CursorMoved")
    data_stream.join(remote_addr, "TextChanged")
    data_stream.join(remote_addr, "CursorMoved")

    vim.api.nvim_create_autocmd({
        "TextChanged",
        "TextChangedI",
        "TextChangedP",
        "TextChangedT",
        "BufReadPost",
        "BufWritePost",
    }, {
        group = M.group,
        callback = function()
            data_stream.send_lua(
                "TextChanged",
                string.format(
                    [[require("pair").set_lines(%s)]],
                    vim.inspect(vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false))
                )
            )
        end,
        buffer = M.bufnr,
    })

    vim.api.nvim_create_autocmd({
        "CursorMoved",
        "CursorMovedI",
        "ModeChanged",
    }, {
        group = M.group,
        callback = function()
            local pos = vim.api.nvim_win_get_cursor(0)
            data_stream.send_lua(
                "CursorMoved",
                string.format(
                    [[require("pair").set_virtual_cursor_mark(%d, %d, %q)]],
                    pos[1],
                    pos[2],
                    vim.api.nvim_get_mode().mode
                )
            )
        end,
        buffer = M.bufnr,
    })
end

function M.stop()
    data_stream.server.stop()
    data_stream.stop("TextChanged")
    data_stream.stop("CursorMoved")
    vim.api.nvim_clear_autocmds({ group = M.group, buffer = M.bufnr })
    vim.api.nvim_buf_clear_namespace(M.bufnr, M.cursor_mark_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(M.bufnr, M.virtual_cursor_mark_ns, 0, -1)
end

vim.api.nvim_create_user_command("PairServer", function() M.start(M.opts.server_addr, M.opts.client_addr) end, {})
vim.api.nvim_create_user_command("PairClient", function() M.start(M.opts.client_addr, M.opts.server_addr) end, {})

vim.api.nvim_create_user_command("PairStop", function() M.stop() end, {})

return M
