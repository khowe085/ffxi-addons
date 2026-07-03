--[[
Ordered table iterator, allow to iterate on the natural order of the keys of a
table.

Example:
]]

-- PORT: from xivcrossbar/libs/ordered_pairs.lua (xivgamepad crossbar port;
-- see .planning/xivgamepad-contracts.md, "crossbar/ subtree rule").
-- Edits:
--   1. global hygiene: __genOrderedIndex, orderedNext and orderedPairs are
--      now locals (upstream leaked all three as globals; luac -l shows zero
--      SETGLOBAL after the change).

local function __genOrderedIndex( t )
    local orderedIndex = {}
    for key in pairs(t) do
        table.insert( orderedIndex, key )
    end
    table.sort( orderedIndex )
    return orderedIndex
end

local function orderedNext(t, state)
    -- Equivalent of the next function, but returns the keys in the alphabetic
    -- order. We use a temporary ordered key table that is stored in the
    -- table being iterated.

    local key = nil
    --print("orderedNext: state = "..tostring(state) )
    if state == nil then
        -- the first time, generate the index
        t.__orderedIndex = __genOrderedIndex( t )
        key = t.__orderedIndex[1]
    else
        -- fetch the next value
        for i = 1,table.getn(t.__orderedIndex) do
            if t.__orderedIndex[i] == state then
                key = t.__orderedIndex[i+1]
            end
        end
    end

    if key then
        return key, t[key]
    end

    -- no more value to return, cleanup
    t.__orderedIndex = nil
    return
end

local function orderedPairs(t)
    -- Equivalent of the pairs() function on tables. Allows to iterate
    -- in order
    return orderedNext, t, nil
end

return orderedPairs
