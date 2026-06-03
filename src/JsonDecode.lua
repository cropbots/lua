--- Minimal JSON decoder (shared by TileSet snapshots and FarmScene).

local M = {}

function M.decode(s)
    local pos = 1

    local function skipWS()
        while pos <= #s and s:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function peek()
        skipWS()
        return s:sub(pos, pos)
    end

    local function consume(ch)
        skipWS()
        if s:sub(pos, pos) ~= ch then
            error(("json: expected '%s' at pos %d"):format(ch, pos))
        end
        pos = pos + 1
    end

    local parseValue

    local function parseString()
        consume('"')
        local result = {}
        while pos <= #s do
            local ch = s:sub(pos, pos)
            if ch == '"' then
                pos = pos + 1
                return table.concat(result)
            elseif ch == '\\' then
                pos = pos + 1
                local esc = s:sub(pos, pos)
                pos = pos + 1
                if esc == 'n' then result[#result + 1] = '\n'
                elseif esc == 't' then result[#result + 1] = '\t'
                else result[#result + 1] = esc end
            else
                result[#result + 1] = ch
                pos = pos + 1
            end
        end
        error("json: unterminated string")
    end

    local function parseNumber()
        skipWS()
        local start = pos
        if s:sub(pos, pos) == '-' then pos = pos + 1 end
        while pos <= #s and s:sub(pos, pos):match("%d") do pos = pos + 1 end
        if pos <= #s and s:sub(pos, pos) == '.' then
            pos = pos + 1
            while pos <= #s and s:sub(pos, pos):match("%d") do pos = pos + 1 end
        end
        return tonumber(s:sub(start, pos - 1))
    end

    local function parseArray()
        consume('[')
        local arr = {}
        skipWS()
        if peek() == ']' then pos = pos + 1; return arr end
        while true do
            arr[#arr + 1] = parseValue()
            skipWS()
            local ch = s:sub(pos, pos)
            if ch == ']' then pos = pos + 1; return arr
            elseif ch == ',' then pos = pos + 1
            else error("json: expected ]") end
        end
    end

    local function parseObject()
        consume('{')
        local obj = {}
        skipWS()
        if peek() == '}' then pos = pos + 1; return obj end
        while true do
            local key = parseString()
            consume(':')
            obj[key] = parseValue()
            skipWS()
            local ch = s:sub(pos, pos)
            if ch == '}' then pos = pos + 1; return obj
            elseif ch == ',' then pos = pos + 1
            else error("json: expected }") end
        end
    end

    parseValue = function()
        local ch = peek()
        if ch == '"' then return parseString()
        elseif ch == '{' then return parseObject()
        elseif ch == '[' then return parseArray()
        elseif ch == 't' then pos = pos + 4; return true
        elseif ch == 'f' then pos = pos + 5; return false
        elseif ch == 'n' then pos = pos + 4; return nil
        elseif ch == '-' or ch:match("%d") then return parseNumber()
        else error("json: bad char " .. ch) end
    end

    local ok, result = pcall(parseValue)
    if not ok then return nil, result end
    return result
end

return M
