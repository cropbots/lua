--- Minimal JSON encoder for snapshots (no external deps).

local JsonUtil = {}

local function encodeValue(v)
    local t = type(v)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "number" then
        return tostring(v)
    elseif t == "string" then
        return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
    elseif t == "table" then
        local isArray = true
        local n = 0
        for k in pairs(v) do
            if type(k) ~= "number" then
                isArray = false
                break
            end
            n = math.max(n, k)
        end
        if isArray and n > 0 then
            local parts = {}
            for i = 1, n do
                parts[#parts + 1] = encodeValue(v[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, val in pairs(v) do
            parts[#parts + 1] = encodeValue(tostring(k)) .. ":" .. encodeValue(val)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

--- @param value any
--- @return string
function JsonUtil.encode(value)
    return encodeValue(value)
end

return JsonUtil
