local Slab = require("vendor.slab")
local utf8 = require("utf8")

local DialogueSystem = {}
DialogueSystem.__index = DialogueSystem

function DialogueSystem.new()
    return setmetatable({
        queue = {},
        active = nil,
        printed = "",
        charPos = 0,
        timer = 0,
        typeSpeed = 0.012,
        advanceKey = "space",
    }, DialogueSystem)
end

function DialogueSystem:say(name, text)
    if not text or text == "" then return end
    self.queue[#self.queue + 1] = {
        speaker = tostring(name or "System"),
        text = tostring(text),
    }
    if not self.active then
        self.active = table.remove(self.queue, 1)
        self.printed = ""
        self.charPos = 0
        self.timer = self.typeSpeed
    end
end

local function utf8Prefix(text, chars)
    if chars <= 0 then return "" end
    local i = utf8.offset(text, chars + 1)
    if i then
        return text:sub(1, i - 1)
    end
    return text
end

function DialogueSystem:update(dt)
    if not self.active then return end
    local msg = self.active.text
    if self.charPos >= utf8.len(msg) then
        self.printed = msg
        return
    end
    self.timer = self.timer - dt
    while self.timer <= 0 do
        self.charPos = self.charPos + 1
        self.printed = utf8Prefix(msg, self.charPos)
        self.timer = self.timer + self.typeSpeed
        if self.charPos >= utf8.len(msg) then
            self.printed = msg
            break
        end
    end
end

function DialogueSystem:advance()
    if not self.active then return end
    local msg = self.active.text
    if self.printed ~= msg then
        self.printed = msg
        self.charPos = utf8.len(msg)
        return
    end
    self.active = table.remove(self.queue, 1)
    self.printed = ""
    self.charPos = 0
    self.timer = self.typeSpeed
end

function DialogueSystem:keypressed(key)
    if key == self.advanceKey then
        self:advance()
    end
end

function DialogueSystem:keyreleased(key)
end

function DialogueSystem:draw()
    if not self.active then return end
    local sw, sh = love.graphics.getDimensions()
    local width = math.min(620, sw - 24)
    local height = 118
    local x = 12
    local y = sh - height - 12
    if Slab.BeginWindow("DialogueOverlay", {
            X = x,
            Y = y,
            W = width,
            H = height,
            IsMenuBar = false,
            AllowFocus = false,
            NoSavedSettings = true,
            BgColor = { 0.04, 0.04, 0.06, 0.92 },
            Title = "",
        }) then
        Slab.Text(self.active.speaker, { Color = { 1.0, 0.87, 0.56, 1.0 } })
        Slab.Separator()
        Slab.Text(self.printed, { W = width - 24 })
        local done = (self.printed == self.active.text)
        Slab.Text(done and "[Space] Continue" or "[Space] Skip", {
            Color = { 0.9, 0.9, 0.9, 0.8 }
        })
        Slab.EndWindow()
    end
end

function DialogueSystem:isActive()
    return self.active ~= nil
end

return DialogueSystem
