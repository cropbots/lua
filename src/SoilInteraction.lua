--- Soil block hover highlight and plant/harvest interactions.

local TileMap = require("src.TileMap")

local SoilInteraction = {}

local SOIL_TYPE = "soil"

--- Register soil farm block type on the given FarmBlockSystem.
--- @param farmBlocks table
--- @param emptyTile number
function SoilInteraction.registerSoilType(farmBlocks, emptyTile)
    farmBlocks:registerType({
        id = SOIL_TYPE,
        stages = {
            emptyTile,
            emptyTile + 1,
            emptyTile + 2,
            emptyTile + 3,
            emptyTile + 4,
        },
        duration = 30.0,
        isSoil = true,
        seedCompat = { "wheat_seed", "carrot_seed" },
        cropItem = "wheat",
    })
end

--- Draw hover outline for soil under cursor.
--- @param map table @param farmBlocks table @param mouseWx number @param mouseWy number
--- @param inventory table|nil
function SoilInteraction.drawHighlight(map, farmBlocks, mouseWx, mouseWy, inventory)
    local tx, ty = map:worldToTile(mouseWx, mouseWy)
    local block = farmBlocks:getAt(tx, ty)
    if not block or block.typeId ~= SOIL_TYPE then return end

    local typeDef = farmBlocks.types[SOIL_TYPE]
    local wx, wy = map:tileToWorld(tx, ty)
    local ts = map.tileSize

    local compatible = true
    if block.stage == 0 and inventory then
        local item = inventory:getActiveItem()
        compatible = false
        if item then
            for _, seed in ipairs(typeDef.seedCompat) do
                if seed == item.id then
                    compatible = true
                    break
                end
            end
        else
            compatible = false
        end
    end

    if compatible then
        love.graphics.setColor(1, 1, 0, 0.8)
    else
        love.graphics.setColor(1, 0.2, 0.2, 0.8)
    end
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", wx, wy, ts, ts)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Handle interact key for soil planting or harvest.
--- @return boolean handled
function SoilInteraction.tryInteract(map, farmBlocks, tx, ty, inventory)
    local block = farmBlocks:getAt(tx, ty)
    if not block or block.typeId ~= SOIL_TYPE then return false end

    local typeDef = farmBlocks.types[SOIL_TYPE]
    local finalStage = #typeDef.stages - 1

    if block.stage == finalStage then
        inventory:add(typeDef.cropItem, 1)
        block.stage = 0
        block.timer = 0
        map:setTile(TileMap.LAYER_BG, tx, ty, typeDef.stages[1])
        return true
    end

    if block.stage == 0 then
        local item = inventory:getActiveItem()
        if not item then return false end
        local ok = false
        for _, seed in ipairs(typeDef.seedCompat) do
            if seed == item.id then ok = true break end
        end
        if not ok then return false end
        if not inventory:remove(item.id, 1) then return false end
        block.stage = 1
        block.timer = typeDef.duration
        map:setTile(TileMap.LAYER_BG, tx, ty, typeDef.stages[2])
        return true
    end

    return false
end

return SoilInteraction
