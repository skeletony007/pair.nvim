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

    server = require("pair.server"),
    util = require("pair.util"),

    max_seqnum = 1000000,
}

vim.api.nvim_set_hl(0, "PairVirtualCursor", vim.api.nvim_get_hl(0, { name = "Cursor" }))
vim.api.nvim_set_hl(0, "PairVirtualBlame", {
    fg = vim.api.nvim_get_hl(0, { name = "PairVirtualCursor" }).bg,
    bg = "none",
    bold = true,
})

function M.setup(opts) M.opts = vim.tbl_deep_extend("force", M.opts, opts or {}) end

--- Sets (replaces) a line-range in the local buffer so that the local buffer
--- is the same as the remote one.
---@param replacement table Array of lines to use as replacement
---@param seqnum integer Change sequence number
function M.set_lines(replacement, seqnum)
    if
        not (
            vim.api.nvim_get_current_buf() == M.bufnr
            and (
                seqnum > M.set_lines_seqnum
                or M.set_lines_seqnum + 1 == M.max_seqnum -- we don't know anything, in this case.
            )
        )
    then
        return
    end

    -- prevent de-sync, see TextChanged* autocmd (where `M.set_lines_seqnum`
    -- is incremented).
    M.set_lines_seqnum = seqnum - 1

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

    local cursor_row_local = vim.api.nvim_win_get_cursor(0)[1]

    vim.api.nvim_buf_set_lines(
        M.bufnr,
        start_index - 1,
        end_index_local,
        false,
        M.util.tbl.range(replacement, start_index, end_index_replacement)
    )

    vim.fn.winrestview({
        topline = vim.fn.winsaveview().topline + vim.api.nvim_win_get_cursor(0)[1] - cursor_row_local,
    })
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
            {
                M.opts.virtual_cursor_blame_prefix,
                "PairVirtualBlame",
            },
            {
                mode,
                "PairVirtualBlame",
            },
        },
        virt_text_pos = "eol",
    })
end

function M.get_virtual_cursor_mark()
    return vim.api.nvim_buf_get_extmark_by_id(M.bufnr, M.virtual_cursor_mark_ns, M.virtual_cursor_mark_id, {})
end

--- Initialize the sequence numbers.
---
--- Used for the start "handshake".
function M.init_set_lines_seqnum() M.set_lines_seqnum = 0 end

--- Broadcast buffer changes to remote client.
---@param server_addr string this server address
---@param client_addr string remote client address
function M.start(server_addr, client_addr)
    M.bufnr = vim.api.nvim_get_current_buf()

    -- undofile gets too messy with single character changes
    vim.bo[M.bufnr].undofile = false

    M.server.start(server_addr, client_addr)

    -- handshake
    M.server.sender.send_lua([[require("pair").init_set_lines_seqnum()]])
    M.init_set_lines_seqnum()

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
            M.set_lines_seqnum = M.set_lines_seqnum + 1 % M.max_seqnum
            M.server.sender.send_lua(
                string.format(
                    [[require("pair").set_lines(%s, %d)]],
                    vim.inspect(vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)),
                    M.set_lines_seqnum
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
            M.server.sender.send_lua(
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
    M.server.stop()
    vim.api.nvim_clear_autocmds({ group = M.group, buffer = M.bufnr })
    vim.api.nvim_buf_clear_namespace(M.bufnr, M.cursor_mark_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(M.bufnr, M.virtual_cursor_mark_ns, 0, -1)
end

vim.api.nvim_create_user_command("PairServer", function() M.start(M.opts.server_addr, M.opts.client_addr) end, {})
vim.api.nvim_create_user_command("PairClient", function() M.start(M.opts.client_addr, M.opts.server_addr) end, {})
vim.api.nvim_create_user_command("PairStop", function() M.stop() end, {})

return M
