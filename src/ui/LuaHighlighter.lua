--- Simple Lua syntax highlighter for the Notebook IDE.

local LuaHighlighter = {}

-- Color definitions
LuaHighlighter.colors = {
    keyword = {1, 0.6, 0.3, 1},      -- orange
    string = {0.5, 0.8, 0.3, 1},     -- green
    number = {0.9, 0.8, 0.2, 1},     -- yellow
    comment = {0.5, 0.5, 0.5, 1},    -- gray
    normal = {1, 1, 1, 1},
}

local KEYWORDS = {
    ["local"] = true, ["function"] = true, ["if"] = true, ["then"] = true,
    ["else"] = true, ["elseif"] = true, ["end"] = true, ["for"] = true,
    ["while"] = true, ["do"] = true, ["return"] = true, ["true"] = true,
    ["false"] = true, ["nil"] = true, ["and"] = true, ["or"] = true,
    ["not"] = true, ["in"] = true, ["repeat"] = true, ["until"] = true,
    ["break"] = true,
}

function LuaHighlighter.highlightLine(line)
    local tokens = {}
    local i = 1
    
    while i <= #line do
        local ch = line:sub(i, i)
        
        -- Comments
        if ch == '-' and line:sub(i + 1, i + 1) == '-' then
            tokens[#tokens + 1] = {line:sub(i), "comment"}
            break
        elseif ch == '"' or ch == "'" then
            -- Strings
            local quote = ch
            local j = i + 1
            local found = false
            while j <= #line do
                if line:sub(j, j) == quote and line:sub(j - 1, j - 1) ~= '\\' then
                    tokens[#tokens + 1] = {line:sub(i, j), "string"}
                    i = j + 1
                    found = true
                    break
                end
                j = j + 1
            end
            if not found then
                tokens[#tokens + 1] = {line:sub(i), "string"}
                break
            end
        elseif ch:match("[0-9]") then
            -- Numbers
            local j = i
            while j <= #line and line:sub(j, j):match("[0-9.]") do
                j = j + 1
            end
            tokens[#tokens + 1] = {line:sub(i, j - 1), "number"}
            i = j
        elseif ch:match("[a-zA-Z_]") then
            -- Keywords and identifiers
            local j = i
            while j <= #line and line:sub(j, j):match("[a-zA-Z0-9_]") do
                j = j + 1
            end
            local word = line:sub(i, j - 1)
            local tokenType = KEYWORDS[word] and "keyword" or "normal"
            tokens[#tokens + 1] = {word, tokenType}
            i = j
        else
            tokens[#tokens + 1] = {ch, "normal"}
            i = i + 1
        end
    end
    
    return tokens
end

function LuaHighlighter.drawHighlightedText(text, x, y, maxWidth)
    local lines = type(text) == "string" and text:split("\n") or {}
    local lineHeight = 16
    
    for lineIdx, line in ipairs(lines) do
        local tokens = LuaHighlighter.highlightLine(line)
        local curX = x
        
        for _, token in ipairs(tokens) do
            local str, tokenType = token[1], token[2]
            local color = LuaHighlighter.colors[tokenType] or LuaHighlighter.colors.normal
            
            love.graphics.setColor(color)
            love.graphics.print(str, curX, y + (lineIdx - 1) * lineHeight)
            
            local font = love.graphics.getFont()
            curX = curX + font:getWidth(str)
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

-- Helper function for string splitting
function string.split(s, sep)
    local fields = {}
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

return LuaHighlighter
