--- Khoron runtime — values, environment, expression evaluation.

local Runtime = {}
Runtime.__index = Runtime
local unpackCompat = table.unpack or unpack

local function isTruthy(v)
    return v ~= nil and v ~= false and v ~= 0
end

function Runtime.new(builtins)
    local self = setmetatable({
        globals = {},
        builtins = builtins or {},
        printFn = builtins and builtins.print or print,
    }, Runtime)
    return self
end

function Runtime:define(name, value)
    self.globals[name] = value
end

function Runtime:get(name)
    if self.globals[name] ~= nil then return self.globals[name] end
    if self.builtins[name] then return self.builtins[name] end
    return nil
end

function Runtime:evalExpr(expr)
    if expr.tag == "num" or expr.tag == "str" or expr.tag == "bool" then
        return expr.value
    elseif expr.tag == "var" then
        return self:get(expr.name)
    elseif expr.tag == "binop" then
        local a = self:evalExpr(expr.left)
        local b = self:evalExpr(expr.right)
        if expr.op == "plus" then
            if type(a) == "string" or type(b) == "string" then
                return tostring(a) .. tostring(b)
            end
            return (a or 0) + (b or 0)
        elseif expr.op == "minus" then
            return (a or 0) - (b or 0)
        elseif expr.op == "star" then
            return (a or 0) * (b or 0)
        elseif expr.op == "slash" then
            return (a or 0) / (b or 0)
        end
    elseif expr.tag == "call" then
        local fn = self:get(expr.name)
        if type(fn) ~= "function" then
            error("undefined call: " .. tostring(expr.name))
        end
        local args = {}
        for i, a in ipairs(expr.args) do
            args[i] = self:evalExpr(a)
        end
        return fn(self, unpackCompat(args))
    end
    return nil
end

function Runtime:evalStmt(stmt)
    if stmt.tag == "assign" then
        self:define(stmt.name, self:evalExpr(stmt.expr))
    elseif stmt.tag == "aug_assign" then
        local cur = self:get(stmt.name) or 0
        local rhs = self:evalExpr(stmt.expr)
        if stmt.op == "plus" then
            if type(cur) == "string" or type(rhs) == "string" then
                self:define(stmt.name, tostring(cur) .. tostring(rhs))
            else
                self:define(stmt.name, (cur or 0) + (rhs or 0))
            end
        elseif stmt.op == "minus" then
            self:define(stmt.name, (cur or 0) - (rhs or 0))
        elseif stmt.op == "star" then
            self:define(stmt.name, (cur or 0) * (rhs or 0))
        elseif stmt.op == "slash" then
            self:define(stmt.name, (cur or 0) / (rhs or 0))
        end
    elseif stmt.tag == "incdec" then
        local cur = self:get(stmt.name) or 0
        if stmt.op == "inc" then
            self:define(stmt.name, cur + 1)
        else
            self:define(stmt.name, cur - 1)
        end
    elseif stmt.tag == "expr" then
        self:evalExpr(stmt.expr)
    elseif stmt.tag == "return" then
        if stmt.expr then return "return", self:evalExpr(stmt.expr) end
        return "return"
    elseif stmt.tag == "if" then
        if isTruthy(self:evalExpr(stmt.cond)) then
            self:runBlock(stmt.body)
        elseif stmt.elseBody then
            self:runBlock(stmt.elseBody)
        end
    elseif stmt.tag == "while" then
        while isTruthy(self:evalExpr(stmt.cond)) do
            self:runBlock(stmt.body)
        end
    elseif stmt.tag == "repeat" then
        local n = math.floor(self:evalExpr(stmt.count) or 0)
        for i = n, 1, -1 do
            stmt._repeatRemaining = i
            self:runBlock(stmt.body)
        end
        stmt._repeatRemaining = nil
    elseif stmt.tag == "function" then
        local runtime = self
        self:define(stmt.name, function(rt, ...)
            local old = {}
            for i, p in ipairs(stmt.params) do
                old[p] = runtime:get(p)
                runtime:define(p, select(i, ...))
            end
            runtime:runBlock(stmt.body)
            for p, v in pairs(old) do runtime:define(p, v) end
        end)
    end
end

function Runtime:runBlock(block)
    for _, s in ipairs(block) do
        local tag, val = self:evalStmt(s)
        if tag == "return" then return val end
    end
end

function Runtime:run(program)
    for _, s in ipairs(program) do
        self:evalStmt(s)
    end
end

Runtime.isTruthy = isTruthy
return Runtime
