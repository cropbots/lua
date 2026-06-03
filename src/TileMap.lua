--- TileMap.lua
--- Manages a layered tile map with chunked canvas rendering.
--- Three tile layers (background, foreground, overlay), two boolean masks
--- (solid, dungeonWall), and a 2D grid of Chunk objects each backed by
--- three 512×512 Love2D canvases.

local TileMap = {}
TileMap.__index = TileMap

-- ---------------------------------------------------------------------------
-- Layer constants
-- ---------------------------------------------------------------------------

--- Background layer index.
TileMap.LAYER_BG = 1

--- Foreground layer index.
TileMap.LAYER_FG = 2

--- Overlay layer index.
TileMap.LAYER_OV = 3

-- ---------------------------------------------------------------------------
-- Internal constants
-- ---------------------------------------------------------------------------

--- Tiles per chunk edge (32×32 tiles per chunk).
local CHUNK_SIZE = 32

--- Canvas size in pixels (32 tiles × 16 px/tile = 512 px).
local CANVAS_SIZE = 512

--- Maximum number of dirty chunks rebuilt per `TileMap:update()` call.
--- Spreading rebuilds across frames prevents per-frame GPU spikes.
local CHUNK_REBUILD_PER_FRAME = 4

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

--- Create a new TileMap.
---
--- Allocates three flat int arrays (`bg`, `fg`, `ov`) of length
--- `width * height`, initialised to 0.  Allocates two flat bool arrays
--- (`solid`, `dungeonWall`) initialised to `false`.  Builds a 2D `chunks`
--- table indexed by `[cy][cx]`; each Chunk receives three 512×512 Love2D
--- canvases (one per layer) and starts with all dirty flags set to `true`.
---
--- Index formula (1-based Lua arrays):
---   `index = ty * width + tx + 1`
---
--- @param width   number  Map width in tiles
--- @param height  number  Map height in tiles
--- @param tileSize number World units per tile (typically 16)
--- @param tileset  table  TileSet reference used during chunk rebuild
--- @return TileMap
function TileMap.new(width, height, tileSize, tileset)
    local self = setmetatable({}, TileMap)

    -- Map dimensions
    self.width    = width
    self.height   = height
    self.tileSize = tileSize
    self.tileset  = tileset

    -- Flat tile-ID arrays (int), length = width * height, initialised to 0
    local size = width * height
    local bg = {}
    local fg = {}
    local ov = {}
    for i = 1, size do
        bg[i] = 0
        fg[i] = 0
        ov[i] = 0
    end
    self.bg = bg
    self.fg = fg
    self.ov = ov

    -- Flat boolean arrays, initialised to false
    local solid      = {}
    local dungeonWall = {}
    for i = 1, size do
        solid[i]       = false
        dungeonWall[i] = false
    end
    self.solid       = solid
    self.dungeonWall = dungeonWall

    -- Chunk grid dimensions
    self.chunkW = math.ceil(width  / CHUNK_SIZE)
    self.chunkH = math.ceil(height / CHUNK_SIZE)

    -- Build 2D chunks table [cy][cx], 0-based chunk coordinates
    local chunks = {}
    for cy = 0, self.chunkH - 1 do
        chunks[cy] = {}
        for cx = 0, self.chunkW - 1 do
            chunks[cy][cx] = {
                cx       = cx,
                cy       = cy,
                canvasBg = love.graphics.newCanvas(CANVAS_SIZE, CANVAS_SIZE),
                canvasFg = love.graphics.newCanvas(CANVAS_SIZE, CANVAS_SIZE),
                canvasOv = love.graphics.newCanvas(CANVAS_SIZE, CANVAS_SIZE),
                dirtyBg  = true,
                dirtyFg  = true,
                dirtyOv  = true,
            }
        end
    end
    self.chunks = chunks

    -- World-space player boundary; nil means no border clamping
    self.borderRect = nil

    return self
end

-- ---------------------------------------------------------------------------
-- Internal helper: select the flat array for a given layer constant.
-- Returns the array, or nil if the layer is invalid.
-- ---------------------------------------------------------------------------

--- @param self  TileMap
--- @param layer number  One of TileMap.LAYER_BG / LAYER_FG / LAYER_OV
--- @return table|nil
local function layerArray(self, layer)
    if layer == TileMap.LAYER_BG then return self.bg
    elseif layer == TileMap.LAYER_FG then return self.fg
    elseif layer == TileMap.LAYER_OV then return self.ov
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Tile read / write
-- ---------------------------------------------------------------------------

--- Write a tile ID to the specified layer at tile coordinates (tx, ty).
--- Marks the containing chunk's dirty flag for that layer.
--- Silently ignores out-of-bounds coordinates.
---
--- @param layer number  TileMap.LAYER_BG | LAYER_FG | LAYER_OV
--- @param tx    number  Tile column (0-based)
--- @param ty    number  Tile row    (0-based)
--- @param id    number  Tile ID to write (0 = empty)
function TileMap:setTile(layer, tx, ty, id)
    if tx < 0 or tx >= self.width or ty < 0 or ty >= self.height then
        return
    end
    local arr = layerArray(self, layer)
    if not arr then return end

    local index = ty * self.width + tx + 1
    arr[index] = id

    -- Mark the containing chunk dirty for this layer
    local cx = math.floor(tx / CHUNK_SIZE)
    local cy = math.floor(ty / CHUNK_SIZE)
    local chunk = self.chunks[cy] and self.chunks[cy][cx]
    if chunk then
        if layer == TileMap.LAYER_BG then
            chunk.dirtyBg = true
        elseif layer == TileMap.LAYER_FG then
            chunk.dirtyFg = true
        elseif layer == TileMap.LAYER_OV then
            chunk.dirtyOv = true
        end
    end
end

--- Read the tile ID from the specified layer at tile coordinates (tx, ty).
--- Returns 0 for out-of-bounds coordinates.
---
--- @param layer number  TileMap.LAYER_BG | LAYER_FG | LAYER_OV
--- @param tx    number  Tile column (0-based)
--- @param ty    number  Tile row    (0-based)
--- @return number  Tile ID (0 = empty / out-of-bounds)
function TileMap:getTile(layer, tx, ty)
    if tx < 0 or tx >= self.width or ty < 0 or ty >= self.height then
        return 0
    end
    local arr = layerArray(self, layer)
    if not arr then return 0 end
    return arr[ty * self.width + tx + 1]
end

-- ---------------------------------------------------------------------------
-- Solid mask
-- ---------------------------------------------------------------------------

--- Set the solid collision flag at tile coordinates (tx, ty).
--- Silently ignores out-of-bounds coordinates.
---
--- @param tx    number   Tile column (0-based)
--- @param ty    number   Tile row    (0-based)
--- @param solid boolean  True to mark the tile as solid
function TileMap:setSolid(tx, ty, solid)
    if tx < 0 or tx >= self.width or ty < 0 or ty >= self.height then
        return
    end
    self.solid[ty * self.width + tx + 1] = solid
end

--- Return whether the tile at (tx, ty) is solid.
--- Returns false for out-of-bounds coordinates.
---
--- @param tx number  Tile column (0-based)
--- @param ty number  Tile row    (0-based)
--- @return boolean
function TileMap:isSolid(tx, ty)
    if tx < 0 or tx >= self.width or ty < 0 or ty >= self.height then
        return false
    end
    return self.solid[ty * self.width + tx + 1] == true
end

-- ---------------------------------------------------------------------------
-- Dungeon-wall mask
-- ---------------------------------------------------------------------------

--- Set the dungeonWall flag at tile coordinates (tx, ty).
--- Silently ignores out-of-bounds coordinates.
---
--- @param tx  number   Tile column (0-based)
--- @param ty  number   Tile row    (0-based)
--- @param val boolean  True to mark the tile as a dungeon wall
function TileMap:setDungeonWall(tx, ty, val)
    if tx < 0 or tx >= self.width or ty < 0 or ty >= self.height then
        return
    end
    self.dungeonWall[ty * self.width + tx + 1] = val
end

--- Return whether the tile at (tx, ty) is a dungeon wall.
--- Returns false for out-of-bounds coordinates.
---
--- @param tx number  Tile column (0-based)
--- @param ty number  Tile row    (0-based)
--- @return boolean
function TileMap:isDungeonWall(tx, ty)
    if tx < 0 or tx >= self.width or ty < 0 or ty >= self.height then
        return false
    end
    return self.dungeonWall[ty * self.width + tx + 1] == true
end

-- ---------------------------------------------------------------------------
-- Bulk fill
-- ---------------------------------------------------------------------------

--- Fill an entire layer with the given tile ID and mark ALL chunks dirty
--- for that layer.
---
--- @param layer number  TileMap.LAYER_BG | LAYER_FG | LAYER_OV
--- @param id    number  Tile ID to fill with (0 = empty)
function TileMap:fillLayer(layer, id)
    local arr = layerArray(self, layer)
    if not arr then return end

    local size = self.width * self.height
    for i = 1, size do
        arr[i] = id
    end

    -- Mark every chunk dirty for this layer
    for cy = 0, self.chunkH - 1 do
        for cx = 0, self.chunkW - 1 do
            local chunk = self.chunks[cy] and self.chunks[cy][cx]
            if chunk then
                if layer == TileMap.LAYER_BG then
                    chunk.dirtyBg = true
                elseif layer == TileMap.LAYER_FG then
                    chunk.dirtyFg = true
                elseif layer == TileMap.LAYER_OV then
                    chunk.dirtyOv = true
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Coordinate conversion helpers
-- ---------------------------------------------------------------------------

--- Convert tile coordinates to world coordinates.
---
--- Returns the top-left world corner of the tile at (tx, ty).
---
--- @param tx number  Tile X coordinate
--- @param ty number  Tile Y coordinate
--- @return number wx  World X (left edge of tile)
--- @return number wy  World Y (top edge of tile)
function TileMap:tileToWorld(tx, ty)
    return tx * self.tileSize, ty * self.tileSize
end

--- Convert world coordinates to tile coordinates.
---
--- Uses floor division so any point inside a tile maps to that tile's
--- grid position.
---
--- @param wx number  World X coordinate
--- @param wy number  World Y coordinate
--- @return number tx  Tile X coordinate
--- @return number ty  Tile Y coordinate
function TileMap:worldToTile(wx, wy)
    return math.floor(wx / self.tileSize), math.floor(wy / self.tileSize)
end

-- ---------------------------------------------------------------------------
-- Border rect helpers
-- ---------------------------------------------------------------------------

--- Set the world-space player boundary rectangle.
---
--- @param rect table|nil  `{x, y, w, h}` in world coordinates, or nil to
---                        disable border clamping.
function TileMap:setBorderRect(rect)
    self.borderRect = rect
end

--- Get the world-space player boundary rectangle.
---
--- @return table|nil  `{x, y, w, h}` in world coordinates, or nil if no
---                    border is set.
function TileMap:getBorderRect()
    return self.borderRect
end

-- ---------------------------------------------------------------------------
-- Snapshot / restore
-- ---------------------------------------------------------------------------

--- Capture a serializable snapshot of all tile data.
---
--- Returns a plain table containing shallow copies of every flat array.
--- Canvas data is intentionally excluded — canvases are rebuilt from tile
--- data when `applySnapshot` marks all chunks dirty.
---
--- @return table  Snapshot with fields: width, height, tileSize, bg, fg, ov,
---                solid, dungeonWall.
local function copyArray(src)
    local dst = {}
    for i = 1, #src do
        dst[i] = src[i]
    end
    return dst
end

function TileMap:snapshot()
    return {
        width       = self.width,
        height      = self.height,
        tileSize    = self.tileSize,
        bg          = copyArray(self.bg),
        fg          = copyArray(self.fg),
        ov          = copyArray(self.ov),
        solid       = copyArray(self.solid),
        dungeonWall = copyArray(self.dungeonWall),
    }
end

--- Restore tile data from a snapshot produced by `TileMap:snapshot`.
---
--- Copies all five flat arrays from `t` into `self`, then marks every chunk
--- dirty on all three layers so the canvas rebuild picks up the new data on
--- the next `TileMap:update` call.
---
--- @param t table  Snapshot table as returned by `TileMap:snapshot`.
function TileMap:applySnapshot(t)
    -- Restore flat tile-ID arrays
    for i = 1, self.width * self.height do
        self.bg[i]          = t.bg[i]
        self.fg[i]          = t.fg[i]
        self.ov[i]          = t.ov[i]
        self.solid[i]       = t.solid[i]
        self.dungeonWall[i] = t.dungeonWall[i]
    end

    -- Mark all chunks dirty for all three layers
    for cy = 0, self.chunkH - 1 do
        for cx = 0, self.chunkW - 1 do
            local chunk = self.chunks[cy] and self.chunks[cy][cx]
            if chunk then
                chunk.dirtyBg = true
                chunk.dirtyFg = true
                chunk.dirtyOv = true
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Chunk canvas rebuild
-- ---------------------------------------------------------------------------

--- Rebuild the canvas for a single layer of a chunk.
---
--- Sets the render target to `canvas`, clears it to transparent black, then
--- iterates all 32×32 tile positions within the chunk and draws each non-empty
--- tile using the shared tileset image and the pre-built Quad for that tile ID.
--- Tiles with ID 0 (or whose Quad is nil) are skipped (Requirement 2.8).
---
--- Drawing coordinates are chunk-local: the canvas origin is the chunk's
--- top-left corner, so each tile is drawn at `(localX * tileSize, localY * tileSize)`.
---
--- @param self    TileMap
--- @param chunk   table     Chunk object (`cx`, `cy`, canvas fields, dirty flags)
--- @param arr     table     Flat tile-ID array for the layer being rebuilt
--- @param canvas  userdata  Love2D Canvas to draw into
local function rebuildLayerCanvas(self, chunk, arr, canvas)
    --- Set the render target to this chunk's canvas.
    love.graphics.setCanvas(canvas)

    --- Clear the canvas to fully transparent black before redrawing.
    love.graphics.clear(0, 0, 0, 0)

    local cx       = chunk.cx
    local cy       = chunk.cy
    local tileSize = self.tileSize
    local width    = self.width
    local image    = self.tileset:getImage()

    --- Iterate all 32×32 tile positions within this chunk.
    for localY = 0, CHUNK_SIZE - 1 do
        for localX = 0, CHUNK_SIZE - 1 do
            --- Compute absolute tile coordinates from chunk-local offsets.
            local tx = cx * CHUNK_SIZE + localX
            local ty = cy * CHUNK_SIZE + localY

            --- Skip tiles that fall outside the map bounds (edge chunks may be partial).
            if tx < width and ty < self.height then
                local tileId = arr[ty * width + tx + 1]

                --- Skip empty tiles (ID 0); getQuad also returns nil for ID 0.
                if tileId ~= 0 then
                    local quad = self.tileset:getQuad(tileId)

                    --- Skip tiles whose quad is nil (unknown or empty ID).
                    if quad then
                        --- Draw at chunk-local pixel position; canvas origin = chunk top-left.
                        love.graphics.draw(image, quad, localX * tileSize, localY * tileSize)
                    end
                end
            end
        end
    end

    --- Restore the default render target (screen).
    love.graphics.setCanvas()
end

--- Process up to `CHUNK_REBUILD_PER_FRAME` dirty chunks per call.
---
--- Iterates chunks in row-major order (cy 0..chunkH-1, cx 0..chunkW-1).
--- For each chunk that has at least one dirty layer flag set, rebuilds every
--- dirty layer canvas (BG, FG, OV) and clears the corresponding dirty flag
--- (Requirements 2.5, 2.6).  Stops after `CHUNK_REBUILD_PER_FRAME` chunks
--- have been processed, deferring the remainder to subsequent frames to avoid
--- per-frame GPU spikes.
---
--- Called once per frame from `SceneManager:update` before `TileMap:draw`.
function TileMap:update()
    --- Counter of chunks rebuilt this call; capped at CHUNK_REBUILD_PER_FRAME.
    local rebuilt = 0

    for cy = 0, self.chunkH - 1 do
        for cx = 0, self.chunkW - 1 do
            --- Stop once the per-frame rebuild budget is exhausted.
            if rebuilt >= CHUNK_REBUILD_PER_FRAME then
                return
            end

            local chunk = self.chunks[cy] and self.chunks[cy][cx]
            if chunk then
                --- Check whether this chunk has any dirty layer.
                local anyDirty = chunk.dirtyBg or chunk.dirtyFg or chunk.dirtyOv

                if anyDirty then
                    --- Rebuild each dirty layer independently.

                    if chunk.dirtyBg then
                        --- Rebuild the background layer canvas.
                        rebuildLayerCanvas(self, chunk, self.bg, chunk.canvasBg)
                        --- Clear the background dirty flag.
                        chunk.dirtyBg = false
                    end

                    if chunk.dirtyFg then
                        --- Rebuild the foreground layer canvas.
                        rebuildLayerCanvas(self, chunk, self.fg, chunk.canvasFg)
                        --- Clear the foreground dirty flag.
                        chunk.dirtyFg = false
                    end

                    if chunk.dirtyOv then
                        --- Rebuild the overlay layer canvas.
                        rebuildLayerCanvas(self, chunk, self.ov, chunk.canvasOv)
                        --- Clear the overlay dirty flag.
                        chunk.dirtyOv = false
                    end

                    --- Count this chunk against the per-frame budget.
                    rebuilt = rebuilt + 1
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Camera-culled draw
-- ---------------------------------------------------------------------------

--- Draw all visible chunk canvases in layer order: BG → FG → OV.
---
--- Determines the range of chunks that intersect the camera rectangle, then
--- draws each visible chunk's canvas at its world-space position.  All BG
--- canvases are drawn first, then all FG canvases, then all OV canvases, so
--- that layering is correct across the entire visible area (Requirement 2.5).
---
--- Chunks that are still dirty (not yet rebuilt by `TileMap:update`) are
--- drawn as-is; their canvas may be stale until the rebuild budget catches up.
---
--- @param camX number  World X of the camera's left edge
--- @param camY number  World Y of the camera's top edge
--- @param camW number  Camera viewport width in world units
--- @param camH number  Camera viewport height in world units
local function drawLayerPass(self, minCX, maxCX, minCY, maxCY, layerKey)
    for cy = minCY, maxCY do
        for cx = minCX, maxCX do
            local chunk = self.chunks[cy] and self.chunks[cy][cx]
            if chunk then
                love.graphics.draw(chunk[layerKey], cx * CANVAS_SIZE, cy * CANVAS_SIZE)
            end
        end
    end
end

local function visibleChunkRange(self, camX, camY, camW, camH)
    return
        math.max(0, math.floor(camX / CANVAS_SIZE)),
        math.min(self.chunkW - 1, math.floor((camX + camW) / CANVAS_SIZE)),
        math.max(0, math.floor(camY / CANVAS_SIZE)),
        math.min(self.chunkH - 1, math.floor((camY + camH) / CANVAS_SIZE))
end

function TileMap:drawBackground(camX, camY, camW, camH)
    local a, b, c, d = visibleChunkRange(self, camX, camY, camW, camH)
    drawLayerPass(self, a, b, c, d, "canvasBg")
end

function TileMap:drawForeground(camX, camY, camW, camH)
    local a, b, c, d = visibleChunkRange(self, camX, camY, camW, camH)
    drawLayerPass(self, a, b, c, d, "canvasFg")
end

function TileMap:drawOverlay(camX, camY, camW, camH)
    local a, b, c, d = visibleChunkRange(self, camX, camY, camW, camH)
    drawLayerPass(self, a, b, c, d, "canvasOv")
end

function TileMap:draw(camX, camY, camW, camH)
    self:drawBackground(camX, camY, camW, camH)
    self:drawForeground(camX, camY, camW, camH)
    self:drawOverlay(camX, camY, camW, camH)
end

return TileMap
