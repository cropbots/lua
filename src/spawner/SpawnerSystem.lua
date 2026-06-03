local DungeonGenerator = require("src.DungeonGenerator")
local TileMap = require("src.TileMap")

local SpawnerSystem = {}
SpawnerSystem.__index = SpawnerSystem

function SpawnerSystem.new()
    return setmetatable({ spawners = {} }, SpawnerSystem)
end

function SpawnerSystem:clear()
    self.spawners = {}
end

function SpawnerSystem:register(spawnerRect, def, roomRect)
    self.spawners[#self.spawners + 1] = {
        rect = spawnerRect,
        def = def,
        roomRect = roomRect,
        remaining = def.total or 16,
        cooldown = 0,
    }
end

local function pointInRect(px, py, r)
    return px >= r.x and py >= r.y and px < r.x + r.w and py < r.y + r.h
end

local function roomAt(rooms, wx, wy, tileSize)
    local tx, ty = math.floor(wx / tileSize), math.floor(wy / tileSize)
    for _, room in ipairs(rooms) do
        if tx >= room.x and tx < room.x + room.w and ty >= room.y and ty < room.y + room.h then
            return {
                x = room.x * tileSize,
                y = room.y * tileSize,
                w = room.w * tileSize,
                h = room.h * tileSize,
            }
        end
    end
    return nil
end

function SpawnerSystem:registerFromMap(map, structureSystem, rooms)
    self:clear()
    local ts = map.tileSize
    for _, sp in ipairs(structureSystem.placedSpawners or {}) do
        local room = roomAt(rooms, sp.rect.x + sp.rect.w * 0.5, sp.rect.y + sp.rect.h * 0.5, ts)
        self:register(sp.rect, sp.def, room)
    end
end

local function isSpawnableTile(map, tx, ty)
    if map:isSolid(tx, ty) then return false end
    return map:getTile(TileMap.LAYER_BG, tx, ty) == DungeonGenerator.FLOOR_TILE
end

local function pickSpawnWorld(spawner, map)
    local ts = map.tileSize
    local cx = spawner.rect.x + spawner.rect.w * 0.5
    local cy = spawner.rect.y + spawner.rect.h * 0.5
    local tx, ty = map:worldToTile(cx, cy)

    local offsets = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
    }
    for i = 1, #offsets do
        local o = offsets[love.math.random(#offsets)]
        local sx, sy = tx + o[1], ty + o[2]
        if isSpawnableTile(map, sx, sy) then
            local wx, wy = map:tileToWorld(sx, sy)
            return wx + ts * 0.5, wy + ts * 0.5
        end
    end

    local room = spawner.roomRect or spawner.rect
    for _ = 1, 12 do
        local rx = room.x + love.math.random() * room.w
        local ry = room.y + love.math.random() * room.h
        local sx, sy = map:worldToTile(rx, ry)
        if isSpawnableTile(map, sx, sy) then
            local wx, wy = map:tileToWorld(sx, sy)
            return wx + ts * 0.5, wy + ts * 0.5
        end
    end

    return nil, nil
end

function SpawnerSystem:update(dt, playerX, playerY, map, entitySystem)
    local activeLock = nil

    for _, sp in ipairs(self.spawners) do
        repeat
        if sp.remaining <= 0 then break end

        local room = sp.roomRect or sp.rect
        if not pointInRect(playerX, playerY, room) then
            break
        end
        activeLock = room

        sp.cooldown = sp.cooldown - dt
        if sp.cooldown > 0 then break end
        sp.cooldown = sp.def.interval or 1.0

        local entities = sp.def.entities or {}
        if #entities == 0 then break end

        local ex, ey = pickSpawnWorld(sp, map)
        if not ex then break end

        local pick = entities[love.math.random(#entities)]
        local inst = entitySystem:spawn(pick, ex, ey)
        if inst then
            sp.remaining = sp.remaining - 1
        end
        until true
    end
    return activeLock
end

return SpawnerSystem
