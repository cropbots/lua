--- Player: WASD movement, dash, HP, collision resolution.

local CollisionSystem = require("src.CollisionSystem")

local Player = {}
Player.__index = Player

local ACCEL = 1800
local MAX_SPEED = 640
local DAMPING = 8
local DASH_SPEED = 1100
local DASH_DURATION = 0.07
local DASH_COOLDOWN = 0.5
local MAX_HP = 50

-- Rust draws player at ~0.25× texture size (scale 0.5 on half-res dest).
local DRAW_SCALE = 0.28

--- @param pos table `{x,y}` world position (feet / origin)
--- @param texture userdata|nil Love2D Image
--- @param hitbox table `{x,y,w,h}` relative to pos
--- @return Player
function Player.new(pos, texture, hitbox)
    return setmetatable({
        _pos = { x = pos.x, y = pos.y },
        _vel = { x = 0, y = 0 },
        _hitbox = hitbox,
        _texture = texture,
        _lastMoveDir = { x = 1, y = 0 },
        _dashTimer = 0,
        _dashCooldown = 0,
        _dashDir = { x = 0, y = 0 },
        _hp = MAX_HP,
        _maxHp = MAX_HP,
        _inventory = nil,
        _cogs = 0,
        _hooks = {},
    }, Player)
end

function Player:setHooks(hooks)
    self._hooks = hooks or {}
end

function Player:setInventory(inv)
    self._inventory = inv
end

function Player:getInventory()
    return self._inventory
end

function Player:getCogs()
    return self._cogs
end

function Player:addCogs(n)
    self._cogs = self._cogs + n
end

function Player:removeCogs(n)
    if self._cogs < n then return false end
    self._cogs = self._cogs - n
    return true
end

--- @param dt number
--- @param map table TileMap
--- @param grid table SpatialGrid
function Player:update(dt, map, grid)
    local input = { x = 0, y = 0 }
    if love.keyboard.isDown("d") then input.x = input.x + 1 end
    if love.keyboard.isDown("a") then input.x = input.x - 1 end
    if love.keyboard.isDown("w") then input.y = input.y - 1 end
    if love.keyboard.isDown("s") then input.y = input.y + 1 end

    if input.x ~= 0 and input.y ~= 0 then
        local len = math.sqrt(input.x * input.x + input.y * input.y)
        input.x = input.x / len
        input.y = input.y / len
    end

    if input.x ~= 0 or input.y ~= 0 then
        self._lastMoveDir = { x = input.x, y = input.y }
    end

    if self._dashCooldown > 0 then
        self._dashCooldown = math.max(0, self._dashCooldown - dt)
    end
    if self._dashTimer > 0 then
        self._dashTimer = math.max(0, self._dashTimer - dt)
    end

    if self._dashTimer <= 0 and self._dashCooldown <= 0 and love.keyboard.isDown("space") then
        local dir = input
        if dir.x == 0 and dir.y == 0 then
            dir = self._lastMoveDir
        end
        if dir.x ~= 0 or dir.y ~= 0 then
            self._dashDir = { x = dir.x, y = dir.y }
            self._vel = { x = dir.x * DASH_SPEED, y = dir.y * DASH_SPEED }
            self._dashTimer = DASH_DURATION
            self._dashCooldown = DASH_COOLDOWN
            if self._hooks.onDashStart then
                self._hooks.onDashStart(self)
            end
        end
    end

    if self._dashTimer > 0 then
        self._vel.x = self._dashDir.x * DASH_SPEED
        self._vel.y = self._dashDir.y * DASH_SPEED
    else
        self._vel.x = self._vel.x + input.x * ACCEL * dt
        self._vel.y = self._vel.y + input.y * ACCEL * dt
        local speed = math.sqrt(self._vel.x * self._vel.x + self._vel.y * self._vel.y)
        if speed > MAX_SPEED then
            self._vel.x = self._vel.x / speed * MAX_SPEED
            self._vel.y = self._vel.y / speed * MAX_SPEED
        end
        local decay = math.max(0, math.min(1, 1 - DAMPING * dt))
        self._vel.x = self._vel.x * decay
        self._vel.y = self._vel.y * decay
    end

    local tileSize = map.tileSize
    local speed = math.sqrt(self._vel.x * self._vel.x + self._vel.y * self._vel.y)
    local steps = CollisionSystem.subSteps(speed, tileSize, dt)
    local stepDt = dt / steps

    for _ = 1, steps do
        local pos = self._pos
        local hb = self._hitbox

        pos.x = pos.x + self._vel.x * stepDt
        local wx = pos.x + hb.x
        local wy = pos.y + hb.y
        local colliders = CollisionSystem.queryGrid(grid, wx, wy, hb.w, hb.h)
        pos, self._vel.x = CollisionSystem.resolveAxis(hb, pos, self._vel.x, colliders, "x")

        pos.y = pos.y + self._vel.y * stepDt
        wx = pos.x + hb.x
        wy = pos.y + hb.y
        colliders = CollisionSystem.queryGrid(grid, wx, wy, hb.w, hb.h)
        pos, self._vel.y = CollisionSystem.resolveAxis(hb, pos, self._vel.y, colliders, "y")

        self._pos = pos
    end

    self._pos = CollisionSystem.clampToRect(self._hitbox, self._pos, map:getBorderRect())
    if self._hooks.onUpdated then
        self._hooks.onUpdated(self, dt)
    end
end

function Player:draw()
    if not self._texture then return end
    local tw, th = self._texture:getWidth(), self._texture:getHeight()
    local dw, dh = tw * DRAW_SCALE, th * DRAW_SCALE
    love.graphics.draw(
        self._texture,
        self._pos.x - dw * 0.5,
        self._pos.y - dh * 0.5,
        0, DRAW_SCALE, DRAW_SCALE
    )
end

function Player:getPosition()
    return self._pos.x, self._pos.y
end

function Player:setPosition(x, y)
    self._pos = { x = x, y = y }
    self._vel = { x = 0, y = 0 }
    self._dashTimer = 0
    self._dashCooldown = 0
end

function Player:getWorldHitbox()
    return {
        x = self._pos.x + self._hitbox.x,
        y = self._pos.y + self._hitbox.y,
        w = self._hitbox.w,
        h = self._hitbox.h,
    }
end

function Player:healFull()
    self._hp = self._maxHp
end

function Player:isDead()
    return self._hp <= 0
end

function Player:applyDamage(amount)
    self._hp = math.max(0, self._hp - amount)
end

function Player:heal(amount)
    self._hp = math.min(self._maxHp, self._hp + amount)
end

function Player:getHp()
    return self._hp, self._maxHp
end

function Player:isDashing()
    return self._dashTimer > 0
end

function Player:isMoving(deadzone)
    deadzone = deadzone or 10
    local s = math.sqrt(self._vel.x * self._vel.x + self._vel.y * self._vel.y)
    return s > deadzone
end

function Player:getVelocity()
    return self._vel.x, self._vel.y
end

function Player:getTexture()
    return self._texture
end

function Player:getDrawScale()
    return DRAW_SCALE
end

function Player:getFacingDirection()
    return self._lastMoveDir.x, self._lastMoveDir.y
end

return Player
