--- FarmBlockSystem: timer-driven single-tile farm blocks.

local TileMap = require("src.TileMap")

local FarmBlockSystem = {}
FarmBlockSystem.__index = FarmBlockSystem

--- @return FarmBlockSystem
function FarmBlockSystem.new()
    return setmetatable({
        types = {},
        blocks = {},
    }, FarmBlockSystem)
end

--- @param typeDef table `{id, stages, duration, ...}`
function FarmBlockSystem:registerType(typeDef)
    assert(typeDef.id and typeDef.stages and typeDef.duration,
        "FarmBlockTypeDef requires id, stages, duration")
    self.types[typeDef.id] = typeDef
end

local function key(tx, ty)
    return tx * 65536 + ty
end

--- @param tx number @param ty number @param typeId string @param stage number|nil
function FarmBlockSystem:add(tx, ty, typeId, stage)
    local typeDef = self.types[typeId]
    if not typeDef then return end
    stage = stage or 0
    self.blocks[key(tx, ty)] = {
        tx = tx,
        ty = ty,
        typeId = typeId,
        stage = stage,
        timer = typeDef.duration,
    }
    return self.blocks[key(tx, ty)]
end

function FarmBlockSystem:remove(tx, ty)
    self.blocks[key(tx, ty)] = nil
end

--- @return table|nil
function FarmBlockSystem:getAt(tx, ty)
    return self.blocks[key(tx, ty)]
end

--- @param dt number @param map table TileMap
function FarmBlockSystem:update(dt, map)
    for _, block in pairs(self.blocks) do
        repeat
            local typeDef = self.types[block.typeId]
            if not typeDef then break end

            local finalStage = #typeDef.stages - 1
            if block.stage >= finalStage then
                break
            end

            block.timer = block.timer - dt
            if block.timer <= 0 then
                block.stage = block.stage + 1
                local tileId = typeDef.stages[block.stage + 1]
                map:setTile(TileMap.LAYER_BG, block.tx, block.ty, tileId)
                if block.stage >= finalStage then
                    block.timer = math.huge
                else
                    block.timer = typeDef.duration
                end
            end
        until true
    end
end

function FarmBlockSystem:snapshot()
    local list = {}
    for _, block in pairs(self.blocks) do
        list[#list + 1] = {
            tx = block.tx,
            ty = block.ty,
            typeId = block.typeId,
            stage = block.stage,
            timer = block.timer,
        }
    end
    return { blocks = list }
end

function FarmBlockSystem:applySnapshot(t)
    self.blocks = {}
    if not t or not t.blocks then return end
    for _, b in ipairs(t.blocks) do
        self:add(b.tx, b.ty, b.typeId, b.stage)
        local block = self:getAt(b.tx, b.ty)
        if block then
            block.timer = b.timer
        end
    end
end

return FarmBlockSystem
