--- Pathfinder.lua
--- Tile-based A* pathfinding with Manhattan distance heuristic.
--- Uses a binary min-heap for the open set to keep per-frame cost low.
--- Max visited tiles: 3000 (prevents frame spikes on large open areas).
--- Replan interval (0.85 s) is stored per entity, not in this module.
---
--- Requirement: 4.9

local Pathfinder = {}

-- ---------------------------------------------------------------------------
-- Internal: binary min-heap (priority queue)
-- ---------------------------------------------------------------------------
-- Each element is {priority, tx, ty}.
-- The heap is a 1-based Lua array.

local Heap = {}
Heap.__index = Heap

--- Create a new empty min-heap.
--- @return table
local function newHeap()
    return setmetatable({_data = {}, _size = 0}, Heap)
end

--- Push an element onto the heap.
--- @param priority number  Lower value = higher priority.
--- @param tx       number  Tile X coordinate.
--- @param ty       number  Tile Y coordinate.
function Heap:push(priority, tx, ty)
    self._size = self._size + 1
    self._data[self._size] = {priority, tx, ty}
    -- Sift up
    local i = self._size
    local data = self._data
    while i > 1 do
        local parent = math.floor(i / 2)
        if data[parent][1] > data[i][1] then
            data[parent], data[i] = data[i], data[parent]
            i = parent
        else
            break
        end
    end
end

--- Pop the element with the lowest priority.
--- @return number priority, number tx, number ty
function Heap:pop()
    local data = self._data
    local top  = data[1]
    local n    = self._size
    -- Move last element to root and sift down
    data[1] = data[n]
    data[n] = nil
    self._size = n - 1
    n = self._size

    local i = 1
    while true do
        local left  = i * 2
        local right = i * 2 + 1
        local smallest = i
        if left  <= n and data[left][1]  < data[smallest][1] then smallest = left  end
        if right <= n and data[right][1] < data[smallest][1] then smallest = right end
        if smallest == i then break end
        data[i], data[smallest] = data[smallest], data[i]
        i = smallest
    end

    return top[1], top[2], top[3]
end

--- Return true when the heap is empty.
--- @return boolean
function Heap:isEmpty()
    return self._size == 0
end

-- ---------------------------------------------------------------------------
-- Internal constants
-- ---------------------------------------------------------------------------

--- Maximum number of tiles that may be visited before giving up.
local MAX_VISITED = 3000

--- 4-directional neighbour offsets (N, E, S, W).
local DIRS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Find a path from (startTx, startTy) to (goalTx, goalTy) on the given TileMap.
---
--- Uses A* with a Manhattan distance heuristic and a binary min-heap open set.
--- Only 4-directional movement (N, E, S, W) is considered.
--- A tile is walkable when `not map:isSolid(tx, ty)`.
---
--- Returns a list of {tx, ty} tile coordinates from start to goal (inclusive),
--- or nil if no path is found within the MAX_VISITED (3000) tile visit limit.
---
--- @param map     table  TileMap instance exposing `isSolid(tx, ty) -> bool`.
--- @param startTx number Start tile X.
--- @param startTy number Start tile Y.
--- @param goalTx  number Goal tile X.
--- @param goalTy  number Goal tile Y.
--- @return table|nil  List of {tx, ty} tables, or nil.
function Pathfinder.findPath(map, startTx, startTy, goalTx, goalTy)
    -- Trivial case: start == goal
    if startTx == goalTx and startTy == goalTy then
        return {{startTx, startTy}}
    end

    -- g-cost table: keyed by "tx,ty" string for simplicity
    local gCost  = {}
    -- came-from table: keyed by "tx,ty", value is {ptx, pty}
    local cameFrom = {}

    local function key(tx, ty)
        return tx * 100003 + ty   -- integer key avoids string allocation
    end

    local startKey = key(startTx, startTy)
    gCost[startKey] = 0

    local open = newHeap()
    local h0   = math.abs(startTx - goalTx) + math.abs(startTy - goalTy)
    open:push(h0, startTx, startTy)

    local visited = 0

    while not open:isEmpty() do
        local _, cx, cy = open:pop()
        local ck = key(cx, cy)

        -- Goal reached — reconstruct path
        if cx == goalTx and cy == goalTy then
            local path = {}
            local tx, ty = cx, cy
            while tx ~= startTx or ty ~= startTy do
                table.insert(path, 1, {tx, ty})
                local prev = cameFrom[key(tx, ty)]
                tx, ty = prev[1], prev[2]
            end
            table.insert(path, 1, {startTx, startTy})
            return path
        end

        visited = visited + 1
        if visited > MAX_VISITED then
            return nil
        end

        local currentG = gCost[ck]

        for _, dir in ipairs(DIRS) do
            local nx = cx + dir[1]
            local ny = cy + dir[2]

            -- Skip solid tiles
            if not map:isSolid(nx, ny) then
                local nk     = key(nx, ny)
                local newG   = currentG + 1
                local oldG   = gCost[nk]

                if oldG == nil or newG < oldG then
                    gCost[nk]    = newG
                    cameFrom[nk] = {cx, cy}
                    local h      = math.abs(nx - goalTx) + math.abs(ny - goalTy)
                    open:push(newG + h, nx, ny)
                end
            end
        end
    end

    -- No path found within the visit limit
    return nil
end

--- Given a path and the entity's current world position, return the index of
--- the next waypoint to follow.
---
--- Advances past any waypoints the entity is within `tileSize * 0.5` world
--- units of (Euclidean distance from the waypoint's tile centre).
--- Returns nil when the path is fully consumed.
---
--- @param path          table   List of {tx, ty} tile coordinates.
--- @param waypointIndex number  Current waypoint index (1-based).
--- @param worldX        number  Entity world X position.
--- @param worldY        number  Entity world Y position.
--- @param tileSize      number  World units per tile (e.g. 16).
--- @return number|nil  Next waypoint index, or nil if path is complete.
function Pathfinder.nextWaypoint(path, waypointIndex, worldX, worldY, tileSize)
    if not path or waypointIndex > #path then
        return nil
    end

    local threshold = tileSize * 0.5
    local idx       = waypointIndex

    -- Advance past waypoints the entity is already close enough to
    while idx <= #path do
        local wp    = path[idx]
        -- Tile centre in world space: top-left is (tx*tileSize, ty*tileSize),
        -- so centre is (tx*tileSize + tileSize/2, ty*tileSize + tileSize/2).
        local wpWx  = wp[1] * tileSize + tileSize * 0.5
        local wpWy  = wp[2] * tileSize + tileSize * 0.5
        local dx    = worldX - wpWx
        local dy    = worldY - wpWy
        local dist  = math.sqrt(dx * dx + dy * dy)

        if dist <= threshold then
            idx = idx + 1
        else
            break
        end
    end

    if idx > #path then
        return nil
    end

    return idx
end

return Pathfinder
