local Crafting = {}
Crafting.__index = Crafting

function Crafting.new()
    return setmetatable({}, Crafting)
end

Crafting.recipes = {
    { id = "tomato_stew", label = "Tomato Stew", out = { item = "tomato_stew", count = 1 }, inItems = { tomato = 3 } },
    { id = "bread", label = "Bread", out = { item = "bread", count = 1 }, inItems = { wheat = 3 } },
    { id = "hashbrown", label = "Hashbrown", out = { item = "hashbrown", count = 1 }, inItems = { potato = 3 } },
    { id = "pizza", label = "Pizza", out = { item = "pizza", count = 1 }, inItems = { tomato = 2, wheat = 2 } },
    { id = "vegetable_stew", label = "Vegetable Stew", out = { item = "vegetable_stew", count = 1 }, inItems = { tomato = 2, potato = 2 } },
    { id = "potato_bread", label = "Potato Bread", out = { item = "potato_bread", count = 1 }, inItems = { wheat = 2, potato = 2 } },
    { id = "shepherd_pie", label = "Shepherd Pie", out = { item = "shepherd_pie", count = 1 }, inItems = { tomato = 2, wheat = 1, potato = 1 } },

    -- Summons (currency + materials)
    { id = "craft_cropbot_summon", label = "Cropbot Summon", out = { item = "cropbot_summon", count = 1 }, inItems = { wood = 10, stone = 5 }, inCogs = 25 },
    { id = "craft_chopbot_summon", label = "Chopbot Summon", out = { item = "chopbot_summon", count = 1 }, inItems = { wood = 15, stone = 3 }, inCogs = 25 },

    -- Crop -> cogs
    { id = "sell_wheat", label = "Wheat -> Cogs", outCogs = 2, inItems = { wheat = 1 } },
    { id = "sell_tomato", label = "Tomato -> Cogs", outCogs = 2, inItems = { tomato = 1 } },
    { id = "sell_potato", label = "Potato -> Cogs", outCogs = 2, inItems = { potato = 1 } },
}

local function canCraft(inv, recipe)
    for itemId, needed in pairs(recipe.inItems) do
        if inv:get(itemId) < needed then
            return false
        end
    end
    return true
end

local function canCraftWithPlayer(inv, player, recipe, amount)
    amount = amount or 1
    if recipe.inItems then
        for itemId, needed in pairs(recipe.inItems) do
            if inv:get(itemId) < (needed * amount) then
                return false
            end
        end
    end
    if recipe.inCogs and recipe.inCogs > 0 then
        if not player or (player.getCogs and player:getCogs() < recipe.inCogs * amount) then
            return false
        end
    end
    return true
end

function Crafting:getVisible(inv, player)
    local list = {}
    for _, recipe in ipairs(self.recipes) do
        list[#list + 1] = {
            recipe = recipe,
            craftable = canCraftWithPlayer(inv, player, recipe, 1),
        }
    end
    return list
end

function Crafting:craft(inv, player, recipeId, amount)
    amount = math.max(1, math.floor(amount or 1))
    local found
    for _, recipe in ipairs(self.recipes) do
        if recipe.id == recipeId then found = recipe break end
    end
    if not found or not canCraftWithPlayer(inv, player, found, amount) then return false end

    if found.inCogs and found.inCogs > 0 then
        if not player or not player.removeCogs or not player:removeCogs(found.inCogs * amount) then
            return false
        end
    end

    for itemId, needed in pairs(found.inItems or {}) do
        if not inv:remove(itemId, needed * amount) then return false end
    end
    if found.out then
        inv:add(found.out.item, (found.out.count or 1) * amount)
    end
    if found.outCogs and found.outCogs > 0 and player and player.addCogs then
        player:addCogs(found.outCogs * amount)
    end
    return true
end

return Crafting
