local M = {
    tbl = {},
    math = {},
}

function M.tbl.range(tbl, start_index, end_index)
    local res = {}
    for i = start_index, end_index do
        table.insert(res, tbl[i])
    end
    return res
end

M.math.max_integer = 4294967296

return M
