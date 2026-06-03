--- StructureSystem: load defs, place structures, scatter, interact, highlights.

local TileMap = require("src.TileMap")

local StructureSystem = {}
StructureSystem.__index = StructureSystem

local bit = bit or require("bit")

local function hash_u32(i, seed, salt)
    local v = bit.band(bit.bxor(bit.bxor(i, seed), salt), 0xFFFFFFFF)
    v = bit.band(bit.bxor(v, bit.lshift(v, 16)), 0xFFFFFFFF)
    v = bit.band(v * 0x85ebca6b, 0xFFFFFFFF)
    v = bit.band(bit.bxor(v, bit.rshift(v, 13)), 0xFFFFFFFF)
    v = bit.band(v * 0xc2b2ae35, 0xFFFFFFFF)
    v = bit.band(bit.bxor(v, bit.rshift(v, 16)), 0xFFFFFFFF)
    return v
end

local function pointInRect(px, py, r)
    return px >= r.x and py >= r.y and px < r.x + r.w and py < r.y + r.h
end

local function playerInRange(px, py, area, range)
    if range <= 0 then return true end
    local nx = math.max(area.x, math.min(px, area.x + area.w))
    local ny = math.max(area.y, math.min(py, area.y + area.h))
    local dx, dy = px - nx, py - ny
    return math.sqrt(dx * dx + dy * dy) <= range
end

--- @return StructureSystem
function StructureSystem.new()
    return setmetatable({
        defs = {},
        interactors = {},
        placedSpawners = {},
        occupiedTiles = {},
        instances = {},
        shaking = {},
    }, StructureSystem)
end

local function tileKey(tx, ty)
    return tx .. "," .. ty
end

function StructureSystem:loadDefs(dir)
    local items = love.filesystem.getDirectoryItems(dir)
    for _, name in ipairs(items) do
        if name:match("%.lua$") then
            local path = dir .. "/" .. name
            local chunk = love.filesystem.load(path)
            if chunk then
                local ok, def = pcall(chunk)
                if ok and def and def.id then
                    self.defs[def.id] = def
                end
            end
        end
    end
end

function StructureSystem:getDef(id)
    return self.defs[id]
end

function StructureSystem:getAll()
    local list = {}
    for _, def in pairs(self.defs) do
        list[#list + 1] = def
    end
    return list
end

function StructureSystem:place(map, defId, tx, ty)
    local def = self.defs[defId]
    if not def then return false end
    if map and not self:canPlace(map, defId, tx, ty) then return false end

    local function writeLayer(layerConst, entries)
        if not map then return end
        if not entries then return end
        for _, e in ipairs(entries) do
            if e.tileId and e.tileId ~= 0 then
                map:setTile(layerConst, tx + e.dx, ty + e.dy, e.tileId)
            end
        end
    end

    writeLayer(TileMap.LAYER_BG, def.background)
    writeLayer(TileMap.LAYER_FG, def.foreground)
    writeLayer(TileMap.LAYER_OV, def.overlay)

    if map and def.colliders then
        for _, c in ipairs(def.colliders) do
            if c.mask and c.mask ~= 0 then
                map:setSolid(tx + c.dx, ty + c.dy, true)
            end
        end
    end

    return self:_trackInstance(map, defId, tx, ty)
end

function StructureSystem:_trackInstance(map, defId, tx, ty)
    local def = self.defs[defId]
    if not def then return false end

    local tileSize = map and map.tileSize or 16
    local gx, gy = tx * tileSize, ty * tileSize
    local gw, gh = def.width * tileSize, def.height * tileSize
    local groupRect = { x = gx, y = gy, w = gw, h = gh }
    local rangeWorld = (def.interact_range or 0) * tileSize

    if def.interactors then
        local actions = def.on_interact or {}
        for _, inter in ipairs(def.interactors) do
            local wx = (tx + inter.dx) * tileSize
            local wy = (ty + inter.dy) * tileSize
            self.interactors[#self.interactors + 1] = {
                structureId = defId,
                worldRect = { x = wx, y = wy, w = tileSize, h = tileSize },
                groupRect = groupRect,
                actions = actions,
                range = rangeWorld,
                spawner = def.spawner,
            }
        end
    end

    if def.spawner then
        self.placedSpawners[#self.placedSpawners + 1] = {
            rect = groupRect,
            def = def.spawner,
        }
    end

    for dy = 0, def.height - 1 do
        for dx = 0, def.width - 1 do
            self.occupiedTiles[tileKey(tx + dx, ty + dy)] = true
        end
    end

    self.instances[#self.instances + 1] = {
        defId = defId,
        tx = tx,
        ty = ty,
        width = def.width,
        height = def.height,
        rect = groupRect,
    }

    return true
end

function StructureSystem:canPlace(map, defId, tx, ty, groundTile)
    local def = self.defs[defId]
    if not def then return false end
    if tx < 0 or ty < 0 or tx + def.width > map.width or ty + def.height > map.height then
        return false
    end
    for dy = 0, def.height - 1 do
        for dx = 0, def.width - 1 do
            local x, y = tx + dx, ty + dy
            if self.occupiedTiles[tileKey(x, y)] then return false end
            if map:isSolid(x, y) then return false end
            if map:getTile(TileMap.LAYER_FG, x, y) ~= 0 then return false end
            if map:getTile(TileMap.LAYER_OV, x, y) ~= 0 then return false end
            if groundTile and map:getTile(TileMap.LAYER_BG, x, y) ~= groundTile then
                return false
            end
        end
    end
    return true
end

function StructureSystem:clearInteractors()
    self.interactors = {}
    self.placedSpawners = {}
    self.occupiedTiles = {}
    self.instances = {}
    self.shaking = {}
end

function StructureSystem:snapshot()
    local out = {}
    for _, inst in ipairs(self.instances) do
        out[#out + 1] = {
            defId = inst.defId,
            tx = inst.tx,
            ty = inst.ty,
        }
    end
    return out
end

function StructureSystem:restoreFromSnapshot(map, snapshot)
    self:clearInteractors()
    if type(snapshot) ~= "table" then return false end
    for _, item in ipairs(snapshot) do
        if item and item.defId and item.tx and item.ty then
            self:_trackInstance(map, item.defId, item.tx, item.ty)
        end
    end
    return true
end

function StructureSystem:findInstanceAt(tx, ty)
    for _, inst in ipairs(self.instances) do
        if tx >= inst.tx and tx < inst.tx + inst.width and ty >= inst.ty and ty < inst.ty + inst.height then
            return inst
        end
    end
    return nil
end

function StructureSystem:shakeInstance(inst, seconds)
    if not inst then return end
    self.shaking[inst] = math.max(self.shaking[inst] or 0, seconds or 0.16)
end

function StructureSystem:removeInstance(map, inst)
    if not map or not inst then return false end
    local def = self.defs[inst.defId]
    if not def then return false end

    local function clearLayer(layerConst, entries)
        if not entries then return end
        for _, e in ipairs(entries) do
            map:setTile(layerConst, inst.tx + e.dx, inst.ty + e.dy, 0)
        end
    end

    clearLayer(TileMap.LAYER_BG, def.background)
    clearLayer(TileMap.LAYER_FG, def.foreground)
    clearLayer(TileMap.LAYER_OV, def.overlay)

    if def.colliders then
        for _, c in ipairs(def.colliders) do
            if c.mask and c.mask ~= 0 then
                map:setSolid(inst.tx + c.dx, inst.ty + c.dy, false)
            end
        end
    end

    for y = inst.ty, inst.ty + def.height - 1 do
        for x = inst.tx, inst.tx + def.width - 1 do
            self.occupiedTiles[tileKey(x, y)] = nil
        end
    end

    local keepInter = {}
    for _, inter in ipairs(self.interactors) do
        if not (inter.groupRect.x == inst.rect.x and inter.groupRect.y == inst.rect.y
            and inter.groupRect.w == inst.rect.w and inter.groupRect.h == inst.rect.h) then
            keepInter[#keepInter + 1] = inter
        end
    end
    self.interactors = keepInter

    local keepInst = {}
    for _, other in ipairs(self.instances) do
        if other ~= inst then keepInst[#keepInst + 1] = other end
    end
    self.instances = keepInst
    self.shaking[inst] = nil
    return true
end

function StructureSystem:update(dt)
    for inst, t in pairs(self.shaking) do
        t = t - dt
        if t <= 0 then
            self.shaking[inst] = nil
        else
            self.shaking[inst] = t
        end
    end
end

--- Hovered interactor: mouse over tile AND player within interact range.
--- @return table|nil interactor
function StructureSystem:findHovered(mouseX, mouseY, playerX, playerY)
    for _, inter in ipairs(self.interactors) do
        if pointInRect(mouseX, mouseY, inter.worldRect)
            and playerInRange(playerX, playerY, inter.groupRect, inter.range) then
            return inter
        end
    end
    return nil
end

--- Execute interact actions; returns list of `{type, ...}` results.
function StructureSystem:executeInteract(inter)
    local results = {}
    for _, action in ipairs(inter.actions) do
        if action:match("^warp:") then
            results[#results + 1] = { type = "warp", target = action:sub(6) }
        elseif action:match("^loot:") then
            results[#results + 1] = {
                type = "loot",
                tableId = action:sub(6),
                area = inter.groupRect,
            }
        elseif action:match("^lock_puzzle:") then
            results[#results + 1] = {
                type = "lock_puzzle",
                puzzleId = action:sub(13),
                area = inter.groupRect,
            }
        elseif action:match("^chop:") then
            results[#results + 1] = {
                type = "chop",
                target = action:sub(6),
                area = inter.groupRect,
            }
        elseif action:match("^rock:") then
            results[#results + 1] = {
                type = "rock",
                target = action:sub(6),
                area = inter.groupRect,
            }
        end
    end
    return results
end

function StructureSystem:drawHighlight(inter)
    if not inter then return end
    local r = inter.groupRect
    love.graphics.setColor(1, 0.95, 0.2, 0.2)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
    love.graphics.setColor(1, 0.95, 0.2, 0.95)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
    love.graphics.setColor(1, 1, 1, 1)
end

function StructureSystem:drawShaking(map, tileset, view)
    if not map or not tileset then return end
    love.graphics.setColor(1, 1, 1, 1)
    for inst, _ in pairs(self.shaking) do
        local def = self.defs[inst.defId]
        if def then
            local jitterX = math.sin(love.timer.getTime() * 48) * 1.4
            local jitterY = math.cos(love.timer.getTime() * 37) * 1.0
            local ts = map.tileSize
            local function drawEntries(entries, layerConst)
                if not entries then return end
                for _, e in ipairs(entries) do
                    if e.tileId and e.tileId ~= 0 then
                        local wx = (inst.tx + e.dx) * ts + jitterX
                        local wy = (inst.ty + e.dy) * ts + jitterY
                        if wx + ts >= view.x and wy + ts >= view.y and wx <= view.x + view.w and wy <= view.y + view.h then
                            local quad = tileset:getQuad(e.tileId)
                            if quad then
                                love.graphics.draw(tileset:getImage(), quad, wx, wy)
                            end
                        end
                    end
                end
            end
            drawEntries(def.background, TileMap.LAYER_BG)
            drawEntries(def.foreground, TileMap.LAYER_FG)
            drawEntries(def.overlay, TileMap.LAYER_OV)
        end
    end
end

function StructureSystem:drawEffects()
end

function StructureSystem:scatter(map, defId, seed, filterFn)
    local def = self.defs[defId]
    if not def or not def.frequency or def.frequency <= 0 then return 0 end
    if def.max_per_map == 0 then return 0 end

    local area = map.width * map.height
    local target = math.min(math.floor(area * def.frequency + 0.5), def.max_per_map)
    if target <= 0 then return 0 end

    local placedRects = {}
    local count = 0
    local attempts = math.max(target * 12, 24)
    local maxX = map.width - def.width
    local maxY = map.height - def.height
    if maxX < 0 or maxY < 0 then return 0 end

    local minDist = def.min_distance or 0

    local function overlaps(rect)
        for _, other in ipairs(placedRects) do
            local pad = minDist
            if rect.x < other.x + other.w + pad and rect.x + rect.w + pad > other.x
                and rect.y < other.y + other.h + pad and rect.y + rect.h + pad > other.y then
                return true
            end
        end
        return false
    end

    for i = 0, attempts - 1 do
        repeat
            if count >= target then break end
            local rx = hash_u32(i, seed, 31) % (maxX + 1)
            local ry = hash_u32(i, seed, 47) % (maxY + 1)
            if filterFn and not filterFn(rx, ry) then break end

            local ts = map.tileSize
            local rect = { x = rx * ts, y = ry * ts, w = def.width * ts, h = def.height * ts }
            if not overlaps(rect) then
                if self:place(map, defId, rx, ry) then
                    placedRects[#placedRects + 1] = rect
                    count = count + 1
                end
            end
        until true
    end
    return count
end

return StructureSystem
