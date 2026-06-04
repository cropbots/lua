--- Khoron lexer — Lua-lite with colon block headers.

local Lexer = {}

local KEYWORDS = {
    ["function"] = true, ["end"] = true, ["if"] = true, ["then"] = true,
    ["else"] = true, ["while"] = true, ["repeat"] = true, ["do"] = true,
    ["return"] = true, ["true"] = true, ["false"] = true, ["and"] = true, ["or"] = true,
}

function Lexer.tokenize(source)
    local tokens = {}
    local line = 1
    local i = 1
    local n = #source

    local function peek(k) return source:sub(i, i + k - 1) end
    local function adv(k) i = i + k end

    local function add(kind, value)
        tokens[#tokens + 1] = { kind = kind, value = value, line = line }
    end

    while i <= n do
        local c = source:sub(i, i)
        if c == "\n" then
            line = line + 1
            add("newline", "\n")
            adv(1)
        elseif c:match("%s") then
            adv(1)
        elseif c == "#" then
            while i <= n and source:sub(i, i) ~= "\n" do adv(1) end
        elseif c == '"' then
            adv(1)
            local start = i
            while i <= n and source:sub(i, i) ~= '"' do
                if source:sub(i, i) == "\\" then adv(1) end
                adv(1)
            end
            add("string", source:sub(start, i - 1))
            adv(1)
        elseif c:match("[%a_]") then
            local start = i
            while i <= n and source:sub(i, i):match("[%w_]") do adv(1) end
            local word = source:sub(start, i - 1)
            if KEYWORDS[word] then
                add("keyword", word)
            else
                add("ident", word)
            end
        elseif c:match("%d") then
            local start = i
            while i <= n and source:sub(i, i):match("[%d%.]") do adv(1) end
            add("number", tonumber(source:sub(start, i - 1)))
        elseif c == ":" then
            add("colon", ":")
            adv(1)
        elseif c == "(" then add("lparen", "("); adv(1)
        elseif c == ")" then add("rparen", ")"); adv(1)
        elseif c == "+" then
            if peek(2) == "+=" then add("plus_eq", "+="); adv(2)
            elseif peek(2) == "++" then add("plus_plus", "++"); adv(2)
            else add("plus", "+"); adv(1) end
        elseif c == "-" then
            if peek(2) == "--" then
                -- Comment: consume until newline
                while i <= n and source:sub(i, i) ~= "\n" do adv(1) end
            elseif peek(2) == "-=" then add("minus_eq", "-="); adv(2)
            else add("minus", "-"); adv(1) end
        elseif c == "*" then
            if peek(2) == "*=" then add("star_eq", "*="); adv(2)
            else add("star", "*"); adv(1) end
        elseif c == "/" then
            if peek(2) == "/=" then add("slash_eq", "/="); adv(2)
            else add("slash", "/"); adv(1) end
        elseif c == "=" then
            if peek(2) == "==" then add("eq_eq", "=="); adv(2)
            else add("eq", "="); adv(1) end
        elseif c == "!" and peek(2) == "!=" then
            add("bang_eq", "!="); adv(2)
        elseif c == "," then add("comma", ","); adv(1)
        else
            adv(1)
        end
    end
    tokens[#tokens + 1] = { kind = "eof", value = nil, line = line }
    return tokens
end

return Lexer
