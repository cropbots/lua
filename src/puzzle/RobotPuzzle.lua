--- Robot puzzle runtime: grid simulation for Khoron builtins.

local RobotPuzzle = {}
RobotPuzzle.__index = RobotPuzzle

local DIRS = {
    up = { 0, -1 },
    right = { 1, 0 },
    down = { 0, 1 },
    left = { -1, 0 },
}

local DIR_ORDER = { "up", "right", "down", "left" }
local DIR_IDX = { up = 1, right = 2, down = 3, left = 4 }

local function inBounds(p, x, y)
    return x >= 1 and y >= 1 and x <= p.w and y <= p.h
end

-- Tokens / nodes:
--   "." empty
--   "#" immovable
--   "M" movable (pushable)
--   "E" enemy
--   "F" flag
--   "K1".."K8" key colors
--   "L1".."L8" lock colors
--   "R" start (becomes ".")
--
-- Parsing:
-- - If a line contains whitespace, it is treated as whitespace-separated tokens.
-- - Otherwise, it is treated as a compact character grid (legacy), with:
--     '.' empty, '#' wall, 'R' start, 'F' flag, 'K' key (uncolored => K1), 'L' lock (uncolored => L1), 'E' enemy, 'M' movable
local function isKey(tok) return type(tok) == "string" and tok:match("^K[1-8]$") ~= nil end
local function isLock(tok) return type(tok) == "string" and tok:match("^L[1-8]$") ~= nil end
local function colorOf(tok) return tonumber(tok:sub(2, 2)) end

local function tokenizeLine(line)
    if line:find("%s") then
        local out = {}
        for t in line:gmatch("%S+") do
            out[#out + 1] = t
        end
        return out
    end
    local out = {}
    for i = 1, #line do
        out[#out + 1] = line:sub(i, i)
    end
    return out
end

function RobotPuzzle.fromLines(lines, opts)
    opts = opts or {}
    local h = #lines
    local w = 0
    for _, ln in ipairs(lines) do
        local toks = tokenizeLine(ln or "")
        w = math.max(w, #toks)
    end

    local grid = {}
    local rx, ry, dir = 1, 1, opts.dir or "up"

    for y = 1, h do
        grid[y] = {}
        local toks = tokenizeLine(lines[y] or "")
        for x = 1, w do
            local c = toks[x] or "."
            if c == "K" then c = "K1" end
            if c == "L" then c = "L1" end
            if c == "" then c = "." end
            if c == "R" then
                rx, ry = x, y
                c = "."
            end
            grid[y][x] = c
        end
    end

    return setmetatable({
        w = w,
        h = h,
        grid = grid,
        rx = rx,
        ry = ry,
        dir = dir,
        keys = { 0, 0, 0, 0, 0, 0, 0, 0 }, -- per-color counts
        objective = opts.objective or { kind = "flag" }, -- flag | kill_all_enemies | collect_all_keys
        solved = false,
        failed = false,
        reason = nil,
    }, RobotPuzzle)
end

function RobotPuzzle:cell(x, y)
    if not inBounds(self, x, y) then return "#" end
    return self.grid[y][x]
end

function RobotPuzzle:setCell(x, y, v)
    if not inBounds(self, x, y) then return end
    self.grid[y][x] = v
end

function RobotPuzzle:forwardPos()
    local d = DIRS[self.dir] or DIRS.up
    return self.rx + d[1], self.ry + d[2]
end

function RobotPuzzle:countRemaining(kind)
    local n = 0
    for y = 1, self.h do
        for x = 1, self.w do
            local c = self.grid[y][x]
            if kind == "enemy" and c == "E" then n = n + 1 end
            if kind == "key" and isKey(c) then n = n + 1 end
        end
    end
    return n
end

function RobotPuzzle:checkSolved()
    if self.solved or self.failed then return self.solved end
    local obj = self.objective or { kind = "flag" }
    if obj.kind == "kill_all_enemies" then
        if self:countRemaining("enemy") == 0 then
            self.solved = true
        end
    elseif obj.kind == "collect_all_keys" then
        if self:countRemaining("key") == 0 then
            self.solved = true
        end
    end
    return self.solved
end

function RobotPuzzle:move()
    local nx, ny = self:forwardPos()
    local c = self:cell(nx, ny)
    if c == "#" or c == "F" or c == "E" or isLock(c) or isKey(c) then
        self.failed = true
        self.reason = "blocked"
        return false
    end
    if c == "M" then
        local fx, fy = nx + (nx - self.rx), ny + (ny - self.ry)
        local ahead = self:cell(fx, fy)
        if ahead ~= "." then
            self.failed = true
            self.reason = "blocked"
            return false
        end
        self:setCell(fx, fy, "M")
        self:setCell(nx, ny, ".")
    end
    self.rx, self.ry = nx, ny
    return true
end

function RobotPuzzle:left_turn()
    local i = (DIR_IDX[self.dir] or 1)
    i = ((i + 2) % 4) + 1
    self.dir = DIR_ORDER[i]
end

function RobotPuzzle:right_turn()
    local i = (DIR_IDX[self.dir] or 1)
    i = (i % 4) + 1
    self.dir = DIR_ORDER[i]
end

function RobotPuzzle:half_turn()
    local i = (DIR_IDX[self.dir] or 1)
    i = ((i + 1) % 4) + 1
    self.dir = DIR_ORDER[i]
end

function RobotPuzzle:collect()
    local nx, ny = self:forwardPos()
    local c = self:cell(nx, ny)
    if isKey(c) then
        local col = colorOf(c) or 1
        self.keys[col] = (self.keys[col] or 0) + 1
        self:setCell(nx, ny, ".")
        self:checkSolved()
        return true
    end
    return false
end

function RobotPuzzle:unlock()
    local nx, ny = self:forwardPos()
    local c = self:cell(nx, ny)
    if isLock(c) then
        local col = colorOf(c) or 1
        if (self.keys[col] or 0) <= 0 then return false end
        self.keys[col] = self.keys[col] - 1
        self:setCell(nx, ny, ".")
        return true
    end
    return false
end

function RobotPuzzle:attack()
    local nx, ny = self:forwardPos()
    if self:cell(nx, ny) == "E" then
        self:setCell(nx, ny, ".")
        self:checkSolved()
        return true
    end
    return false
end

function RobotPuzzle:flag()
    local nx, ny = self:forwardPos()
    if self:cell(nx, ny) == "F" then
        if not self.objective or self.objective.kind == "flag" then
            self.solved = true
        end
        return true
    end
    return false
end

function RobotPuzzle:getVizState()
    local remainingEnemies = self:countRemaining("enemy")
    local remainingKeys = self:countRemaining("key")
    return {
        w = self.w,
        h = self.h,
        grid = self.grid,
        rx = self.rx,
        ry = self.ry,
        dir = self.dir,
        keys = self.keys,
        objective = self.objective,
        remainingEnemies = remainingEnemies,
        remainingKeys = remainingKeys,
        solved = self.solved,
        failed = self.failed,
        reason = self.reason,
    }
end

return RobotPuzzle

