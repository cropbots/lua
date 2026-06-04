local CustomUI = require("src.ui.CustomUI")

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

    local function drawEntries(entries)
        if not entries then return end
        for _, e in ipairs(entries) do
            if e and e.tileId and e.tileId ~= 0 then
                local quad = self.tileset:getQuad(e.tileId)
                if quad then
                    local rect = self.tileset:getRect(e.tileId)
                    local iw, ih = rect.w, rect.h
                    local scale = math.min(w / iw, h / ih)
                    love.graphics.draw(
                        self.tileset:getImage(),
                        quad,
                        (w - iw * scale) * 0.5 + (e.dx or 0) * scale * iw,
                        (h - ih * scale) * 0.5 + (e.dy or 0) * scale * ih,
                        0, scale, scale
                    )
                end
            end
        end
    end

    drawEntries(def.background)
    drawEntries(def.foreground)
    drawEntries(def.overlay)

    love.graphics.setCanvas()
    love.graphics.pop()
end

function BuildGallery:getStructureTileInfo(def)
    if not def or not self.tileset then return nil, nil end
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
        return self.tileset:getImage(), quad
    end
    return nil, nil
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
end

function BuildGallery:hide()
    self.open = false
    CustomUI.focusedWidgetId = nil
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

    if CustomUI.beginDialog("BuildGallery", "Build Gallery", { W = windowWidth, H = windowHeight }) then
        local shouldClose = false
        if CustomUI.dialogCloseButton() then
            shouldClose = true
        end

        CustomUI.text("Build Gallery")
        CustomUI.separator()

        local contentWidth = windowWidth - 32
        
        if #self.entries == 0 then
            CustomUI.text("No buildable structures.", { Color = CustomUI.style.textDim })
        else
            local leftW = contentWidth * 0.65
            local rightW = contentWidth * 0.35 - 16

            CustomUI.beginLayout("BuildGalleryLayout", { Columns = 2, widths = { leftW, rightW } })
            CustomUI.setLayoutColumn(1)

            -- Scrollable Grid of structures
            if CustomUI.beginScrollArea("StructureGridScroll", { W = leftW, H = windowHeight - 160 }) then
                local cols = 3
                local cardW = math.floor((leftW - 24 - (cols - 1) * 8) / cols)
                local cardH = 100

                local numEntries = #self.entries
                local numRows = math.ceil(numEntries / cols)

                for r = 1, numRows do
                    CustomUI.beginLayout("GridRow_" .. r, { Columns = cols })
                    for c = 1, cols do
                        local idx = (r - 1) * cols + c
                        CustomUI.setLayoutColumn(c)
                        if idx <= numEntries then
                            local def = self.entries[idx]
                            local img, quad = self:getStructureTileInfo(def)
                            local label = def.id or ""
                            local costLabel = (def.build_cog_cost or 0) .. " cogs"
                            local selected = (self.selectedIdx == idx)

                            if CustomUI.gridItem("Card_" .. idx, img, quad, label, costLabel, selected, cardW, cardH) then
                                self.selectedIdx = idx
                            end
                        end
                    end
                    CustomUI.endLayout()
                end
                CustomUI.endScrollArea()
            end

            CustomUI.setLayoutColumn(2)
            if self.selectedIdx and self.entries[self.selectedIdx] then
                local def = self.entries[self.selectedIdx]
                local pw = rightW
                local ph = math.min(rightW, windowHeight - 220)
                local img, quad = self:getStructureTileInfo(def)
                if img and quad then
                    CustomUI.quadImage("BuildPreview", img, quad, pw, ph)
                else
                    CustomUI.text("No Preview", { Color = CustomUI.style.textDim })
                end
                CustomUI.text(def.id or "", { Color = CustomUI.style.text })
                CustomUI.text(def.description or "No description.", { Color = CustomUI.style.textDim })
            else
                CustomUI.text("Select a structure.")
            end

            CustomUI.endLayout()
        end

        CustomUI.separator()

        -- Buttons
        if CustomUI.button("Build", "Build", { W = 100 }) then
            if self.selectedIdx and self.entries[self.selectedIdx] then
                local def = self.entries[self.selectedIdx]
                if self.onSelect then self.onSelect(def.id) end
                self:hide()
            end
        end

        CustomUI.sameLine()

        if shouldClose or CustomUI.button("Close", "Close", { W = 100 }) then
            self:hide()
            if self.onClose then self.onClose() end
        end

        CustomUI.endDialog()
    else
        self.open = false
    end
end

function BuildGallery:draw()
    -- Handled globally by CustomUI.draw()
end

return BuildGallery
