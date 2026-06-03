-- lua/src/StatBlock.lua
-- Named float accumulator used per entity instance.
-- Each StatBlock holds a map of string keys to float values.

local StatBlock = {}
StatBlock.__index = StatBlock

--- Create a new, empty StatBlock.
--- @return StatBlock
function StatBlock.new()
    return setmetatable({ values = {} }, StatBlock)
end

--- Add `value` to the named stat, initialising it to 0 if not yet present.
--- @param key    string  The stat name.
--- @param value  number  The amount to add (may be negative).
function StatBlock:add(key, value)
    self.values[key] = (self.values[key] or 0) + value
end

--- Merge all values from another StatBlock into this one.
--- Each key in `other` is added to the corresponding key in `self`.
--- @param other StatBlock  The source StatBlock to merge from.
function StatBlock:merge(other)
    for key, value in pairs(other.values) do
        self.values[key] = (self.values[key] or 0) + value
    end
end

--- Return the value for `key`, or `default` if the key is not present.
--- @param key     string  The stat name.
--- @param default number  Fallback value when the key is absent.
--- @return number
function StatBlock:get(key, default)
    local v = self.values[key]
    if v == nil then
        return default
    end
    return v
end

return StatBlock
