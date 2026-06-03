--- Stepped execution with line highlight and repeat countdown.

local Lexer = require("lexer")
local Parser = require("parser")
local Runtime = require("runtime")

local Stepper = {}
Stepper.__index = Stepper

Stepper.SPEEDS = {
    cheetah = 0.05,
    speedster = 0.1,
    fast = 0.2,
    regular = 0.5,
    slow = 1.0,
    turtle = 2.0,
}

function Stepper.new(source, builtins)
    local tokens = Lexer.tokenize(source)
    local program = Parser.parse(tokens)
    return setmetatable({
        source = source,
        lines = {},
        program = program,
        runtime = Runtime.new(builtins),
        flat = {},
        pc = 1,
        timer = 0,
        speed = Stepper.SPEEDS.regular,
        running = false,
        currentLine = nil,
        executedLines = {},
        onPrint = nil,
        repeatLabel = nil,
        whileFrames = {},
    }, Stepper)
end

local function splitLines(source)
    local lines = {}
    for line in (source .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

local function flatten(stmts, out)
    for _, s in ipairs(stmts) do
        if s.tag == "if" then
            out[#out + 1] = s
            flatten(s.body, out)
            if s.elseBody then flatten(s.elseBody, out) end
        elseif s.tag == "while" then
            out[#out + 1] = s
        elseif s.tag == "repeat" then
            out[#out + 1] = s
        elseif s.tag == "function" then
            out[#out + 1] = s
        else
            out[#out + 1] = s
        end
    end
end

function Stepper:reset()
    self.lines = splitLines(self.source)
    self.flat = {}
    flatten(self.program, self.flat)
    self.pc = 1
    self.whileFrames = {}
    self.executedLines = {}
    self.currentLine = nil
    self.repeatLabel = nil
    self.running = true
    self.timer = 0
end

function Stepper:setSpeed(name)
    self.speed = Stepper.SPEEDS[name] or Stepper.SPEEDS.regular
end

function Stepper:update(dt)
    if not self.running then return end
    self.timer = self.timer + dt
    if self.timer < self.speed then return end
    self.timer = 0
    self:step()
end

function Stepper:expandRepeat(stmt)
    local n = math.floor(self.runtime:evalExpr(stmt.count) or 0)
    if n <= 0 then return true end
    local expanded = {}
    for i = n, 1, -1 do
        for _, inner in ipairs(stmt.body) do
            local copy = {}
            for k, v in pairs(inner) do copy[k] = v end
            copy._repeatRemaining = i
            copy._repeatParentLine = stmt.line
            expanded[#expanded + 1] = copy
        end
    end
    for i = 1, #expanded do
        table.insert(self.flat, self.pc + i, expanded[i])
    end
    return true
end

function Stepper:step()
    if self.pc > #self.flat then
        self.running = false
        self.currentLine = nil
        self.repeatLabel = nil
        return
    end

    local stmt = self.flat[self.pc]

    if stmt.tag == "repeat" and not stmt._expanded then
        stmt._expanded = true
        self:expandRepeat(stmt)
        return self:step()
    end

    if stmt.tag == "while" then
        if not Runtime.isTruthy(self.runtime:evalExpr(stmt.cond)) then
            self.pc = self.pc + 1
            return
        end
        self.whileFrames[#self.whileFrames + 1] = {
            headerPc = self.pc,
            bodyStart = self.pc + 1,
            bodyEnd = self.pc + #stmt.body,
        }
        self.pc = self.pc + 1
        stmt = self.flat[self.pc]
    end

    self.currentLine = stmt.line or stmt._repeatParentLine
    self.executedLines[self.currentLine] = true

    if stmt._repeatRemaining then
        self.repeatLabel = "repeat " .. tostring(stmt._repeatRemaining)
    else
        self.repeatLabel = nil
    end

    local ok, err = pcall(function()
        if stmt.tag == "if" then
            if Runtime.isTruthy(self.runtime:evalExpr(stmt.cond)) then
                self.runtime:runBlock(stmt.body)
            elseif stmt.elseBody then
                self.runtime:runBlock(stmt.elseBody)
            end
        elseif stmt.tag == "while" then
            self.runtime:evalStmt(stmt)
        else
            self.runtime:evalStmt(stmt)
        end
    end)

    if not ok and self.onPrint then
        self.onPrint("[error] " .. tostring(err))
        self.running = false
        return
    end

    self.pc = self.pc + 1

    local frame = self.whileFrames[#self.whileFrames]
    if frame and self.pc > frame.bodyEnd then
        if Runtime.isTruthy(self.runtime:evalExpr(self.flat[frame.headerPc].cond)) then
            self.pc = frame.bodyStart
        else
            table.remove(self.whileFrames)
            self.pc = frame.headerPc + 1
        end
    end
end

function Stepper:getLineHighlight(lineNo)
    if self.currentLine == lineNo then
        return "current"
    elseif self.executedLines[lineNo] then
        return "done"
    end
    return nil
end

return Stepper
