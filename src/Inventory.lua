--- Player inventory: single HUD slot (top-left) + radial wheel (I / click slot).

local Inventory = {}
Inventory.__index = Inventory
local ItemIcons = require("src.ui.ItemIcons")

local HOTBAR_SIZE = 20
local HUD_SLOT_SIZE = 52
local HUD_ICON_SCALE = 1
local WHEEL_RADIUS = 160
local WHEEL_RING = 82
local WHEEL_SLOT = 48
local WHEEL_CENTER = 82
local WHEEL_SPIN = 0.28

--- @return Inventory
function Inventory.new()
    return setmetatable({
        counts = {},
        order = {},
        selectedSlot = 0,
        wheelOpen = false,
        crafting = nil,
        craftRects = {},
        craftHover = nil,
        craftScrollY = 0,
        craftPanelRect = nil,
        icons = ItemIcons.new(),
    }, Inventory)
end

function Inventory:setCrafting(adapter)
    self.crafting = adapter
end

function Inventory:add(itemId, count)
    if count <= 0 then return end
    if not self.counts[itemId] or self.counts[itemId] == 0 then
        self.order[#self.order + 1] = itemId
    end
    self.counts[itemId] = (self.counts[itemId] or 0) + count
end

function Inventory:remove(itemId, count)
    local have = self.counts[itemId] or 0
    if have < count then return false end
    self.counts[itemId] = have - count
    if self.counts[itemId] == 0 then
        self.counts[itemId] = nil
        for i, id in ipairs(self.order) do
            if id == itemId then
                table.remove(self.order, i)
                break
            end
        end
    end
    return true
end

function Inventory:get(itemId)
    return self.counts[itemId] or 0
end

function Inventory:snapshot()
    local counts = {}
    for id, n in pairs(self.counts) do
        counts[id] = n
    end
    local order = {}
    for i, id in ipairs(self.order) do
        order[i] = id
    end
    return {
        counts = counts,
        order = order,
        selectedSlot = self.selectedSlot or 0,
    }
end

function Inventory:applySnapshot(data)
    if not data then return end
    self.counts = {}
    self.order = {}
    for id, n in pairs(data.counts or {}) do
        self.counts[id] = n
    end
    for i, id in ipairs(data.order or {}) do
        self.order[i] = id
    end
    self.selectedSlot = data.selectedSlot or 0
end

function Inventory:items()
    local list = {}
    for _, id in ipairs(self.order) do
        local n = self.counts[id]
        if n and n > 0 then
            list[#list + 1] = { id = id, count = n }
        end
    end
    return list
end

function Inventory:priorityItems()
    local out = {}
    for i = 1, HOTBAR_SIZE do
        out[i] = self.order[i]
    end
    return out
end

function Inventory:selectedItem()
    return self.order[self.selectedSlot + 1]
end

function Inventory:getActiveItem()
    local id = self:selectedItem()
    if id then return { id = id } end
    return nil
end

function Inventory:toggleWheel()
    self.wheelOpen = not self.wheelOpen
end

function Inventory:isWheelOpen()
    return self.wheelOpen
end

function Inventory:cycleSelection(dir)
    local n = math.min(#self.order, HOTBAR_SIZE)
    if n == 0 then return end
    self.selectedSlot = (self.selectedSlot + dir) % n
end

function Inventory:transferOneTo(other, itemId)
    if self:remove(itemId, 1) then
        other:add(itemId, 1)
        return true
    end
    return false
end

--- Screen-space HUD slot rect (top-left, below hearts).
function Inventory:getHudSlotRect()
    local scale = math.max(0.8, math.min(1.35, love.graphics.getHeight() / 540))
    local size = HUD_SLOT_SIZE * scale
    return { x = 14 * scale, y = 14 * scale, w = size, h = size }
end

function Inventory:capturesPointer(mx, my)
    local hud = self:getHudSlotRect()
    if mx >= hud.x and mx < hud.x + hud.w and my >= hud.y and my < hud.y + hud.h then
        return true
    end
    if self.wheelOpen then
        local cx = love.graphics.getWidth() * 0.5
        local cy = love.graphics.getHeight() * 0.5
        local dx, dy = mx - cx, my - cy
        if math.sqrt(dx * dx + dy * dy) <= WHEEL_RADIUS + 40 then
            return true
        end
    end
    return false
end

--- @param mx number @param my number screen coords
function Inventory:handlePointer(mx, my, pressed)
    local hud = self:getHudSlotRect()
    if pressed and mx >= hud.x and mx < hud.x + hud.w and my >= hud.y and my < hud.y + hud.h then
        self:toggleWheel()
        return true
    end
    if self.wheelOpen and pressed then
        local craftId = self:craftingItemAt(mx, my)
        if craftId then
            if self.crafting and self.crafting.craft then
                local amount = 1
                if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
                    amount = 5
                elseif love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
                    amount = 10
                end
                self.crafting:craft(craftId, amount)
            end
            return true
        end
        local slotIndex = self:wheelItemAt(mx, my)
        if slotIndex then
            -- select slot even if empty
            self.selectedSlot = slotIndex - 1
            self.wheelOpen = false
            return true
        end
    end
    return false
end

function Inventory:handleWheel(mx, my, wheelY)
    if not self.wheelOpen then return false end
    if not self.craftPanelRect then return false end
    local r = self.craftPanelRect
    if mx < r.x or mx > r.x + r.w or my < r.y or my > r.y + r.h then
        return false
    end
    local rows = self.crafting and self.crafting.list and self.crafting:list() or {}
    local ICON = 42
    local GAP = 8
    local contentH = #rows * (ICON + GAP) + 12
    local maxScroll = math.max(0, contentH - r.h)
    self.craftScrollY = math.max(0, math.min(maxScroll, (self.craftScrollY or 0) - wheelY * 24))
    return true
end

function Inventory:craftingItemAt(mx, my)
    for _, row in ipairs(self.craftRects) do
        local r = row.rect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return row.id
        end
    end
    return nil
end

function Inventory:wheelItemAt(mx, my)
    local cx = love.graphics.getWidth() * 0.5
    local cy = love.graphics.getHeight() * 0.5
    local spin = love.timer.getTime() * WHEEL_SPIN
    local slotRadius = WHEEL_RADIUS - WHEEL_RING * 0.5
    local items = self:priorityItems()
    for idx = 0, HOTBAR_SIZE - 1 do
        local angle = spin + idx / HOTBAR_SIZE * math.pi * 2 - math.pi * 0.5
        local px = cx + math.cos(angle) * slotRadius
        local py = cy + math.sin(angle) * slotRadius
        local half = WHEEL_SLOT * 0.5
        if mx >= px - half and mx < px + half and my >= py - half and my < py + half then
            -- return slot index (1-based) even if empty
            return idx + 1
        end
    end
    return nil
end

--- @param tileset table|nil
--- @param slotTex userdata|nil
function Inventory:draw(tileset, slotTex)
    local hud = self:getHudSlotRect()
    if slotTex then
        love.graphics.draw(slotTex, hud.x, hud.y, 0, hud.w / slotTex:getWidth(), hud.h / slotTex:getHeight())
    else
        love.graphics.setColor(0.2, 0.2, 0.25, 0.9)
        love.graphics.rectangle("fill", hud.x, hud.y, hud.w, hud.h)
        love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.setColor(0.9, 0.78, 0.5, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", hud.x, hud.y, hud.w, hud.h)

    local sel = self:selectedItem()
    if sel and tileset then
        local pad = hud.w * 0.22
        local iw = (hud.w - pad * 2) * HUD_ICON_SCALE
        self:drawItemIcon(sel, tileset, hud.x + (hud.w - iw) * 0.5, hud.y + (hud.h - iw) * 0.5, iw, iw)
        local n = self:get(sel)
        if n > 1 then
            love.graphics.setColor(0.04, 0.025, 0.01, 0.82)
            love.graphics.rectangle("fill", hud.x + hud.w - 24, hud.y + hud.h - 16, 20, 12, 3, 3)
            love.graphics.setColor(1, 0.94, 0.78, 1)
            love.graphics.print(tostring(n), hud.x + hud.w - 22, hud.y + hud.h - 16)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)

    if self.wheelOpen then
        self:drawWheel(tileset, slotTex)
    end
end

function Inventory:drawItemIcon(itemId, tileset, x, y, w, h)
    if self.icons:draw(itemId, x, y, w, h, 1) then
        return
    end
    if not tileset then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print((itemId or "?"):sub(1, 4), x + 2, y + 2)
        return
    end
    local tileId = ({
        wheat_seed = 24,
        wheat = 25,
        tomato_seed = 229,
        tomato = 230,
        potato = 228,
        chopbot_summon = 59,
        cropbot_summon = 59,
        virat_summon = 59,
        virabird_summon = 59,
        carrot_seed = 26,
    })[itemId] or 59
    local quad = tileset:getQuad(tileId)
    if quad then
        love.graphics.draw(tileset:getImage(), quad, x, y, 0, w / 16, h / 16)
    else
        love.graphics.print(itemId:sub(1, 4), x + 2, y + 2)
    end
end

function Inventory:drawWheel(tileset, slotTex)
    local cx = love.graphics.getWidth() * 0.5
    local cy = love.graphics.getHeight() * 0.5
    local spin = love.timer.getTime() * WHEEL_SPIN
    local slotRadius = WHEEL_RADIUS - WHEEL_RING * 0.5
    local items = self:priorityItems()

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.setLineWidth(WHEEL_RING)
    love.graphics.circle("line", cx, cy, WHEEL_RADIUS - WHEEL_RING * 0.5)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", cx, cy, WHEEL_RADIUS)
    love.graphics.circle("line", cx, cy, WHEEL_RADIUS - WHEEL_RING)

    for idx = 0, HOTBAR_SIZE - 1 do
        local angle = spin + idx / HOTBAR_SIZE * math.pi * 2 - math.pi * 0.5
        local px = cx + math.cos(angle) * slotRadius
        local py = cy + math.sin(angle) * slotRadius
        local half = WHEEL_SLOT * 0.5
        if slotTex then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(slotTex, px - half, py - half, 0, WHEEL_SLOT / slotTex:getWidth(),
                WHEEL_SLOT / slotTex:getHeight())
        end
        local itemId = items[idx + 1]
        if itemId and tileset then
            self:drawItemIcon(itemId, tileset, px - half + 8, py - half + 8, WHEEL_SLOT - 16, WHEEL_SLOT - 16)
            local n = self:get(itemId)
            if n > 0 then
                love.graphics.print(tostring(n), px + half - 18, py + half - 22)
            end
        end
    end

    love.graphics.setColor(0, 0, 0, 0.46)
    love.graphics.circle("fill", cx, cy, WHEEL_CENTER * 0.5)
    local sel = self:selectedItem()
    local half = WHEEL_SLOT * 0.5
    if sel and tileset then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(slotTex, cx - half, cy - half, 0, WHEEL_SLOT / slotTex:getWidth(),
            WHEEL_SLOT / slotTex:getHeight())
        self:drawItemIcon(sel, tileset, cx - half + 8, cy - half + 8, WHEEL_SLOT - 16, WHEEL_SLOT - 16)
        local n = self:get(sel)
        if n > 1 then
            love.graphics.setColor(0.04, 0.025, 0.01, 0.8)
            love.graphics.rectangle("fill", cx + half - 22, cy + half - 14, 20, 12)
            love.graphics.setColor(1, 0.94, 0.78, 1)
            love.graphics.print(tostring(n), cx + half - 20, cy + half - 12)
        end
    end

    self:drawCraftingPanel(cx + WHEEL_RADIUS + 40, cy - WHEEL_RADIUS, 220, 300)
end

function Inventory:drawCraftingPanel(x, y, w, h)
    self.craftRects = {}
    self.craftHover = nil
    local ICON = 42
    local GAP = 8
    local cols = 1  -- Always 1 item wide
    local panelW = cols * ICON + math.max(0, cols - 1) * GAP + 12
    local rows = self.crafting and self.crafting.list and self.crafting:list() or {}
    local contentH = #rows * (ICON + GAP) + 12
    local panelH = math.min(h, math.max(ICON + 12, contentH))
    local maxScroll = math.max(0, contentH - panelH)
    self.craftScrollY = math.max(0, math.min(maxScroll, self.craftScrollY or 0))
    self.craftPanelRect = { x = x, y = y, w = panelW, h = panelH }

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x, y, panelW, panelH, 6, 6)
    love.graphics.setColor(0.85, 0.85, 0.85, 1)
    love.graphics.rectangle("line", x, y, panelW, panelH, 6, 6)

    if not self.crafting or not self.crafting.list then
        return
    end

    love.graphics.push("all")
    love.graphics.intersectScissor(x + 1, y + 1, panelW - 2, panelH - 2)
    local mx, my = love.mouse.getPosition()
    for i = 1, #rows do
        local row = rows[i]
        local col = (i - 1) % cols
        local rowIdx = math.floor((i - 1) / cols)
        local rect = {
            x = x + 6 + col * (ICON + GAP),
            y = y + 6 + rowIdx * (ICON + GAP) - self.craftScrollY,
            w = ICON,
            h = ICON,
        }
        self.craftRects[#self.craftRects + 1] = { id = row.id, rect = rect }
        if row.craftable then
            love.graphics.setColor(0.2, 0.35, 0.2, 0.9)
        else
            love.graphics.setColor(0.25, 0.25, 0.25, 0.9)
        end
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)

        if row.outCogs and row.outCogs > 0 then
            self:drawItemIcon("cogs", nil, rect.x + 8, rect.y + 8, ICON - 16, ICON - 16)
            love.graphics.setColor(1, 0.94, 0.78, row.craftable and 1 or 0.6)
            love.graphics.print(tostring(row.outCogs), rect.x + ICON - 18, rect.y + ICON - 16)
        else
            self:drawItemIcon(row.outItem, nil, rect.x + 8, rect.y + 8, ICON - 16, ICON - 16)
            local n = row.outCount or 1
            love.graphics.setColor(0.04, 0.025, 0.01, 0.75)
            love.graphics.rectangle("fill", rect.x + ICON - 20, rect.y + ICON - 14, 18, 12, 3, 3)
            love.graphics.setColor(1, 0.94, 0.78, row.craftable and 1 or 0.6)
            love.graphics.print(tostring(n), rect.x + ICON - 18, rect.y + ICON - 14)
        end

        if mx >= rect.x and mx <= rect.x + rect.w and my >= rect.y and my <= rect.y + rect.h then
            self.craftHover = row
        end
    end
    if self.craftHover then
        self:drawCraftTooltip(self.craftHover, x - 170, y + 30)
    end
    love.graphics.pop()

    if maxScroll > 0 then
        local sbH = math.max(16, (panelH / contentH) * panelH)
        local sbY = y + (self.craftScrollY / maxScroll) * (panelH - sbH)
        love.graphics.setColor(0.2, 0.2, 0.22, 0.75)
        love.graphics.rectangle("fill", x + panelW - 6, sbY, 4, sbH, 2, 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Inventory:drawCraftTooltip(row, x, y)
    local req = row.inItems or {}
    local entries = {}
    for id, amount in pairs(req) do
        entries[#entries + 1] = { id = id, amount = amount }
    end
    if row.inCogs and row.inCogs > 0 then
        entries[#entries + 1] = { id = "cogs", amount = row.inCogs }
    end
    table.sort(entries, function(a, b) return a.id < b.id end)

    local w = 160
    local h = math.max(34, 8 + #entries * 24)
    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    love.graphics.setColor(0.9, 0.9, 0.9, 1)
    love.graphics.rectangle("line", x, y, w, h, 4, 4)
    local cy = y + 6
    for _, e in ipairs(entries) do
        self:drawItemIcon(e.id, nil, x + 6, cy, 18, 18)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(tostring(e.amount), x + 28, cy + 2)
        cy = cy + 22
    end
end

return Inventory
