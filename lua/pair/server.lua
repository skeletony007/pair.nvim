local M = {
    --- Stores this server named pipe or socket address.
    addr = "",
}

--- Opens a socket or named pipe and listens for RPC messages.
---
--- This function corresponds with `vim.fn.serverstart()` and has side effects.
--- See `:help remote`.
---
---@param addr string This named pipe or socket address
function M.start(addr)
    M.addr = addr
    vim.fn.serverstart(addr)
end

--- Closes the pipe or socket.
---
--- This function corresponds with `vim.fn.serverstop()`.
---
function M.stop() vim.fn.serverstop(M.addr) end

--- Evaluate lua code in remote.
---
--- Accepts a function.
---
---@param lua_code string Lua code
---@param remote_addr string Remote named pipe or socket address
function M.send_lua(lua_code, remote_addr)
    local command = string.format(
        "nvim --server %q --remote-expr %q",
        remote_addr,
        string.format("luaeval(%q)", string.format([[require("pair.server").receive_lua(%q)]], lua_code))
    )
    vim.fn.jobstart(command)
end

--- Evaluate lua code locally.
---
--- Functions fail silently.
---
---@param lua_code string Lua code
function M.receive_lua(lua_code)
    local chunk, _ = load(lua_code)
    if chunk then
        chunk()
    end
end

return M
