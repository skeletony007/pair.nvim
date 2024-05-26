local M = {
    sender = {},
    receiver = {},

    --math.maxinteger
    max_seqnum = 1000000,
}

--- Initialize broadcasting to remote client.
---@param server_addr string this server address
---@param client_addr string remote client address
function M.start(server_addr, client_addr)
    M.server_addr = server_addr
    M.client_addr = client_addr

    vim.fn.serverstart(server_addr)

    -- handshake
    M.sender.seqnum = M.max_seqnum
    M.sender.send_lua([[require("pair.server").init_seqnum()]])
    M.init_seqnum()
end

--- Stop a connection with the remote.
function M.stop() vim.fn.serverstop(M.server_addr) end

--- Initialize the sequence numbers.
---
--- Used for the start "handshake".
function M.init_seqnum()
    M.sender.seqnum = 0
    M.receiver.seqnum = 0
end

--- Evaluate lua code in remote.
---
--- Accepts a function.
---
---@param lua_code string lua code
function M.sender.send_lua(lua_code)
    M.sender.seqnum = M.sender.seqnum + 1 % M.max_seqnum
    local command = string.format(
        "nvim --server %q --remote-expr %q",
        M.client_addr,
        string.format(
            "luaeval(%q)",
            string.format([[require("pair.server").receiver.receive_lua(%q, %d)]], lua_code, M.sender.seqnum)
        )
    )
    vim.fn.jobstart(command)
end

--- Evaluate lua code locally.
---
--- Functions fail silently.
---
---@param lua_code string lua code
---@param seqnum integer sequence number (out of date sequence numbers are dropped)
function M.receiver.receive_lua(lua_code, seqnum)
    if
        not (
            seqnum > M.receiver.seqnum
            or M.receiver.seqnum + 1 == M.max_seqnum -- we don't know anything, in this case.
        )
    then
        return
    end

    M.receiver.seqnum = seqnum
    --print(lua_code)
    local chunk, _ = load(lua_code)
    if chunk then
        chunk()
    end
end

return M
