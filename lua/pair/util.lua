local M = { tbl = {} }

function M.tbl.range(tbl, start_index, end_index)
    local res = {}
    for i = start_index, end_index do
        table.insert(res, tbl[i])
    end
    return res
end

return M
