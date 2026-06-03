--- SpawnerSystem: ticks spawner blocks when the player is in the same dungeon room.

local DungeonGenerator = require("src.DungeonGenerator")
local TileMap = require("src.TileMap")

local SpawnerSystem = {}
SpawnerSystem.__index = SpawnerSystem

--- @return SpawnerSystem
function SpawnerSystem.new()
    return setmetatable({ spawners = {} }, SpawnerSystem)
end

function SpawnerSystem:clear()
    self.spawners = {}
end

--- @param spawnerRect table world `{x,y,w,h}`
--- @param def table `{interval, total, entities}`
--- @param roomRect table|nil tile rect `{x,y,w,h}` in tile coords * tileSize later
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

--- Find the dungeon room containing a world position.
--- @param rooms table[] tile rects
--- @param wx number @param wy number @param tileSize number
--- @return table|nil
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

--- Register all spawner_block defs placed on the map (call after dungeon gen).
function SpawnerSystem:registerFromMap(map, structureSystem, rooms)
    self:clear()
    local ts = map.tileSize
    for _, sp in ipairs(structureSystem.placedSpawners or {}) do
        local room = roomAt(rooms, sp.rect.x + sp.rect.w * 0.5, sp.rect.y + sp.rect.h * 0.5, ts)
        self:register(sp.rect, sp.def, room)
    end
end

--- @param dt number
--- @param playerX number @param playerY number
--- @param map table
--- @param entitySystem table
--- @return table|nil roomLock rect when player is in an active spawner room
function SpawnerSystem:update(dt, playerX, playerY, map, entitySystem)
    local activeLock = nil
    local floorTile = DungeonGenerator.FLOOR_TILE

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

            local pick = entities[love.math.random(#entities)]
            local cx = sp.rect.x + sp.rect.w * 0.5
            local cy = sp.rect.y + sp.rect.h * 0.5
            local tx, ty = map:worldToTile(cx, cy)
            if not map:isSolid(tx, ty) and map:getTile(TileMap.LAYER_BG, tx, ty) == floorTile then
                local inst = entitySystem:spawn(pick, cx, cy)
                if inst then
                    sp.remaining = sp.remaining - 1
                end
            end
        until true
    end
    return activeLock
end

return SpawnerSystem
