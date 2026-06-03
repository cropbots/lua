--- EntitySystem: load defs, spawn instances, update/draw with behavior trees.

local Gfx = require("src.Gfx")
local StatBlock = require("src.StatBlock")
local BehaviorTree = require("src.BehaviorTree")
local CollisionSystem = require("src.CollisionSystem")
local EntityActions = require("src.entity.EntityActions")
local EntityFlags = require("src.EntityFlags")
local bit = bit or require("bit")

local EntitySystem = {}
EntitySystem.__index = EntitySystem

local CONTACT_COOLDOWN = 0.3
local VIEW_HEIGHT = 300
local CHOPBOT_LEASH = 400
local _nextUid = 1

function EntitySystem.new()
    return setmetatable({
        defs = {},
        instances = {},
        sprites = {},
        damageEvents = {},
        onKill = nil,
    }, EntitySystem)
end

function EntitySystem:loadDefs(dirs)
    for _, dir in ipairs(dirs) do
        local items = love.filesystem.getDirectoryItems(dir)
        for _, name in ipairs(items) do
            if name:match("%.lua$") then
                local path = dir .. "/" .. name
                local chunk, err = love.filesystem.load(path)
                if chunk then
                    local ok, def = pcall(chunk)
                    if ok and def and def.id then
                        self.defs[def.id] = def
                        if def.sprite then
                            local imgOk, img = pcall(love.graphics.newImage, def.sprite)
                            if imgOk then
                                Gfx.setNearest(img)
                                self.sprites[def.id] = img
                            end
                        end
                    end
                end
            end
        end
    end
end

function EntitySystem:spawn(defId, x, y)
    local def = self.defs[defId]
    if not def then return nil end

    local stats = StatBlock.new()
    if def.stats then
        for k, v in pairs(def.stats) do
            stats:add(k, v)
        end
    end

    local inst = {
        uid = _nextUid,
        defId = defId,
        def = def,
        pos = { x = x, y = y },
        vel = { x = 0, y = 0 },
        hp = def.hp or 10,
        maxHp = def.hp or 10,
        flags = def.flags or 0,
        stats = stats,
        alive = true,
        contactCooldown = 0,
        currentTarget = nil,
        runtime = {},
        cropbot = {},
    }
    _nextUid = _nextUid + 1
    self.instances[#self.instances + 1] = inst
    return inst
end

local function hasFlag(flags, flagBit)
    return bit.band(flags, flagBit) ~= 0
end

local function worldHitbox(inst)
    local hb = inst.def.hitbox
    return {
        x = inst.pos.x + hb.x,
        y = inst.pos.y + hb.y,
        w = hb.w,
        h = hb.h,
    }
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function findNearestEnemy(instances, inst, maxRange)
    local best, bestD2 = nil, maxRange * maxRange
    for _, other in ipairs(instances) do
        if other.alive and other ~= inst and other.def.kind == "enemy" then
            local d2 = (other.pos.x - inst.pos.x) ^ 2 + (other.pos.y - inst.pos.y) ^ 2
            if d2 < bestD2 then
                best, bestD2 = other, d2
            end
        end
    end
    return best
end

local function updateTargeting(self, inst, playerInfo)
    inst.currentTarget = nil
    if inst.def.targetMode == "nearest_enemy" then
        inst.currentTarget = findNearestEnemy(self.instances, inst, inst.def.seekRange or 320)
    elseif inst.def.targetMode == "player" or hasFlag(inst.flags, EntityFlags.TARGET_PLAYER) then
        inst.currentTarget = {
            pos = {
                x = playerInfo.x + (playerInfo.w or 8) * 0.5,
                y = playerInfo.y + (playerInfo.h or 8) * 0.5,
            },
            alive = true,
        }
    end

    inst.stats.values.has_target = inst.currentTarget and 1 or 0
    inst.stats.values.target_in_range = 0
    inst.stats.values.player_in_range = 0

    if playerInfo then
        local px = playerInfo.x + (playerInfo.w or 8) * 0.5
        local py = playerInfo.y + (playerInfo.h or 8) * 0.5
        local pd = dist(inst.pos.x, inst.pos.y, px, py)
        inst.stats.values.player_in_range = (pd <= VIEW_HEIGHT * 0.75) and 1 or 0
    end

    if inst.currentTarget and inst.currentTarget.pos then
        local td = dist(inst.pos.x, inst.pos.y, inst.currentTarget.pos.x, inst.currentTarget.pos.y)
        local threshold = (inst.def.targetRange or 0.25) * VIEW_HEIGHT
        inst.stats.values.target_in_range = (td <= threshold) and 1 or 0
    end
end

function EntitySystem:update(dt, map, grid, playerInfo, worldCtx)
    worldCtx = worldCtx or {}
    self.damageEvents = {}

    for _, inst in ipairs(self.instances) do
        repeat
            if not inst.alive then break end

            if inst.contactCooldown > 0 then
                inst.contactCooldown = inst.contactCooldown - dt
            end

            updateTargeting(self, inst, playerInfo)

            if inst.defId == "chopbot" and playerInfo then
                local px = playerInfo.x + (playerInfo.w or 8) * 0.5
                local py = playerInfo.y + (playerInfo.h or 8) * 0.5
                if dist(inst.pos.x, inst.pos.y, px, py) > CHOPBOT_LEASH then
                    inst.pos.x, inst.pos.y = px, py
                    inst.vel.x, inst.vel.y = 0, 0
                end
            end

            inst.vel.x, inst.vel.y = 0, 0
            if inst.def.behavior then
                local ctx = { selectedActions = {} }
                BehaviorTree.evaluateTree(inst.def.behavior, inst, ctx)
                local usePath = hasFlag(inst.flags, EntityFlags.PATHFINDING)
                for _, action in ipairs(ctx.selectedActions) do
                    local actionName = type(action) == "table" and action.name or action
                    local actionParams = type(action) == "table" and action.params or {}
                    EntityActions.run(actionName, inst, dt, {
                        playerInfo = playerInfo,
                        map = map,
                        farmSystem = worldCtx.farmSystem,
                        cropbotInv = worldCtx.cropbotInv,
                        usePathfinding = usePath,
                        actionParams = actionParams,
                        viewHeight = VIEW_HEIGHT,
                    })
                end
            end

            if not hasFlag(inst.flags, EntityFlags.NO_MAP_COLLISION) then
                local hb = inst.def.hitbox
                local speed = math.sqrt(inst.vel.x * inst.vel.x + inst.vel.y * inst.vel.y)
                local steps = CollisionSystem.subSteps(speed, map.tileSize, dt)
                local stepDt = dt / steps
                for _ = 1, steps do
                    inst.pos.x = inst.pos.x + inst.vel.x * stepDt
                    local wh = worldHitbox(inst)
                    local colliders = CollisionSystem.queryGrid(grid, wh.x, wh.y, wh.w, wh.h)
                    inst.pos, inst.vel.x = CollisionSystem.resolveAxis(hb, inst.pos, inst.vel.x, colliders, "x")
                    inst.pos.y = inst.pos.y + inst.vel.y * stepDt
                    wh = worldHitbox(inst)
                    colliders = CollisionSystem.queryGrid(grid, wh.x, wh.y, wh.w, wh.h)
                    inst.pos, inst.vel.y = CollisionSystem.resolveAxis(hb, inst.pos, inst.vel.y, colliders, "y")
                end
            else
                inst.pos.x = inst.pos.x + inst.vel.x * dt
                inst.pos.y = inst.pos.y + inst.vel.y * dt
            end

            inst.pos = CollisionSystem.clampToRect(inst.def.hitbox, inst.pos, map:getBorderRect())

            if hasFlag(inst.flags, EntityFlags.TARGET_PLAYER) and playerInfo and inst.contactCooldown <= 0 then
                local a = worldHitbox(inst)
                local px, py = playerInfo.x, playerInfo.y
                local pw, ph = playerInfo.w or 16, playerInfo.h or 16
                if a.x < px + pw and a.x + a.w > px and a.y < py + ph and a.y + a.h > py then
                    self.damageEvents[#self.damageEvents + 1] = {
                        amount = inst.stats:get("damage", 1),
                        target = "player",
                    }
                    inst.contactCooldown = CONTACT_COOLDOWN
                end
            end

            if inst.hp <= 0 then
                inst.alive = false
            end
        until true
    end

    local alive = {}
    for _, inst in ipairs(self.instances) do
        if inst.alive then
            alive[#alive + 1] = inst
        elseif self.onKill then
            self.onKill(inst)
        end
    end
    self.instances = alive
end

function EntitySystem:processDamageEvents(player)
    for _, ev in ipairs(self.damageEvents) do
        if ev.target == "player" and player then
            player:applyDamage(ev.amount)
        end
    end
end

function EntitySystem:draw()
    for _, inst in ipairs(self.instances) do
        local img = self.sprites[inst.defId]
        if img then
            local dp = inst.def.drawParams or {}
            local ds = dp.destSize or { x = 16, y = 16 }
            local off = dp.offset or { x = -ds.x * 0.5, y = -ds.y * 0.5 }
            love.graphics.draw(
                img,
                inst.pos.x + off.x,
                inst.pos.y + off.y,
                0,
                ds.x / img:getWidth(),
                ds.y / img:getHeight()
            )
        end
    end
end

function EntitySystem:getAll()
    return self.instances
end

function EntitySystem:clear()
    self.instances = {}
end

return EntitySystem
