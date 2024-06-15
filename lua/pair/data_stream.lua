local util = require("pair.util")

local M = {
    --- Table of broadcasting (streaming) streams indexed by stream_id, containing sequence number and remote addresses.
    --- Each entry in the table represents a stream with a unique ID.
    --- - `seqnum`: The sequence number of the stream.
    --- - `remote_addrs`: A list-like (vector) table of target remote named pipe or socket addresses for the stream.
    --- Example:
    --- ```lua
    --- streams = {
    ---     ["StreamID"] = {
    ---         seqnum = 42,
    ---         remote_addrs = { "/tmp/socket" },
    ---     },
    --- }
    --- ```
    streams = {},
    --- Table of listening (joined) sockets indexed by remote address, each containing streams with their sequence numbers.
    --- Each entry in the table represents a socket with its remote address as the key.
    --- The `streams` table within each socket entry contains streams indexed by their `stream_id`.
    --- Each stream entry in the `streams` table represents a stream with a unique ID.
    --- - `seqnum`: The sequence number of the stream.
    --- Example:
    --- ```lua
    --- sockets = {
    ---     ["/tmp/socket"] = {
    ---         streams = {
    ---             ["StreamID1"] = { seqnum = 69 },
    ---             ["StreamID2"] = { seqnum = 420 },
    ---         },
    ---     },
    --- }
    --- ```
    sockets = {},

    server = require("pair.server"),
}

--- Set the sequence number of a joined stream.
---@param remote_addr string Remote named pipe or socket address
---@param stream_id string Unique stream ID
---@param seqnum integer Sequence number
function M.set_socket_seqnum(remote_addr, stream_id, seqnum) M.sockets[remote_addr].streams[stream_id].seqnum = seqnum end

--- Initialize a stream to specified remote named pipe or socket addresses with a unique stream ID.
---@param remote_addrs table Remote named pipe or socket addresses
---@param stream_id string Unique stream ID
function M.start(remote_addrs, stream_id)
    M.streams[stream_id] = { seqnum = 0, remote_addrs = remote_addrs }

    for _, remote_addr in ipairs(remote_addrs) do
        M.server.send_lua(
            string.format([[require("pair.data_stream").set_socket_seqnum(%q, %q, %d)]], M.server.addr, stream_id, 0),
            remote_addr
        )
    end
end

--- End stream by stream ID.
---@param stream_id string Unique stream ID
function M.stop(stream_id) M.streams[stream_id] = nil end

--- Opens a socket or named pipe and listens for stream data by stream ID.
---@param remote_addr string Remote named pipe or socket address
---@param stream_id string Unique stream ID
function M.join(remote_addr, stream_id)
    if not M.sockets[remote_addr] then
        M.sockets[remote_addr] = { streams = {} }
    end

    M.sockets[remote_addr].streams[stream_id] = { seqnum = 0 }

    M.server.send_lua(
        string.format(
            [[require("pair.data_stream").server.send_lua(%q, %q)]],
            string.format(
                [[require("pair.data_stream").set_socket_seqnum(%q, %q, require("pair.data_stream").streams[%q].seqnum)]],
                remote_addr,
                stream_id,
                stream_id
            ),
            M.server.addr
        ),
        remote_addr
    )
end

--- Closes an open named pipe or socket stream by stream ID.
---@param remote_addr string Remote named pipe or socket address
---@param stream_id string Unique stream ID
function M.leave(remote_addr, stream_id)
    local socket = M.sockets[remote_addr]

    socket.streams[stream_id] = nil

    -- remove remote_addr if it has no more streams
    if next(socket.streams) == nil then
        socket = nil
    end
end

--- Broadcast lua code in a stream.
---
--- Accepts a function.
---
---@param stream_id string Unique stream ID
---@param lua_code string Lua code
function M.send_lua(stream_id, lua_code)
    local stream = M.streams[stream_id]
    stream.seqnum = (stream.seqnum + 1) % util.math.max_integer

    local wrapped_lua_code = string.format(
        [[require("pair.data_stream").receive_lua(%q, %d, %q, %q)]],
        M.server.addr,
        stream.seqnum,
        stream_id,
        lua_code
    )

    for _, remote_addr in ipairs(M.streams[stream_id].remote_addrs) do
        M.server.send_lua(wrapped_lua_code, remote_addr)
    end
end

--- Receive Lua code from a stream.
---
--- Functions fail silently.
---
---@param remote_addr string Remote named pipe or socket address
---@param seqnum integer Sequence number
---@param stream_id string Unique stream ID
---@param lua_code string Lua code
function M.receive_lua(remote_addr, seqnum, stream_id, lua_code)
    local socket = M.sockets[remote_addr]
    if not (socket and socket.streams[stream_id]) then
        return
    end

    local local_seqnum = socket.streams[stream_id].seqnum
    if not (seqnum > local_seqnum or local_seqnum + 1 == util.math.max_integer) then
        return
    end

    socket.streams[stream_id].seqnum = seqnum
    M.server.receive_lua(lua_code)
end

return M
