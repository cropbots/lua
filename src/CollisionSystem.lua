-- lua/src/CollisionSystem.lua
-- Stateless module of pure collision-resolution functions.
-- No instance is required; all functions are called on the module table directly.
--
-- SpatialGrid internals:
--   A flat hash table keyed by (cx * 10007 + cy) where cx/cy are cell coordinates.
--   Each cell holds a list of rects that overlap it.
--   Built once per scene load; rebuilt when solid tiles change significantly.

local CollisionSystem = {}

--- Build a SpatialGrid from a list of world-space AABB rects.
---
--- Each rect is a table `{x, y, w, h}` in world units.  A rect is inserted into
--- every grid cell it overlaps.  Cell coordinates are derived by dividing world
--- coordinates by `cellSize` (floor division).  The cell key is
--- `cx * 10007 + cy`.
---
--- @param rects    table[]  List of `{x, y, w, h}` tables.
--- @param cellSize number   World units per cell side (default: 32).
--- @return table  SpatialGrid `{cells={}, cellSize=cellSize}`.
function CollisionSystem.buildGrid(rects, cellSize)
    cellSize = cellSize or 32

    local grid = { cells = {}, cellSize = cellSize }
    local cells = grid.cells
    local floor = math.floor

    for _, rect in ipairs(rects) do
        -- Compute the range of cells this rect overlaps on each axis.
        local minCX = floor(rect.x / cellSize)
        local maxCX = floor((rect.x + rect.w - 1) / cellSize)
        local minCY = floor(rect.y / cellSize)
        local maxCY = floor((rect.y + rect.h - 1) / cellSize)

        for cy = minCY, maxCY do
            for cx = minCX, maxCX do
                local key = cx * 10007 + cy
                local cell = cells[key]
                if cell == nil then
                    cell = {}
                    cells[key] = cell
                end
                cell[#cell + 1] = rect
            end
        end
    end

    return grid
end

--- Query a SpatialGrid for all rects that overlap the given world-space AABB.
---
--- Cells are visited from `floor(x/cellSize)` to `floor((x+w-1)/cellSize)` on
--- the X axis, and equivalently on the Y axis.  A rect that appears in multiple
--- cells is returned only once (deduplicated by Lua table identity).
---
--- @param grid table  SpatialGrid returned by `buildGrid`.
--- @param x    number  Left edge of the query AABB.
--- @param y    number  Top edge of the query AABB.
--- @param w    number  Width of the query AABB.
--- @param h    number  Height of the query AABB.
--- @return table[]  Deduplicated list of rects overlapping the AABB.
function CollisionSystem.queryGrid(grid, x, y, w, h)
    local cellSize = grid.cellSize
    local cells    = grid.cells
    local floor    = math.floor

    local minCX = floor(x / cellSize)
    local maxCX = floor((x + w - 1) / cellSize)
    local minCY = floor(y / cellSize)
    local maxCY = floor((y + h - 1) / cellSize)

    local result = {}
    local seen   = {}  -- keyed by rect table reference for O(1) dedup

    for cy = minCY, maxCY do
        for cx = minCX, maxCX do
            local key  = cx * 10007 + cy
            local cell = cells[key]
            if cell then
                for _, rect in ipairs(cell) do
                    if not seen[rect] then
                        seen[rect]         = true
                        result[#result + 1] = rect
                    end
                end
            end
        end
    end

    return result
end

--- Compute the number of collision sub-steps needed for the given speed.
---
--- Returns `math.max(1, math.min(8, math.ceil(speed / tileSize)))`.
--- The result is clamped to the range [1, 8] to prevent both wasted work at
--- low speeds and excessive iteration at very high speeds.
---
--- @param speed    number  Entity speed in world units per second.
--- @param tileSize number  Tile size in world units (typically 16).
--- @return integer  Sub-step count in [1, 8].
--- @param speed    number  Entity speed (world units / s).
--- @param tileSize number  Tile size in world units.
--- @param dt       number|nil  Optional delta time; when omitted uses speed-only estimate.
--- @return integer  Sub-step count in [1, 8].
function CollisionSystem.subSteps(speed, tileSize, dt)
    if dt and dt > 0 then
        return math.max(1, math.min(8, math.ceil(speed * dt / (tileSize * 0.4))))
    end
    return math.max(1, math.min(8, math.ceil(speed / tileSize)))
end

--- Test whether two world AABBs overlap.
--- @param ax number @param ay number @param aw number @param ah number
--- @param bx number @param by number @param bw number @param bh number
--- @return boolean
local function aabbOverlap(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

--- Resolve collisions on one axis for an entity AABB moving with scalar velocity.
--- Pure function: returns adjusted position and velocity on the given axis.
---
--- @param hitbox    table   `{x, y, w, h}` relative to entity origin.
--- @param pos       table   `{x, y}` world position of entity origin.
--- @param velAxis   number  Scalar velocity on the active axis.
--- @param colliders table[] List of `{x, y, w, h}` world rects.
--- @param axis      string  `"x"` or `"y"`.
--- @return table pos  Updated `{x, y}`.
--- @return number  Updated scalar velocity on `axis`.
function CollisionSystem.resolveAxis(hitbox, pos, velAxis, colliders, axis)
    if velAxis == 0 then
        return pos, velAxis
    end

    local epsilon = 0.001
    local hit = false
    local candidate = pos[axis]

    local wx = pos.x + hitbox.x
    local wy = pos.y + hitbox.y
    local ww = hitbox.w
    local wh = hitbox.h

    for _, c in ipairs(colliders) do
        if aabbOverlap(wx, wy, ww, wh, c.x, c.y, c.w, c.h) then
            hit = true
            if axis == "x" then
                if velAxis > 0 then
                    candidate = math.min(candidate, c.x - hitbox.x - hitbox.w - epsilon)
                else
                    candidate = math.max(candidate, c.x + c.w - hitbox.x + epsilon)
                end
            else
                if velAxis > 0 then
                    candidate = math.min(candidate, c.y - hitbox.y - hitbox.h - epsilon)
                else
                    candidate = math.max(candidate, c.y + c.h - hitbox.y + epsilon)
                end
            end
        end
    end

    if hit then
        local maxPush = (axis == "x") and hitbox.w or hitbox.h
        maxPush = math.max(maxPush, 1)
        local base = pos[axis]
        candidate = math.max(base - maxPush, math.min(base + maxPush, candidate))
        local newPos = { x = pos.x, y = pos.y }
        newPos[axis] = candidate
        return newPos, 0
    end

    return pos, velAxis
end

--- Clamp entity origin so its hitbox stays inside `bounds`.
--- When `bounds` is nil, returns `pos` unchanged.
---
--- @param hitbox table `{x, y, w, h}` relative to origin.
--- @param pos    table `{x, y}` world origin.
--- @param bounds table|nil `{x, y, w, h}` world boundary rect.
--- @return table `{x, y}`
function CollisionSystem.clampToRect(hitbox, pos, bounds)
    if not bounds then
        return pos
    end
    local minX = bounds.x - hitbox.x
    local maxX = bounds.x + bounds.w - hitbox.w - hitbox.x
    local minY = bounds.y - hitbox.y
    local maxY = bounds.y + bounds.h - hitbox.h - hitbox.y
    return {
        x = math.max(minX, math.min(maxX, pos.x)),
        y = math.max(minY, math.min(maxY, pos.y)),
    }
end

return CollisionSystem
