--- Loot chest UI: player wheel (left) + chest wheel (right), like Rust loot blocks.

local LootUI = {}
LootUI.__index = LootUI

local HOTBAR_SIZE = 20
local OUTER_RADIUS = 132
local RING_THICKNESS = 72
local SLOT_SIZE = 40
local SPIN_SPEED = 0.28

local CROP_ITEMS = { "wheat_seed", "tomato_seed", "potato" }

local function rollBasicCrate(inv)
    local crop = CROP_ITEMS[love.math.random(#CROP_ITEMS)]
    local cropAmt = love.math.random(0, 3)
    if cropAmt > 0 then
        inv:add(crop, cropAmt)
    end
    inv:add("cogs", love.math.random(3, 7))
    if love.math.random(0, 1) == 1 then
        inv:add("wood", 1)
    end
    if love.math.random(0, 1) == 1 then
        inv:add("stone", 1)
    end
end

local function rollLockedCrate(inv)
    local numCrops = (love.math.random(100) <= 75) and 1 or 2
    for _ = 1, numCrops do
        local crop = CROP_ITEMS[love.math.random(#CROP_ITEMS)]
        inv:add(crop, love.math.random(3, 5))
    end
    inv:add("cogs", love.math.random(16, 25))
    inv:add("wood", love.math.random(2, 5))
    inv:add("stone", love.math.random(3, 4))
end

local LOOT_GENERATORS = {
    basic_crate = rollBasicCrate,
    locked_loot = rollLockedCrate,
}

--- @return LootUI
function LootUI.new()
    return setmetatable({
        chests = {},
        openKey = nil,
        openLabel = nil,
    }, LootUI)
end

function LootUI:chestKey(tableId, area)
    return string.format("loot:%s:%.0f:%.0f", tableId, area.x, area.y)
end

function LootUI:open(tableId, area)
    local key = self:chestKey(tableId, area)
    if not self.chests[key] then
        local Inventory = require("src.Inventory")
        local chest = Inventory.new()
        local gen = LOOT_GENERATORS[tableId] or LOOT_GENERATORS.basic_crate
        gen(chest)
        self.chests[key] = chest
    end
    self.openKey = key
    self.openLabel = (tableId == "locked_loot") and "Locked Loot" or "Loot"
end

function LootUI:openCustom(key, inventory, label)
    if not key or not inventory then return end
    self.chests[key] = inventory
    self.openKey = key
    self.openLabel = label or "Loot"
end

function LootUI:close()
    self.openKey = nil
    self.openLabel = nil
end

function LootUI:isOpen()
    return self.openKey ~= nil
end

function LootUI:getOpenChest()
    if self.openKey then
        return self.chests[self.openKey]
    end
    return nil
end

function LootUI:getOpenLabel()
    return self.openLabel or "Loot"
end

function LootUI:bounds()
    local sw, sh = love.graphics.getDimensions()
    local w = math.min(1100, math.max(680, sw * 0.84))
    local h = math.min(760, math.max(420, sh * 0.74))
    return { x = (sw - w) * 0.5, y = (sh - h) * 0.5, w = w, h = h }
end

function LootUI:capturesPointer(mx, my)
    if not self:isOpen() then return false end
    return mx >= self:bounds().x and mx < self:bounds().x + self:bounds().w
        and my >= self:bounds().y and my < self:bounds().y + self:bounds().h
end

function LootUI:transferFromChest(chest, playerInv, player, itemId)
    if itemId == "cogs" and player then
        if chest:remove("cogs", 1) then
            player:addCogs(1)
            return true
        end
        return false
    end
    return chest:transferOneTo(playerInv, itemId)
end

function LootUI:wheelItemAt(inv, centerX, centerY, mx, my)
    local spin = love.timer.getTime() * SPIN_SPEED
    local slotRadius = OUTER_RADIUS - RING_THICKNESS * 0.5
    local items = inv:priorityItems()
    for idx = 0, HOTBAR_SIZE - 1 do
        local angle = spin + idx / HOTBAR_SIZE * math.pi * 2 - math.pi * 0.5
        local px = centerX + math.cos(angle) * slotRadius
        local py = centerY + math.sin(angle) * slotRadius
        local half = SLOT_SIZE * 0.5
        if mx >= px - half and mx < px + half and my >= py - half and my < py + half then
            return items[idx + 1]
        end
    end
    return nil
end

function LootUI:handleClick(playerInv, mx, my, player)
    if not self:isOpen() then return end
    local b = self:bounds()
    local left = { x = b.x + b.w * 0.29, y = b.y + b.h * 0.56 }
    local right = { x = b.x + b.w * 0.71, y = b.y + b.h * 0.56 }
    local chest = self:getOpenChest()
    if not chest then return end

    local fromPlayer = self:wheelItemAt(playerInv, left.x, left.y, mx, my)
    if fromPlayer then
        playerInv:transferOneTo(chest, fromPlayer)
        return
    end
    local fromChest = self:wheelItemAt(chest, right.x, right.y, mx, my)
    if fromChest then
        self:transferFromChest(chest, playerInv, player, fromChest)
    end
end

function LootUI:drawWheel(inv, tileset, slotTex, centerX, centerY, showCenter)
    local spin = love.timer.getTime() * SPIN_SPEED
    local slotRadius = OUTER_RADIUS - RING_THICKNESS * 0.5
    local items = inv:priorityItems()

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.setLineWidth(RING_THICKNESS)
    love.graphics.circle("line", centerX, centerY, OUTER_RADIUS - RING_THICKNESS * 0.5)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", centerX, centerY, OUTER_RADIUS)
    love.graphics.circle("line", centerX, centerY, OUTER_RADIUS - RING_THICKNESS)

    for idx = 0, HOTBAR_SIZE - 1 do
        local angle = spin + idx / HOTBAR_SIZE * math.pi * 2 - math.pi * 0.5
        local px = centerX + math.cos(angle) * slotRadius
        local py = centerY + math.sin(angle) * slotRadius
        local half = SLOT_SIZE * 0.5
        if slotTex then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(slotTex, px - half, py - half, 0, SLOT_SIZE / slotTex:getWidth(),
                SLOT_SIZE / slotTex:getHeight())
        end
        local itemId = items[idx + 1]
        if itemId then
            inv:drawItemIcon(itemId, tileset, px - half + 4, py - half + 4, SLOT_SIZE - 8, SLOT_SIZE - 8)
            local n = inv:get(itemId)
            if n > 0 then
                love.graphics.setColor(0.04, 0.025, 0.01, 0.8)
                love.graphics.rectangle("fill", px + half - 22, py + half - 14, 20, 12)
                love.graphics.setColor(1, 0.94, 0.78, 1)
                love.graphics.print(tostring(n), px + half - 20, py + half - 12)
            end
        end
    end

    if showCenter then
        love.graphics.setColor(0, 0, 0, 0.46)
        love.graphics.circle("fill", centerX, centerY, 36)
        local sel = inv:selectedItem()
        if sel then
            inv:drawItemIcon(sel, tileset, centerX - 20, centerY - 20, 40, 40)
            local n = inv:get(sel)
            if n > 1 then
                love.graphics.setColor(0.04, 0.025, 0.01, 0.8)
                love.graphics.rectangle("fill", centerX + 12, centerY + 12, 22, 12)
                love.graphics.setColor(1, 0.94, 0.78, 1)
                love.graphics.print(tostring(n), centerX + 14, centerY + 12)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function LootUI:draw(playerInv, tileset, slotTex)
    if not self:isOpen() then return end
    local chest = self:getOpenChest()
    if not chest then return end

    local b = self:bounds()
    local left = { x = b.x + b.w * 0.29, y = b.y + b.h * 0.56 }
    local right = { x = b.x + b.w * 0.71, y = b.y + b.h * 0.56 }

    self:drawWheel(playerInv, tileset, slotTex, left.x, left.y, true)
    self:drawWheel(chest, tileset, slotTex, right.x, right.y, false)

    love.graphics.setColor(0.05, 0.04, 0.08, 0.88)
    local labelY = left.y + OUTER_RADIUS + 18
    for _, pair in ipairs({ { left, "Player" }, { right, self:getOpenLabel() } }) do
        local center, label = pair[1], pair[2]
        local fw = love.graphics.getFont():getWidth(label) + 28
        love.graphics.rectangle("fill", center.x - fw * 0.5, labelY - 20, fw, 24)
        love.graphics.setColor(0.97, 0.89, 0.7, 1)
        love.graphics.print(label, center.x - love.graphics.getFont():getWidth(label) * 0.5, labelY)
        love.graphics.setColor(0.05, 0.04, 0.08, 0.88)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return LootUI
