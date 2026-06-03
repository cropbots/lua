local Tools = {}

Tools.tier = {
    wooden = 1,
    stone = 2,
    iron = 3,
    hold = 4,
    diamond = 5,
}

local function tierFromId(prefix, id)
    if not id or not id:match("_" .. prefix .. "$") then return nil end
    local t = id:gsub("_" .. prefix .. "$", "")
    return Tools.tier[t]
end

function Tools.getHoeTier(itemId)
    return tierFromId("hoe", itemId)
end

function Tools.getAxeTier(itemId)
    return tierFromId("axe", itemId)
end

function Tools.getPickaxeTier(itemId)
    return tierFromId("pickaxe", itemId)
end

return Tools
