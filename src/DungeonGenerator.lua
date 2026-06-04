--- DungeonGenerator: seeded room/hallway dungeon for expeditions.

local TileMap = require("src.TileMap")

local DungeonGenerator = {}

DungeonGenerator.SEED = 0xD06E0B07
DungeonGenerator.WIDTH = 256
DungeonGenerator.HEIGHT = 256
DungeonGenerator.FLOOR_TILE = 226
DungeonGenerator.WALL_TILE = 225
DungeonGenerator.ROOM_TARGET = 140
DungeonGenerator.MARGIN = 8
DungeonGenerator.HALL_LENGTH = 3

local ROOM_SIZES = {
    {5, 4}, {4, 5}, {5, 5}, {5, 6}, {6, 5}, {6, 6},
    {6, 7}, {7, 6}, {7, 7}, {7, 8}, {8, 7}, {8, 8},
}

local DIRS = {
    {0, -1, "north"},
    {1, 0, "east"},
    {0, 1, "south"},
    {-1, 0, "west"},
}

local function Rng(seed)
    local state = seed
    return {
        next = function()
            state = (state * 1664525 + 1013904223) % 4294967296
            return state
        end,
        usize = function(self, upper)
            if upper <= 0 then return 0 end
            return self:next() % upper
        end,
    }
end

local function rectsOverlap(a, b, pad)
    pad = pad or 1
    return a.x < b.x + b.w + pad and a.x + a.w + pad > b.x
        and a.y < b.y + b.h + pad and a.y + a.h + pad > b.y
end

local function carveRect(map, rect, tile)
    for ty = rect.y, rect.y + rect.h - 1 do
        for tx = rect.x, rect.x + rect.w - 1 do
            map:setTile(TileMap.LAYER_BG, tx, ty, tile)
            map:setSolid(tx, ty, false)
            map:setDungeonWall(tx, ty, false)
        end
    end
end

local function isFloor(map, tx, ty)
    return map:getTile(TileMap.LAYER_BG, tx, ty) == DungeonGenerator.FLOOR_TILE
end

--- @param map table @param structureSystem table @param seed number|nil
--- @return table layout `{rooms, halls, edges}`
function DungeonGenerator.generate(map, structureSystem, seed)
    seed = seed or DungeonGenerator.SEED
    local rng = Rng(seed)
    local w, h = map.width, map.height
    local margin = DungeonGenerator.MARGIN

    map:fillLayer(TileMap.LAYER_BG, 0)
    map:fillLayer(TileMap.LAYER_FG, 0)
    map:fillLayer(TileMap.LAYER_OV, 0)

    local rooms = {}
    local halls = {}
    local edges = {}

    local cx = math.floor(w / 2) - 2
    local cy = math.floor(h / 2) - 2
    local start = { x = cx, y = cy, w = 5, h = 5 }
    rooms[1] = start
    carveRect(map, start, DungeonGenerator.FLOOR_TILE)

    local maxAttempts = DungeonGenerator.ROOM_TARGET * 40
    local attempts = 0

    while #rooms < DungeonGenerator.ROOM_TARGET and attempts < maxAttempts do
        repeat
        attempts = attempts + 1
        local roomIdx = rng:usize(#rooms)
        local room = rooms[roomIdx + 1]
        local dirIdx = rng:usize(4)
        local d = DIRS[dirIdx + 1]
        local dx, dy = d[1], d[2]

        local size = ROOM_SIZES[rng:usize(#ROOM_SIZES) + 1]
        local rw, rh = size[1], size[2]

        local hall
        if dy < 0 then
            hall = {
                x = room.x + math.floor((room.w - 2) / 2),
                y = room.y - DungeonGenerator.HALL_LENGTH,
                w = 2,
                h = DungeonGenerator.HALL_LENGTH,
            }
        elseif dy > 0 then
            hall = {
                x = room.x + math.floor((room.w - 2) / 2),
                y = room.y + room.h,
                w = 2,
                h = DungeonGenerator.HALL_LENGTH,
            }
        elseif dx > 0 then
            hall = {
                x = room.x + room.w,
                y = room.y + math.floor((room.h - 2) / 2),
                w = DungeonGenerator.HALL_LENGTH,
                h = 2,
            }
        else
            hall = {
                x = room.x - DungeonGenerator.HALL_LENGTH,
                y = room.y + math.floor((room.h - 2) / 2),
                w = DungeonGenerator.HALL_LENGTH,
                h = 2,
            }
        end

        local newRoom
        if dy < 0 then
            newRoom = { x = hall.x + math.floor((2 - rw) / 2), y = hall.y - rh, w = rw, h = rh }
        elseif dy > 0 then
            newRoom = { x = hall.x + math.floor((2 - rw) / 2), y = hall.y + hall.h, w = rw, h = rh }
        elseif dx > 0 then
            newRoom = { x = hall.x + hall.w, y = hall.y + math.floor((2 - rh) / 2), w = rw, h = rh }
        else
            newRoom = { x = hall.x - rw, y = hall.y + math.floor((2 - rh) / 2), w = rw, h = rh }
        end

        if newRoom.x < margin or newRoom.y < margin
            or newRoom.x + newRoom.w > w - margin
            or newRoom.y + newRoom.h > h - margin then
            break
        end

        local blocked = false
        for _, other in ipairs(rooms) do
            if rectsOverlap(newRoom, other, 1) then
                blocked = true
                break
            end
        end
        if blocked then break end

        carveRect(map, hall, DungeonGenerator.FLOOR_TILE)
        carveRect(map, newRoom, DungeonGenerator.FLOOR_TILE)
        halls[#halls + 1] = hall
        rooms[#rooms + 1] = newRoom
        edges[#edges + 1] = { roomIdx, #rooms }

        until true
    end

    -- Wall placement: non-floor adjacent to floor (8-way)
    for ty = 0, h - 1 do
        for tx = 0, w - 1 do
            repeat
            if isFloor(map, tx, ty) then break end
            local nearFloor = false
            for oy = -1, 1 do
                for ox = -1, 1 do
                    if isFloor(map, tx + ox, ty + oy) then
                        nearFloor = true
                        break
                    end
                end
                if nearFloor then break end
            end
            if nearFloor then
                map:setTile(TileMap.LAYER_FG, tx, ty, DungeonGenerator.WALL_TILE)
                map:setDungeonWall(tx, ty, true)
                map:setSolid(tx, ty, true)
            end
            until true
        end
    end

    structureSystem:clearInteractors()

    for _, hall in ipairs(halls) do
        if rng:usize(10) < 3 then
            if hall.w > hall.h then
                local tx = hall.x + math.floor(hall.w * 0.5)
                local ty = hall.y
                structureSystem:place(map, "lock_block_v", tx, ty)
            else
                local tx = hall.x
                local ty = hall.y + math.floor(hall.h * 0.5)
                structureSystem:place(map, "lock_block_h", tx, ty)
            end
        end
    end

    for _, room in ipairs(rooms) do
    end

    -- Loot/spawner/warp in ~40% of rooms (min 6)
    local blockTypes = { "loot_block", "spawner_block", "warp_block" }
    local roomBlockCount = math.max(6, math.floor(#rooms * 0.4))
    for i = 1, roomBlockCount do
        local room = rooms[rng:usize(#rooms) + 1]
        local bt = blockTypes[rng:usize(#blockTypes) + 1]
        local tx = room.x + rng:usize(math.max(1, room.w))
        local ty = room.y + rng:usize(math.max(1, room.h))
        structureSystem:place(map, bt, tx, ty)
    end

    map:setBorderRect(nil)

    return { rooms = rooms, halls = halls, edges = edges }
end

return DungeonGenerator
