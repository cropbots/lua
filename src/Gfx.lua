--- Graphics bootstrap: crisp pixels, SLAB/Khoron package paths.

local Gfx = {}
local _pathsReady = false

local function ensurePaths()
    if _pathsReady then return end

    local path = "kh.src/"
    local files = { "init", "lexer", "parser", "runtime", "stepper" }
    for _, f in ipairs(files) do
        package.preload[f] = function(modname)
            if love and love.filesystem then
                local fn, err = love.filesystem.load(path .. f .. ".lua")
                if not fn then return err end
                return fn(modname)
            else
                local fn, err = loadfile(path .. f .. ".lua")
                if not fn then return err end
                return fn(modname)
            end
        end
    end

    _pathsReady = true
end

ensurePaths()

function Gfx.init()
    ensurePaths()
    if love.graphics and love.graphics.setDefaultFilter then
        love.graphics.setDefaultFilter("nearest", "nearest")
    end
end

function Gfx.setNearest(image)
    if image and image.setFilter then
        image:setFilter("nearest", "nearest")
    end
end

return Gfx
