--- Khoron language package.

local Khoron = {
    Lexer = require("lexer"),
    Parser = require("parser"),
    Runtime = require("runtime"),
    Stepper = require("stepper"),
}

function Khoron.run(source, builtins)
    local tokens = Khoron.Lexer.tokenize(source)
    local program = Khoron.Parser.parse(tokens)
    local rt = Khoron.Runtime.new(builtins)
    rt:run(program)
    return rt
end

function Khoron.stepper(source, builtins)
    return Khoron.Stepper.new(source, builtins)
end

function Khoron.defaultBuiltins(notebook)
    local hooks = (notebook and notebook.robotHooks) or {}
    local function callHook(name)
        local fn = hooks[name]
        if type(fn) == "function" then fn() end
    end
    return {
        print = function(_, ...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[i] = tostring(select(i, ...))
            end
            local line = table.concat(parts, "\t")
            if notebook and notebook.log then
                notebook:log(line)
            else
                print(line)
            end
        end,
        input = function(_, prompt)
            prompt = prompt or ""
            if notebook and notebook.promptInput then
                return notebook:promptInput(prompt)
            end
            return ""
        end,
        -- Robot/puzzle builtins (canonical names)
        move = function() callHook("move") end,
        left_turn = function() callHook("left_turn") end,
        right_turn = function() callHook("right_turn") end,
        half_turn = function() callHook("half_turn") end,
        collect = function() callHook("collect") end,
        unlock = function() callHook("unlock") end,
        attack = function() callHook("attack") end,
        flag = function() callHook("flag") end,

        -- Backwards-compatible aliases (older notebook code)
        turn_left = function() callHook("left_turn") end,
        turn_right = function() callHook("right_turn") end,
    }
end

return Khoron
