local Placement = {}
Placement.__index = Placement

function Placement.new(structureSystem, entitySystem)
    return setmetatable({
        structures = structureSystem,
        entities = entitySystem,
        items = {
            campfire_kit = { kind = "structure", id = "campfire" },
            chopbot_summon = { kind = "entity", id = "chopbot" },
            cropbot_summon = { kind = "entity", id = "cropbot" },
            virat_summon = { kind = "entity", id = "virat" },
            virabird_summon = { kind = "entity", id = "virabird" },
        },
    }, Placement)
end

function Placement:actionForItem(itemId)
    return self.items[itemId]
end

function Placement:tryPlace(itemId, map, tx, ty, wx, wy)
    local action = self:actionForItem(itemId)
    if not action then return false end

    if action.kind == "structure" then
        return self.structures:place(map, action.id, tx, ty)
    end

    if action.kind == "entity" then
        local spawned = self.entities:spawn(action.id, wx, wy)
        return spawned or false
    end

    return false
end

return Placement
