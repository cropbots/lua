local ItemIcons = {}
ItemIcons.__index = ItemIcons

local ITEM_TO_FILE = {
    wheat_seed = "seed_wheat",
    tomato_seed = "seed_tomato",
    potato = "potato",
    wheat = "wheat",
    tomato = "tomato",

    tomato_stew = "tomato_stew",
    bread = "bread",
    hashbrown = "hashbrown",
    pizza = "pizza",
    vegetable_stew = "vegetable_stew",
    potato_bread = "potato_dumpling",
    shepherd_pie = "shepherd_pie",
    wood = "wood",
    stone = "stone",

    wooden_hoe = "wooden_hoe",
    stone_hoe = "stone_hoe",
    iron_hoe = "iron_hoe",
    hold_hoe = "gold_hoe",
    diamond_hoe = "diamond_hoe",
    wooden_axe = "wooden_axe",
    stone_axe = "stone_axe",
    iron_axe = "iron_axe",
    hold_axe = "gold_axe",
    diamond_axe = "diamond_axe",
    soil = "assets/tiles/228.png",
    cogs = "assets/items/gear.png",
}

function ItemIcons.new()
    return setmetatable({ cache = {} }, ItemIcons)
end

local function loadImage(path)
    local ok, img = pcall(love.graphics.newImage, path)
    if not ok then return nil end
    img:setFilter("nearest", "nearest")
    return img
end

function ItemIcons:getImage(itemId)
    if self.cache[itemId] ~= nil then
        return self.cache[itemId]
    end
    local name = ITEM_TO_FILE[itemId]
    if not name then
        self.cache[itemId] = false
        return nil
    end
    local path
    if name:match("^assets/") then
        path = name
    else
        path = "assets/items/" .. name .. ".png"
    end
    local img = loadImage(path)
    self.cache[itemId] = img or false
    return img
end

function ItemIcons:draw(itemId, x, y, w, h, alpha)
    local img = self:getImage(itemId)
    if not img then return false end
    alpha = alpha or 1
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(img, x, y, 0, w / img:getWidth(), h / img:getHeight())
    love.graphics.setColor(1, 1, 1, 1)
    return true
end

return ItemIcons
