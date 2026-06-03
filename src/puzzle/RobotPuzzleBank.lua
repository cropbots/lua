--- RobotPuzzleBank: loads generated robot puzzles and serves them by difficulty/id.
local JsonDecode = require("src.JsonDecode")

local Bank = {}
Bank.__index = Bank

local function readAll(path)
    local ok, data = pcall(love.filesystem.read, path)
    if not ok then return nil end
    return data
end

local function joinRow(tokens)
    return table.concat(tokens, " ")
end

local function emptyGrid(w, h)
    local g = {}
    for y = 1, h do
        local row = {}
        for x = 1, w do row[x] = "." end
        g[y] = row
    end
    return g
end

local function gridToLines(g, w, h)
    local lines = {}
    for y = 1, h do
        lines[y] = joinRow(g[y])
    end
    return lines
end

local function genVeryEasy(idx)
    local w, h = 6, 6
    local g = emptyGrid(w, h)
    -- border walls for clarity
    for x = 1, w do g[1][x] = "#" g[h][x] = "#" end
    for y = 1, h do g[y][1] = "#" g[y][w] = "#" end
    g[2][2] = "R"

    local mode = (idx % 3)
    if mode == 0 then
        -- flag straight shot
        g[2][w - 1] = "F"
        return {
            id = ("ve_flag_%03d"):format(idx),
            difficulty = "VERY_EASY",
            robot = { dir = "right", objective = { kind = "flag" }, lines = gridToLines(g, w, h) },
            starter = "repeat 3:\n    move()\nend\nflag()\n",
        }
    elseif mode == 1 then
        -- collect all keys: one key in front
        g[2][3] = "K" .. tostring(((idx - 1) % 8) + 1)
        return {
            id = ("ve_keys_%03d"):format(idx),
            difficulty = "VERY_EASY",
            robot = { dir = "right", objective = { kind = "collect_all_keys" }, lines = gridToLines(g, w, h) },
            starter = "collect()\n",
        }
    else
        -- kill all enemies: one enemy in front
        g[2][3] = "E"
        return {
            id = ("ve_kill_%03d"):format(idx),
            difficulty = "VERY_EASY",
            robot = { dir = "right", objective = { kind = "kill_all_enemies" }, lines = gridToLines(g, w, h) },
            starter = "attack()\n",
        }
    end
end

local function genMediumHard(idx)
    local w, h = 8, 8
    local g = emptyGrid(w, h)
    for x = 1, w do g[1][x] = "#" g[h][x] = "#" end
    for y = 1, h do g[y][1] = "#" g[y][w] = "#" end
    g[2][2] = "R"

    local mode = (idx % 4)
    local color = ((idx - 1) % 8) + 1
    if mode == 0 then
        -- key + lock gate + flag (reach flag condition via flag() in front)
        g[2][3] = "K" .. color
        g[2][5] = "L" .. color
        g[2][w - 1] = "F"
        return {
            id = ("mh_gate_%03d"):format(idx),
            difficulty = "MEDIUM_HARD",
            robot = { dir = "right", objective = { kind = "flag" }, lines = gridToLines(g, w, h) },
            starter = "collect()\nrepeat 2:\n    move()\nend\nunlock()\nrepeat 2:\n    move()\nend\nflag()\n",
        }
    elseif mode == 1 then
        -- push movable into hole then get flag
        g[2][3] = "M"
        g[2][6] = "F"
        g[2][4] = "."; g[2][5] = "."
        return {
            id = ("mh_push_%03d"):format(idx),
            difficulty = "MEDIUM_HARD",
            robot = { dir = "right", objective = { kind = "flag" }, lines = gridToLines(g, w, h) },
            starter = "move()\nmove()\nmove()\nflag()\n",
        }
    elseif mode == 2 then
        -- two enemies
        g[2][3] = "E"
        g[2][4] = "E"
        return {
            id = ("mh_kill_%03d"):format(idx),
            difficulty = "MEDIUM_HARD",
            robot = { dir = "right", objective = { kind = "kill_all_enemies" }, lines = gridToLines(g, w, h) },
            starter = "attack()\nattack()\n",
        }
    else
        -- collect 2 keys different colors
        g[2][3] = "K" .. color
        g[3][2] = "K" .. (((color) % 8) + 1)
        return {
            id = ("mh_keys_%03d"):format(idx),
            difficulty = "MEDIUM_HARD",
            robot = { dir = "right", objective = { kind = "collect_all_keys" }, lines = gridToLines(g, w, h) },
            starter = "collect()\nright_turn()\nmove()\ncollect()\n",
        }
    end
end

function Bank.new()
    return setmetatable({
        puzzles = {},
        byDifficulty = { VERY_EASY = {}, MEDIUM_HARD = {} },
        loaded = false,
    }, Bank)
end

function Bank:load(path)
    if self.loaded then return true end
    path = path or "src/puzzle/generated_robot_puzzles.json"
    local raw = readAll(path)
    local data
    if raw then
        data = JsonDecode.decode(raw)
    end
    if not data then
        -- fallback: generate 50+50 procedurally
        local generated = {}
        for i = 1, 50 do generated[#generated + 1] = genVeryEasy(i) end
        for i = 1, 50 do generated[#generated + 1] = genMediumHard(i) end
        data = generated
    end
    for _, p in ipairs(data) do
        if p and p.id then
            self.puzzles[p.id] = p
            local diff = p.difficulty or "VERY_EASY"
            self.byDifficulty[diff] = self.byDifficulty[diff] or {}
            table.insert(self.byDifficulty[diff], p.id)
        end
    end
    self.loaded = true
    return true
end

function Bank:get(id)
    return self.puzzles[id]
end

function Bank:random(difficulty)
    local list = self.byDifficulty[difficulty or "VERY_EASY"] or {}
    if #list == 0 then return nil end
    local idx = love.math.random(1, #list)
    return self.puzzles[list[idx]]
end

return Bank

