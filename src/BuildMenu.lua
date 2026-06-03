--- BuildMenu: structure gallery + placement mode.

local TileMap = require("src.TileMap")
local BuildGallery = require("src.ui.BuildGallery")

local BuildMenu = {}
BuildMenu.__index = BuildMenu

function BuildMenu.new(structureSystem, tileset)
    local self = setmetatable({
        structures = structureSystem,
        state = "idle",
        selectedDef = nil,
        gallery = nil,
        tileset = tileset,
    }, BuildMenu)

    self.gallery = BuildGallery.new(
        structureSystem,
        function(defId) self:beginPlacement(defId) end,
        function() self.state = "idle" end,
        tileset
    )
    return self
end

function BuildMenu:openGallery()
    self.state = "gallery"
    self.gallery:show()
end

function BuildMenu:closeAll()
    self.state = "idle"
    self.selectedDef = nil
    self.gallery:hide()
end

function BuildMenu:isOpen()
    return self.state ~= "idle"
end

function BuildMenu:isPlacing()
    return self.state == "placing"
end

function BuildMenu:capturesInput()
    return self.gallery:isOpen() or self.state == "placing"
end

function BuildMenu:beginPlacement(defId)
    self.selectedDef = defId
    self.state = "placing"
    self.gallery:hide()
end

function BuildMenu:checkValid(map, mouseWx, mouseWy, groundTile)
    if not self.selectedDef then return false end
    local ts = map.tileSize
    local tx = math.floor(mouseWx / ts)
    local ty = math.floor(mouseWy / ts)
    return self.structures:canPlace(map, self.selectedDef, tx, ty, groundTile)
end

function BuildMenu:drawGhost(map, tileset, mouseWx, mouseWy, valid)
    local def = self.structures:getDef(self.selectedDef)
    if not def then return end
    local ts = map.tileSize
    local tx = math.floor(mouseWx / ts)
    local ty = math.floor(mouseWy / ts)
    local wx, wy = tx * ts, ty * ts

    if valid then
        love.graphics.setColor(0.55, 1.0, 0.7, 0.72)
    else
        love.graphics.setColor(1.0, 0.35, 0.35, 0.72)
    end

    local image = tileset:getImage()
    local function drawEntries(entries)
        if not entries then return end
        for _, e in ipairs(entries) do
            if e.tileId and e.tileId ~= 0 then
                local quad = tileset:getQuad(e.tileId)
                if quad then
                    love.graphics.draw(image, quad, wx + e.dx * ts, wy + e.dy * ts)
                end
            end
        end
    end
    drawEntries(def.background)
    drawEntries(def.foreground)
    love.graphics.setColor(1, 1, 1, 1)
end

function BuildMenu:update(dt, map, mouseWx, mouseWy, player, groundTile)
    self.gallery:update(dt)
    if self.state == "placing" then
        self._lastValid = self:checkValid(map, mouseWx, mouseWy, groundTile)
    end
end

function BuildMenu:mousepressed(button, map, mouseWx, mouseWy, player, groundTile)
    if self.gallery:isOpen() then
        return
    end

    if self.state == "placing" and button == 1 then
        if not self:checkValid(map, mouseWx, mouseWy, groundTile) then return end
        local def = self.structures:getDef(self.selectedDef)
        local cog = def.build_cog_cost or 0
        if cog > 0 and not player:removeCogs(cog) then return end
        local ts = map.tileSize
        local tx = math.floor(mouseWx / ts)
        local ty = math.floor(mouseWy / ts)
        if self.structures:place(map, self.selectedDef, tx, ty) then
            return true
        end
    end
    return false
end

function BuildMenu:draw(map, tileset, mouseWx, mouseWy, groundTile)
    if self.state == "placing" then
        self:drawGhost(map, tileset, mouseWx, mouseWy, self._lastValid)
    end
    self.gallery:draw()
end

return BuildMenu
