--- SLAB build gallery — scrollable cards for player-buildable structures.

local Slab = require("vendor.slab")

local BuildGallery = {}
BuildGallery.__index = BuildGallery

function BuildGallery.new(structureSystem, onSelect, onClose, tileset)
    local self = setmetatable({
        structures = structureSystem,
        onSelect = onSelect,
        onClose = onClose,
        entries = {},
        tileset = tileset,
        open = false,
        selectedIdx = nil,
        previewCanvas = nil,
        previewCanvasW = 128,
        previewCanvasH = 128,
    }, BuildGallery)
    return self
end

local function ensurePreviewCanvas(self, w, h)
    if not self.previewCanvas or self.previewCanvasW ~= w or self.previewCanvasH ~= h then
        self.previewCanvas = love.graphics.newCanvas(w, h)
        self.previewCanvas:setFilter("nearest", "nearest")
        self.previewCanvasW, self.previewCanvasH = w, h
    end
end

function BuildGallery:drawPreview(def, w, h)
    ensurePreviewCanvas(self, w, h)
    love.graphics.push("all")
    love.graphics.setCanvas(self.previewCanvas)
    love.graphics.clear(0, 0, 0, 0)

    if not def or not self.tileset then
        love.graphics.setCanvas()
        love.graphics.pop()
        return
    end

    local tileId
    for _, layer in ipairs({ 'overlay', 'foreground', 'background' }) do
        local entries = def[layer]
        if entries then
            for _, e in ipairs(entries) do
                if e and e.tileId and e.tileId ~= 0 then
                    tileId = e.tileId
                    break
                end
            end
        end
        if tileId then break end
    end

    if tileId then
        local quad = self.tileset:getQuad(tileId)
        if quad then
            local rect = self.tileset:getRect(tileId)
            local iw, ih = rect.w, rect.h
            local scale = math.min(w / iw, h / ih)
            love.graphics.draw(
                self.tileset:getImage(),
                quad,
                (w - iw * scale) * 0.5,
                (h - ih * scale) * 0.5,
                0, scale, scale
            )
        end
    end

    love.graphics.setCanvas()
    love.graphics.pop()
end

function BuildGallery:rebuild()
    local entries = {}
    if self.structures and self.structures.defs then
        for _, def in pairs(self.structures.defs) do
            if def.player_buildable and def.id then
                entries[#entries + 1] = def
            end
        end
    end
    table.sort(entries, function(a, b)
        return tostring(a.id or "") < tostring(b.id or "")
    end)
    self.entries = entries
end

function BuildGallery:show()
    self:rebuild()
    self.open = true
    Slab.OpenDialog("BuildGallery")
end

function BuildGallery:hide()
    self.open = false
    Slab.CloseDialog()
end

function BuildGallery:isOpen()
    return self.open
end

function BuildGallery:capturesInput()
    return self:isOpen()
end

function BuildGallery:update(dt)
    if not self.open then return end

    local windowWidth = math.min(720, love.graphics.getWidth() - 40)
    local windowHeight = math.min(480, love.graphics.getHeight() - 40)

    if Slab.BeginDialog("BuildGallery", { Title = "Build Gallery", W = windowWidth, H = windowHeight }) then
        -- Title
        Slab.Text("Build Gallery")
        Slab.Separator()

        -- Gallery content area
        local contentWidth = windowWidth - 32
        
        if #self.entries == 0 then
            Slab.Text("No buildable structures.", { Align = "center" })
        else
            Slab.BeginLayout("BuildGalleryLayout", { Columns = 2 })
            Slab.SetLayoutColumn(1)

            -- Scrollable list of structures
            if Slab.BeginListBox("StructureList", { W = contentWidth * 0.6, H = windowHeight - 160 }) then
                for i, def in ipairs(self.entries) do
                    local cog = def.build_cog_cost or 0
                    local itemLabel = def.id .. " (" .. cog .. " cogs)"

                    if Slab.BeginListBoxItem("Item_" .. i, { Selected = self.selectedIdx == i }) then
                        Slab.Text(itemLabel)
                        
                        if Slab.IsListBoxItemClicked(1) then
                            self.selectedIdx = i
                        end
                        
                        Slab.EndListBoxItem()
                    end
                end
                Slab.EndListBox()
            end

            Slab.SetLayoutColumn(2)
            if self.selectedIdx and self.entries[self.selectedIdx] then
                local def = self.entries[self.selectedIdx]
                local pw, ph = contentWidth * 0.35, contentWidth * 0.35
                self:drawPreview(def, pw, ph)
                Slab.Image("BuildPreview", { Image = self.previewCanvas, W = pw, H = ph })
                Slab.Text(def.description or "No description.")
            else
                Slab.Text("Select a structure.")
            end

            Slab.EndLayout()
        end

        Slab.Separator()

        -- Buttons
        if Slab.Button("Build", { W = 100 }) then
            if self.selectedIdx and self.entries[self.selectedIdx] then
                local def = self.entries[self.selectedIdx]
                if self.onSelect then self.onSelect(def.id) end
                self:hide()
            end
        end

        Slab.SameLine()

        if Slab.Button("Close", { W = 100 }) then
            self:hide()
            if self.onClose then self.onClose() end
        end

        Slab.EndDialog()
    else
        self.open = false
    end
end

function BuildGallery:draw()
    -- Slab handles all dialog drawing in the update phase.
end

return BuildGallery
