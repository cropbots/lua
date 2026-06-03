--- ExpeditionTracker: 5-minute expedition timer, stats, victory/corrupted screen.

local ExpeditionTracker = {}
ExpeditionTracker.__index = ExpeditionTracker

local EXPEDITION_DURATION = 300  -- 5 minutes
local DANGER_THRESHOLD   = 60   -- last 60 seconds = red aura

function ExpeditionTracker.new()
    return setmetatable({
        active       = false,
        timeLeft     = EXPEDITION_DURATION,
        itemsGained  = 0,
        cogsGained   = 0,
        enemiesSlain = 0,
        showResult   = false,
        corrupted    = false,
        resultAlpha  = 0,
    }, ExpeditionTracker)
end

function ExpeditionTracker:start()
    self.active       = true
    self.timeLeft     = EXPEDITION_DURATION
    self.itemsGained  = 0
    self.cogsGained   = 0
    self.enemiesSlain = 0
    self.showResult   = false
    self.corrupted    = false
    self.resultAlpha  = 0
end

function ExpeditionTracker:stop()
    self.active = false
end

function ExpeditionTracker:isActive()
    return self.active
end

function ExpeditionTracker:addItem(count)
    self.itemsGained = self.itemsGained + (count or 1)
end

function ExpeditionTracker:addCogs(count)
    self.cogsGained = self.cogsGained + (count or 1)
end

function ExpeditionTracker:addKill()
    self.enemiesSlain = self.enemiesSlain + 1
end

function ExpeditionTracker:update(dt)
    if not self.active then
        if self.showResult then
            self.resultAlpha = math.min(1, self.resultAlpha + dt * 2.5)
        end
        return
    end

    self.timeLeft = self.timeLeft - dt
    if self.timeLeft <= 0 then
        self.timeLeft = 0
        self.corrupted = true
        self.active = false
        self.showResult = true
        self.resultAlpha = 0
    end
end

--- Call when player warps OUT of expedition voluntarily.
function ExpeditionTracker:finishVictory()
    self.corrupted = false
    self.active = false
    self.showResult = true
    self.resultAlpha = 0
end

function ExpeditionTracker:isShowingResult()
    return self.showResult
end

function ExpeditionTracker:dismissResult()
    self.showResult = false
end

function ExpeditionTracker:isCorrupted()
    return self.corrupted
end

--- Draw the red danger aura when under 1 minute.
function ExpeditionTracker:drawDangerAura()
    if not self.active then return end
    if self.timeLeft >= DANGER_THRESHOLD then return end

    local intensity = 1.0 - (self.timeLeft / DANGER_THRESHOLD)
    intensity = math.min(1.0, intensity)
    local alpha = intensity * 0.45

    local sw, sh = love.graphics.getDimensions()
    -- Radial vignette: darker at edges
    local r = math.max(sw, sh) * 0.55
    love.graphics.setColor(0.7, 0, 0, alpha * 0.3)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Edge glow strips
    local edge = 60 + intensity * 80
    love.graphics.setColor(0.8, 0, 0, alpha * 0.6)
    love.graphics.rectangle("fill", 0, 0, edge, sh)
    love.graphics.rectangle("fill", sw - edge, 0, edge, sh)
    love.graphics.rectangle("fill", 0, 0, sw, edge)
    love.graphics.rectangle("fill", 0, sh - edge, sw, edge)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Draw the expedition timer HUD (top-center).
function ExpeditionTracker:drawTimer()
    if not self.active then return end
    local minutes = math.floor(self.timeLeft / 60)
    local seconds = math.floor(self.timeLeft % 60)
    local text = string.format("%d:%02d", minutes, seconds)

    local sw = love.graphics.getWidth()
    local font = love.graphics.getFont()
    local tw = font:getWidth(text)
    local th = font:getHeight()
    local px, py = sw * 0.5 - tw * 0.5 - 14, 12
    local pw, ph = tw + 28, th + 12

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", px, py, pw, ph, 6, 6)

    if self.timeLeft < DANGER_THRESHOLD then
        local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 4)
        love.graphics.setColor(1, 0.2, 0.2, 0.7 + pulse * 0.3)
    else
        love.graphics.setColor(0.92, 0.9, 0.88, 1)
    end
    love.graphics.print(text, px + 14, py + 6)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Draw the victory / corrupted result screen overlay.
function ExpeditionTracker:drawResultScreen()
    if not self.showResult then return end
    local alpha = self.resultAlpha
    if alpha <= 0 then return end

    local sw, sh = love.graphics.getDimensions()

    -- Full-screen dim
    love.graphics.setColor(0, 0, 0, 0.7 * alpha)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Panel
    local pw, ph = 420, 320
    local px = (sw - pw) * 0.5
    local py = (sh - ph) * 0.5

    if self.corrupted then
        love.graphics.setColor(0.15, 0.03, 0.03, 0.95 * alpha)
    else
        love.graphics.setColor(0.05, 0.1, 0.05, 0.95 * alpha)
    end
    love.graphics.rectangle("fill", px, py, pw, ph, 10, 10)

    if self.corrupted then
        love.graphics.setColor(0.8, 0.15, 0.15, alpha)
    else
        love.graphics.setColor(0.9, 0.75, 0.2, alpha)
    end
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", px, py, pw, ph, 10, 10)

    -- Title
    local title = self.corrupted and "CORRUPTED" or "VICTORY"
    local font = love.graphics.getFont()
    local tw = font:getWidth(title)
    if self.corrupted then
        love.graphics.setColor(1, 0.2, 0.2, alpha)
    else
        love.graphics.setColor(1, 0.85, 0.3, alpha)
    end
    love.graphics.print(title, px + (pw - tw) * 0.5, py + 24)

    -- Stats
    love.graphics.setColor(0.92, 0.9, 0.88, alpha)
    local lx = px + 50
    local ly = py + 70
    local lineH = 36

    local elapsed = EXPEDITION_DURATION - self.timeLeft
    local mins = math.floor(elapsed / 60)
    local secs = math.floor(elapsed % 60)

    local lines = {
        { "Time Taken",       string.format("%d:%02d", mins, secs) },
        { "Enemies Defeated", tostring(self.enemiesSlain) },
        { "Items Collected",  tostring(self.itemsGained) },
        { "Cogs Gained",      tostring(self.cogsGained) },
    }

    for _, line in ipairs(lines) do
        love.graphics.setColor(0.7, 0.68, 0.65, alpha)
        love.graphics.print(line[1], lx, ly)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.print(line[2], lx + 220, ly)
        ly = ly + lineH
    end

    if self.corrupted then
        love.graphics.setColor(0.6, 0.2, 0.2, alpha)
        love.graphics.print("Items and cogs were not awarded.", lx - 10, ly + 16)
    end

    -- Dismiss hint
    love.graphics.setColor(0.6, 0.6, 0.6, alpha * 0.8)
    local hint = "Click or press any key to continue"
    local hw = font:getWidth(hint)
    love.graphics.print(hint, px + (pw - hw) * 0.5, py + ph - 40)

    love.graphics.setColor(1, 1, 1, 1)
end

return ExpeditionTracker
