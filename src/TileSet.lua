--- TileSet.lua
--- Loads a tileset from a JSON descriptor and a PNG texture atlas.
--- Pre-builds one love.graphics.Quad per tile ID at load time for O(1) access.

local TileSet = {}
TileSet.__index = TileSet

-- ---------------------------------------------------------------------------
-- Minimal JSON decoder (no external dependencies)
-- Supports the subset used by tileset.json: objects, arrays, strings, numbers,
-- booleans, and null. Does not support Unicode escape sequences beyond \uXXXX
-- mapped to a literal '?' placeholder.
-- ---------------------------------------------------------------------------

local json = {}

--- Decode a JSON string into a Lua value.
--- @param s string  Raw JSON text
--- @return any      Decoded Lua value
--- @return string?  Error message on failure
function json.decode(s)
    local pos = 1

    local function skipWS()
        while pos <= #s and s:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function peek()
        skipWS()
        return s:sub(pos, pos)
    end

    local function consume(ch)
        skipWS()
        if s:sub(pos, pos) ~= ch then
            error(("json: expected '%s' at pos %d, got '%s'"):format(ch, pos, s:sub(pos, pos)))
        end
        pos = pos + 1
    end

    local parseValue  -- forward declaration

    local function parseString()
        consume('"')
        local result = {}
        while pos <= #s do
            local ch = s:sub(pos, pos)
            if ch == '"' then
                pos = pos + 1
                return table.concat(result)
            elseif ch == '\\' then
                pos = pos + 1
                local esc = s:sub(pos, pos)
                pos = pos + 1
                if     esc == '"'  then result[#result+1] = '"'
                elseif esc == '\\' then result[#result+1] = '\\'
                elseif esc == '/'  then result[#result+1] = '/'
                elseif esc == 'b'  then result[#result+1] = '\b'
                elseif esc == 'f'  then result[#result+1] = '\f'
                elseif esc == 'n'  then result[#result+1] = '\n'
                elseif esc == 'r'  then result[#result+1] = '\r'
                elseif esc == 't'  then result[#result+1] = '\t'
                elseif esc == 'u'  then
                    -- consume 4 hex digits, map to '?' (ASCII-safe placeholder)
                    pos = pos + 4
                    result[#result+1] = '?'
                else
                    result[#result+1] = esc
                end
            else
                result[#result+1] = ch
                pos = pos + 1
            end
        end
        error("json: unterminated string")
    end

    local function parseNumber()
        skipWS()
        local start = pos
        -- optional leading minus
        if s:sub(pos, pos) == '-' then pos = pos + 1 end
        -- integer part
        while pos <= #s and s:sub(pos, pos):match("%d") do pos = pos + 1 end
        -- optional fractional part
        if pos <= #s and s:sub(pos, pos) == '.' then
            pos = pos + 1
            while pos <= #s and s:sub(pos, pos):match("%d") do pos = pos + 1 end
        end
        -- optional exponent
        if pos <= #s and s:sub(pos, pos):match("[eE]") then
            pos = pos + 1
            if pos <= #s and s:sub(pos, pos):match("[+-]") then pos = pos + 1 end
            while pos <= #s and s:sub(pos, pos):match("%d") do pos = pos + 1 end
        end
        local numStr = s:sub(start, pos - 1)
        local n = tonumber(numStr)
        if not n then error("json: invalid number: " .. numStr) end
        return n
    end

    local function parseArray()
        consume('[')
        local arr = {}
        skipWS()
        if peek() == ']' then
            pos = pos + 1
            return arr
        end
        while true do
            arr[#arr+1] = parseValue()
            skipWS()
            local ch = s:sub(pos, pos)
            if ch == ']' then
                pos = pos + 1
                return arr
            elseif ch == ',' then
                pos = pos + 1
            else
                error(("json: expected ',' or ']' at pos %d"):format(pos))
            end
        end
    end

    local function parseObject()
        consume('{')
        local obj = {}
        skipWS()
        if peek() == '}' then
            pos = pos + 1
            return obj
        end
        while true do
            skipWS()
            local key = parseString()
            consume(':')
            obj[key] = parseValue()
            skipWS()
            local ch = s:sub(pos, pos)
            if ch == '}' then
                pos = pos + 1
                return obj
            elseif ch == ',' then
                pos = pos + 1
            else
                error(("json: expected ',' or '}' at pos %d"):format(pos))
            end
        end
    end

    parseValue = function()
        local ch = peek()
        if ch == '"' then
            return parseString()
        elseif ch == '{' then
            return parseObject()
        elseif ch == '[' then
            return parseArray()
        elseif ch == 't' then
            if s:sub(pos, pos+3) == 'true' then pos = pos + 4; return true end
            error("json: invalid token at pos " .. pos)
        elseif ch == 'f' then
            if s:sub(pos, pos+4) == 'false' then pos = pos + 5; return false end
            error("json: invalid token at pos " .. pos)
        elseif ch == 'n' then
            if s:sub(pos, pos+3) == 'null' then pos = pos + 4; return nil end
            error("json: invalid token at pos " .. pos)
        elseif ch == '-' or ch:match("%d") then
            return parseNumber()
        else
            error(("json: unexpected character '%s' at pos %d"):format(ch, pos))
        end
    end

    local ok, result = pcall(parseValue)
    if not ok then
        return nil, result
    end
    return result
end

-- ---------------------------------------------------------------------------
-- TileSet
-- ---------------------------------------------------------------------------

--- Load a TileSet from a JSON descriptor and a PNG texture atlas.
---
--- Parses `jsonPath` using `love.filesystem.read`, decodes the JSON, loads
--- `imagePath` with `love.graphics.newImage`, then pre-builds one
--- `love.graphics.newQuad` per tile entry for O(1) access by tile ID.
---
--- @param jsonPath  string  Path to the tileset JSON file (relative to game root)
--- @param imagePath string  Path to the tileset PNG file (relative to game root)
--- @return TileSet|nil      The loaded TileSet instance, or nil on failure
--- @return string?          Error message when the first return value is nil
function TileSet.load(jsonPath, imagePath)
    -- Read JSON file
    local jsonText, readErr = love.filesystem.read(jsonPath)
    if not jsonText then
        return nil, ("TileSet: failed to read '%s': %s"):format(jsonPath, tostring(readErr))
    end

    -- Decode JSON
    local data, decodeErr = json.decode(jsonText)
    if not data then
        return nil, ("TileSet: failed to parse '%s': %s"):format(jsonPath, tostring(decodeErr))
    end

    -- Validate required fields
    if type(data.tiles) ~= "table" then
        return nil, ("TileSet: '%s' is missing 'tiles' array"):format(jsonPath)
    end

    -- Load image
    local ok, image = pcall(love.graphics.newImage, imagePath)
    if not ok then
        return nil, ("TileSet: failed to load image '%s': %s"):format(imagePath, tostring(image))
    end
    image:setFilter("nearest", "nearest")

    local imageW = image:getWidth()
    local imageH = image:getHeight()

    -- Pre-build quads and store source rects, both indexed by tile ID
    local quads = {}   -- [id] -> love.graphics.Quad
    local rects = {}   -- [id] -> {x, y, w, h}

    for _, tile in ipairs(data.tiles) do
        local id = tile.id
        local x  = tile.x
        local y  = tile.y
        local w  = tile.width  or data.tile_width
        local h  = tile.height or data.tile_height

        if type(id) == "number" and type(x) == "number" and type(y) == "number"
                and type(w) == "number" and type(h) == "number" then
            quads[id] = love.graphics.newQuad(x, y, w, h, imageW, imageH)
            rects[id] = { x = x, y = y, w = w, h = h }
        end
    end

    local self = setmetatable({}, TileSet)
    self._image  = image
    self._quads  = quads
    self._rects  = rects
    self._imageW = imageW
    self._imageH = imageH

    return self
end

--- Return the pre-built `love.graphics.Quad` for the given tile ID.
--- Returns `nil` for tile ID 0, `nil`, or any ID not present in the tileset.
---
--- @param tileId number|nil  Tile ID to look up
--- @return Quad|nil
function TileSet:getQuad(tileId)
    if not tileId or tileId == 0 then return nil end
    return self._quads[tileId]
end

--- Return the raw source rectangle `{x, y, w, h}` for the given tile ID.
--- Returns `nil` for tile ID 0, `nil`, or any ID not present in the tileset.
---
--- @param tileId number|nil  Tile ID to look up
--- @return {x:number, y:number, w:number, h:number}|nil
function TileSet:getRect(tileId)
    if not tileId or tileId == 0 then return nil end
    return self._rects[tileId]
end

--- Return the shared `love.graphics.Image` object for this tileset.
---
--- @return Image
function TileSet:getImage()
    return self._image
end

return TileSet
