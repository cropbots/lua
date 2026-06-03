--- Camera: FOV-based zoom (matches Rust CAMERA_FOV = 300 world units tall).

local Camera = {}
Camera.__index = Camera

local VIEW_HEIGHT = 300
local SMOOTH = 8.0

--- @return Camera
function Camera.new()
    local w, h = love.graphics.getDimensions()
    return setmetatable({
        x = 0,
        y = 0,
        viewH = VIEW_HEIGHT,
        viewW = VIEW_HEIGHT * (w / h),
        screenW = w,
        screenH = h,
    }, Camera)
end

function Camera:setSize(w, h)
    self.screenW = w
    self.screenH = h
    self.viewW = self.viewH * (w / h)
end

function Camera:getScale()
    return self.screenH / self.viewH
end

--- @param tx number @param ty number @param dt number
function Camera:follow(tx, ty, dt)
    local targetX = tx - self.viewW * 0.5
    local targetY = ty - self.viewH * 0.5
    local t = math.min(1, SMOOTH * dt)
    self.x = self.x + (targetX - self.x) * t
    self.y = self.y + (targetY - self.y) * t
end

--- @param sx number @param sy number
--- @return number wx, number wy
function Camera:screenToWorld(sx, sy)
    local scale = self:getScale()
    return self.x + sx / scale, self.y + sy / scale
end

function Camera:apply()
    local scale = self:getScale()
    love.graphics.push()
    love.graphics.scale(scale, scale)
    love.graphics.translate(-self.x, -self.y)
end

function Camera:reset()
    love.graphics.pop()
end

--- Visible world rect `{x,y,w,h}` for culling.
function Camera:getViewRect()
    return { x = self.x, y = self.y, w = self.viewW, h = self.viewH }
end

return Camera
