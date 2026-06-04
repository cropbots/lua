--- FarmScene: procedural farm generation and snapshot save/load.

local JsonUtil = require("src.JsonUtil")
local TileMap = require("src.TileMap")

local FarmScene = {}

FarmScene.FARM_WIDTH = 100
FarmScene.FARM_HEIGHT = 50
FarmScene.FARM_OUTER_MARGIN = 128
FarmScene.MAP_WIDTH = FarmScene.FARM_WIDTH + FarmScene.FARM_OUTER_MARGIN * 2
FarmScene.MAP_HEIGHT = FarmScene.FARM_HEIGHT + FarmScene.FARM_OUTER_MARGIN * 2
FarmScene.DECOR_SEED = 0xA5312D91

local SAVE_FILE = "farm_save.json"

function FarmScene.farmCoreRect()
    return {
        x = FarmScene.FARM_OUTER_MARGIN,
        y = FarmScene.FARM_OUTER_MARGIN,
        w = FarmScene.FARM_WIDTH,
        h = FarmScene.FARM_HEIGHT,
    }
end

function FarmScene.insetCoreRect()
    local r = FarmScene.farmCoreRect()
    return { x = r.x + 1, y = r.y + 1, w = r.w - 2, h = r.h - 2 }
end

--- @param map table @param structureSystem table @param farmBlockSystem table
--- @param groundTile number
--- @return number spawnX, number spawnY
function FarmScene.generate(map, structureSystem, farmBlockSystem, groundTile)
    map:fillLayer(TileMap.LAYER_BG, groundTile)

    local core = FarmScene.farmCoreRect()
    local ts = map.tileSize

    local function inCore(tx, ty)
        return tx >= core.x and tx < core.x + core.w
            and ty >= core.y and ty < core.y + core.h
    end

    local function inMargin(tx, ty)
        return not inCore(tx, ty)
    end

    structureSystem:clearInteractors()
    structureSystem:scatter(map, "tree_plains", FarmScene.DECOR_SEED, inMargin)
    structureSystem:scatter(map, "bush_plains", FarmScene.DECOR_SEED + 1, inMargin)
    structureSystem:scatter(map, "stump_plains", FarmScene.DECOR_SEED + 2, inMargin)

    local innerSeed = FarmScene.DECOR_SEED + 100
    structureSystem:scatter(map, "tree_plains", innerSeed, inCore)
    structureSystem:scatter(map, "bush_plains", innerSeed + 1, inCore)
    structureSystem:scatter(map, "rock_small_88", innerSeed + 2, inCore)
    structureSystem:scatter(map, "rock_small_89", innerSeed + 3, inCore)
    structureSystem:scatter(map, "rock_small_90", innerSeed + 4, inCore)
    structureSystem:scatter(map, "rock_big_94", innerSeed + 5, inCore)
    structureSystem:scatter(map, "stump_plains", innerSeed + 6, inCore)

    -- Bush border around farm core perimeter
    local def = structureSystem:getDef("bush_plains")
    if def then
        for x = core.x - 1, core.x + core.w do
            structureSystem:place(map, "bush_plains", x, core.y - 1)
            structureSystem:place(map, "bush_plains", x, core.y + core.h)
        end
        for y = core.y, core.y + core.h - 1 do
            structureSystem:place(map, "bush_plains", core.x - 1, y)
            structureSystem:place(map, "bush_plains", core.x + core.w, y)
        end
    end

    -- Expedition portal near farm center
    local portalX = core.x + math.floor(core.w / 2)
    local portalY = core.y + core.h - 2
    structureSystem:place(map, "warp_expedition", portalX, portalY)

    local inset = FarmScene.insetCoreRect()
    map:setBorderRect({
        x = inset.x * ts,
        y = inset.y * ts,
        w = inset.w * ts,
        h = inset.h * ts,
    })

    local spawnInset = FarmScene.insetCoreRect()
    local spawnX = (spawnInset.x + spawnInset.w * 0.5) * ts
    local spawnY = (spawnInset.y + spawnInset.h * 0.5) * ts
    return spawnX, spawnY
end

function FarmScene.save(map, farmBlockSystem, farmSystem, structureSystem)
    local data = {
        map = map:snapshot(),
        farmBlocks = farmBlockSystem:snapshot(),
        farm = farmSystem and farmSystem:snapshot() or nil,
        structures = structureSystem and structureSystem:snapshot() or nil,
    }
    local ok, err = love.filesystem.write(SAVE_FILE, JsonUtil.encode(data))
    return ok
end

--- @return boolean loaded
function FarmScene.load(map, farmBlockSystem, farmSystem, structureSystem)
    if not love.filesystem.getInfo(SAVE_FILE) then
        return false
    end
    local raw = love.filesystem.read(SAVE_FILE)
    if not raw then return false end

    local ok, parsed = pcall(function()
        return require("src.JsonDecode").decode(raw)
    end)
    if not ok or not parsed or not parsed.map then
        return false
    end
    if structureSystem and type(parsed.structures) ~= "table" then
        -- Old save format cannot restore interactors/instances reliably.
        return false
    end

    map:applySnapshot(parsed.map)
    farmBlockSystem:applySnapshot(parsed.farmBlocks)
    if farmSystem then
        farmSystem:applySnapshot(parsed.farm, map)
    end
    if structureSystem then
        structureSystem:restoreFromSnapshot(map, parsed.structures)
    end
    return true
end

function FarmScene.hasSave()
    return love.filesystem.getInfo(SAVE_FILE) ~= nil
end

function FarmScene.resetSave()
    if love.filesystem.getInfo(SAVE_FILE) then
        love.filesystem.remove(SAVE_FILE)
    end
end

return FarmScene
