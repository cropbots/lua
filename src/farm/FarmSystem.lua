local TileMap = require("src.TileMap")
local Crops = require("src.farm.Crops")

local FarmSystem = {}
FarmSystem.__index = FarmSystem

local function key(tx, ty)
    return tx .. ":" .. ty
end

function FarmSystem.new()
    return setmetatable({
        crops = {},
    }, FarmSystem)
end

function FarmSystem:isSoil(map, tx, ty)
    return map:getTile(TileMap.LAYER_BG, tx, ty) == Crops.SOIL_TILE
end

function FarmSystem:get(tx, ty)
    return self.crops[key(tx, ty)]
end

function FarmSystem:plant(map, tx, ty, seedItem)
    local cropId = Crops.seedToCrop[seedItem]
    if not cropId then return false end
    local def = Crops.defs[cropId]
    if not def then return false end
    if not self:isSoil(map, tx, ty) then return false end
    if self:get(tx, ty) then return false end

    self.crops[key(tx, ty)] = {
        tx = tx,
        ty = ty,
        cropId = cropId,
        stage = 1,
        timer = def.growSeconds,
    }
    map:setTile(TileMap.LAYER_BG, tx, ty, def.stages[1])
    map:setTile(TileMap.LAYER_OV, tx, ty, 0)
    return true
end

function FarmSystem:harvest(map, tx, ty, inventory)
    local plant = self:get(tx, ty)
    if not plant then return false end
    local def = Crops.defs[plant.cropId]
    if not def then return false end
    local finalStage = #def.stages
    if plant.stage < finalStage then return false end

    if plant.cropId == "wheat" then
        inventory:add("wheat", love.math.random(2, 3))
        inventory:add("wheat_seed", love.math.random(1, 2))
        self.crops[key(tx, ty)] = nil
        map:setTile(TileMap.LAYER_BG, tx, ty, Crops.SOIL_TILE)
        map:setTile(TileMap.LAYER_OV, tx, ty, 0)
    elseif plant.cropId == "tomato" then
        inventory:add("tomato", love.math.random(3, 4))
        local s = love.math.random(0, 1)
        if s > 0 then
            inventory:add("tomato_seed", s)
        end
        -- no replanting, goes back to stage 2
        plant.stage = 2
        plant.timer = def.growSeconds
        map:setTile(TileMap.LAYER_BG, tx, ty, def.stages[2])
        map:setTile(TileMap.LAYER_OV, tx, ty, 0)
    elseif plant.cropId == "potato" then
        inventory:add("potato", love.math.random(1, 4))
        inventory:add("potato", love.math.random(1, 2))
        self.crops[key(tx, ty)] = nil
        map:setTile(TileMap.LAYER_BG, tx, ty, Crops.SOIL_TILE)
        map:setTile(TileMap.LAYER_OV, tx, ty, 0)
    else
        inventory:add(def.harvestItem, 1)
        self.crops[key(tx, ty)] = nil
        map:setTile(TileMap.LAYER_BG, tx, ty, Crops.SOIL_TILE)
        map:setTile(TileMap.LAYER_OV, tx, ty, 0)
    end
    return true
end

function FarmSystem:update(dt, map)
    for _, plant in pairs(self.crops) do
        local def = Crops.defs[plant.cropId]
        if def then
            local finalStage = #def.stages
            if plant.stage < finalStage then
                plant.timer = plant.timer - dt
                if plant.timer <= 0 then
                    plant.stage = plant.stage + 1
                    map:setTile(TileMap.LAYER_BG, plant.tx, plant.ty, def.stages[plant.stage])
                    map:setTile(TileMap.LAYER_OV, plant.tx, plant.ty, 0)
                    if plant.stage < finalStage then
                        plant.timer = def.growSeconds
                    end
                end
            end
        end
    end
end

function FarmSystem:hoeTill(map, tx, ty)
    if not self:isSoil(map, tx, ty) and not self:get(tx, ty) then
        return false
    end
    if self:get(tx, ty) then
        return self:hoeUproot(map, tx, ty, nil)
    end
    map:setTile(TileMap.LAYER_BG, tx, ty, Crops.SOIL_TILE)
    map:setTile(TileMap.LAYER_OV, tx, ty, 0)
    return true
end

--- Uproot immature crop: returns one seed to inventory (if provided).
function FarmSystem:hoeUproot(map, tx, ty, inventory)
    local plant = self:get(tx, ty)
    if not plant then return false end
    local def = Crops.defs[plant.cropId]
    if not def then return false end
    local finalStage = #def.stages
    if plant.stage >= finalStage then
        return false
    end
    if inventory then
        inventory:add(def.seedItem, 1)
    end
    self.crops[key(tx, ty)] = nil
    map:setTile(TileMap.LAYER_BG, tx, ty, Crops.SOIL_TILE)
    map:setTile(TileMap.LAYER_OV, tx, ty, 0)
    return true
end

function FarmSystem:tryHoe(map, tx, ty, inventory)
    local plant = self:get(tx, ty)
    if plant then
        local def = Crops.defs[plant.cropId]
        if def and plant.stage >= #def.stages then
            return self:harvest(map, tx, ty, inventory)
        end
        return self:hoeUproot(map, tx, ty, inventory)
    end
    if self:isSoil(map, tx, ty) then
        return true
    end
    return self:hoeTill(map, tx, ty)
end

function FarmSystem:tryInteract(map, tx, ty, inventory)
    if self:harvest(map, tx, ty, inventory) then
        return true
    end
    local item = inventory:getActiveItem()
    if not item then return false end
    if not Crops.seedToCrop[item.id] then return false end
    if not inventory:remove(item.id, 1) then return false end
    local ok = self:plant(map, tx, ty, item.id)
    if not ok then
        inventory:add(item.id, 1)
        return false
    end
    return true
end

function FarmSystem:drawHighlight(map, tx, ty, inventory)
    local plant = self:get(tx, ty)
    if not self:isSoil(map, tx, ty) and not plant then return end
    local wx, wy = map:tileToWorld(tx, ty)
    local ts = map.tileSize

    local canUse = false
    if plant then
        local def = Crops.defs[plant.cropId]
        local finalStage = def and #def.stages or 0
        canUse = def and plant.stage >= finalStage
    else
        local item = inventory and inventory:getActiveItem() or nil
        canUse = item and Crops.seedToCrop[item.id] ~= nil
    end

    if canUse then
        love.graphics.setColor(1, 1, 0, 0.9)
    else
        love.graphics.setColor(1, 0.25, 0.25, 0.9)
    end
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", wx, wy, ts, ts)
    love.graphics.setColor(1, 1, 1, 1)
end

function FarmSystem:getHoverStageText(map, tx, ty)
    if not self:isSoil(map, tx, ty) then
        local plant = self:get(tx, ty)
        if not plant then return nil end
        local def = Crops.defs[plant.cropId]
        if not def then return nil end
        return string.format("%s stage %d/%d", plant.cropId, plant.stage, #def.stages)
    end
    local plant = self:get(tx, ty)
    if not plant then
        return "soil: empty"
    end
    local def = Crops.defs[plant.cropId]
    if not def then return "soil: planted" end
    return string.format("%s stage %d/%d", plant.cropId, plant.stage, #def.stages)
end

function FarmSystem:snapshot()
    local list = {}
    for _, plant in pairs(self.crops) do
        list[#list + 1] = {
            tx = plant.tx,
            ty = plant.ty,
            cropId = plant.cropId,
            stage = plant.stage,
            timer = plant.timer,
        }
    end
    return { plants = list }
end

function FarmSystem:applySnapshot(data, map)
    self.crops = {}
    if not data or not data.plants then return end
    for _, p in ipairs(data.plants) do
        local def = Crops.defs[p.cropId]
        if def then
            self.crops[key(p.tx, p.ty)] = {
                tx = p.tx,
                ty = p.ty,
                cropId = p.cropId,
                stage = p.stage,
                timer = p.timer,
            }
            map:setTile(TileMap.LAYER_BG, p.tx, p.ty, def.stages[p.stage or 1] or Crops.SOIL_TILE)
            map:setTile(TileMap.LAYER_OV, p.tx, p.ty, 0)
        end
    end
end

return FarmSystem
