--- Khoron parser — line-oriented blocks with `end`.

local Parser = {}

function Parser.parse(tokens)
    local pos = 1

    local function cur() return tokens[pos] end
    local function nxt() return tokens[pos + 1] end

    local function eat(kind, val)
        local t = cur()
        if t.kind ~= kind or (val and t.value ~= val) then
            error(("parse error line %d: expected %s"):format(t.line, kind))
        end
        pos = pos + 1
        return t
    end

    local function match(kind, val)
        local t = cur()
        return t.kind == kind and (not val or t.value == val)
    end

    local function skipNewlines()
        while match("newline") do pos = pos + 1 end
    end

    local parseExpr

    local function parsePrimary()
        local t = cur()
        if t.kind == "number" then
            pos = pos + 1
            return { tag = "num", value = t.value }
        elseif t.kind == "string" then
            pos = pos + 1
            return { tag = "str", value = t.value }
        elseif t.kind == "keyword" and (t.value == "true" or t.value == "false") then
            pos = pos + 1
            return { tag = "bool", value = t.value == "true" }
        elseif t.kind == "ident" then
            pos = pos + 1
            local name = t.value
            if match("lparen") then
                pos = pos + 1
                local args = {}
                if not match("rparen") then
                    args[#args + 1] = parseExpr()
                    while match("comma") do
                        pos = pos + 1
                        args[#args + 1] = parseExpr()
                    end
                end
                eat("rparen", ")")
                return { tag = "call", name = name, args = args }
            end
            return { tag = "var", name = name }
        elseif t.kind == "lparen" then
            pos = pos + 1
            local e = parseExpr()
            eat("rparen", ")")
            return e
        end
        error("bad expr line " .. t.line)
    end

    parseExpr = function()
        local left = parsePrimary()
        while match("plus") or match("minus") or match("star") or match("slash") do
            local op = cur().kind
            pos = pos + 1
            left = { tag = "binop", op = op, left = left, right = parsePrimary() }
        end
        return left
    end

    local function parseBlock()
        local stmts = {}
        while true do
            skipNewlines()
            if match("keyword", "end") then
                pos = pos + 1
                break
            end
            if match("eof") then break end
            local stmt = parseLine()
            if stmt then stmts[#stmts + 1] = stmt end
        end
        return stmts
    end

    function parseLine()
        skipNewlines()
        if match("eof") then return nil end
        local lineNo = cur().line

        if match("keyword", "function") then
            pos = pos + 1
            local name = eat("ident").value
            local params = {}
            if match("lparen") then
                pos = pos + 1
                if not match("rparen") then
                    params[#params + 1] = eat("ident").value
                    while match("comma") do
                        pos = pos + 1
                        params[#params + 1] = eat("ident").value
                    end
                end
                eat("rparen", ")")
            end
            if match("colon") then pos = pos + 1 end
            return { tag = "function", name = name, params = params, body = parseBlock(), line = lineNo }
        end

        if match("keyword", "if") then
            pos = pos + 1
            local cond = parseExpr()
            if match("colon") then pos = pos + 1 end
            local body = parseBlock()
            local elseBody = nil
            skipNewlines()
            if match("keyword", "else") then
                pos = pos + 1
                if match("colon") then pos = pos + 1 end
                elseBody = parseBlock()
            end
            return { tag = "if", cond = cond, body = body, elseBody = elseBody, line = lineNo }
        end

        if match("keyword", "while") then
            pos = pos + 1
            local cond = parseExpr()
            if match("colon") then pos = pos + 1 end
            return { tag = "while", cond = cond, body = parseBlock(), line = lineNo }
        end

        if match("keyword", "repeat") then
            pos = pos + 1
            local count = parseExpr()
            if match("colon") then pos = pos + 1 end
            return { tag = "repeat", count = count, body = parseBlock(), line = lineNo }
        end

        if match("keyword", "return") then
            pos = pos + 1
            local expr = nil
            if not match("newline") and not match("eof") and not match("keyword", "end") then
                expr = parseExpr()
            end
            return { tag = "return", expr = expr, line = lineNo }
        end

        if match("ident") and nxt() and nxt().kind == "eq" then
            local name = eat("ident").value
            pos = pos + 1
            return { tag = "assign", name = name, expr = parseExpr(), line = lineNo }
        end

        if match("ident") and nxt() and nxt().kind == "plus_eq" then
            local name = eat("ident").value
            pos = pos + 1
            return { tag = "aug_assign", op = "plus", name = name, expr = parseExpr(), line = lineNo }
        end

        if match("ident") and nxt() and nxt().kind == "minus_eq" then
            local name = eat("ident").value
            pos = pos + 1
            return { tag = "aug_assign", op = "minus", name = name, expr = parseExpr(), line = lineNo }
        end

        if match("ident") and nxt() and nxt().kind == "star_eq" then
            local name = eat("ident").value
            pos = pos + 1
            return { tag = "aug_assign", op = "star", name = name, expr = parseExpr(), line = lineNo }
        end

        if match("ident") and nxt() and nxt().kind == "slash_eq" then
            local name = eat("ident").value
            pos = pos + 1
            return { tag = "aug_assign", op = "slash", name = name, expr = parseExpr(), line = lineNo }
        end

        if match("ident") and nxt() and nxt().kind == "plus_plus" then
            local name = eat("ident").value
            pos = pos + 1
            return { tag = "incdec", op = "inc", name = name, line = lineNo }
        end

        if match("ident") and nxt() and (nxt().kind == "newline" or nxt().kind == "eof" or (nxt().kind == "keyword" and nxt().value == "end")) then
            local name = eat("ident").value
            return { tag = "expr", expr = { tag = "call", name = name, args = {} }, line = lineNo }
        end

        return { tag = "expr", expr = parseExpr(), line = lineNo }
    end

    skipNewlines()
    if match("eof") then return {} end
    local program = {}
    while not match("eof") do
        local stmt = parseLine()
        if stmt then program[#program + 1] = stmt end
        skipNewlines()
    end
    return program
end

return Parser
