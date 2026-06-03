--- Simple bottom-left toast notifications (no persistence).

local Toasts = {}
Toasts.__index = Toasts

function Toasts.new()
    return setmetatable({
        items = {},
    }, Toasts)
end

--- @param text string
--- @param opts table|nil { ttl=number, kind=string }
function Toasts:push(text, opts)
    opts = opts or {}
    self.items[#self.items + 1] = {
        text = tostring(text or ""),
        t = 0,
        ttl = opts.ttl or 3.5,
        kind = opts.kind or "info",
    }
end

function Toasts:update(dt)
    local keep = {}
    for _, it in ipairs(self.items) do
        it.t = it.t + dt
        if it.t < it.ttl then
            keep[#keep + 1] = it
        end
    end
    self.items = keep
end

function Toasts:draw()
    local x = 18
    local y = love.graphics.getHeight() - 18
    local pad = 10

    love.graphics.push("all")
    love.graphics.setFont(love.graphics.getFont())

    for i = #self.items, 1, -1 do
        local it = self.items[i]
        local alpha = 1.0
        if it.ttl - it.t < 0.35 then
            alpha = math.max(0, (it.ttl - it.t) / 0.35)
        elseif it.t < 0.15 then
            alpha = math.min(1.0, it.t / 0.15)
        end

        local tw = love.graphics.getFont():getWidth(it.text)
        local th = love.graphics.getFont():getHeight()
        local bw = math.min(420, tw + pad * 2)
        local bh = th + pad * 2
        local bx = x
        local by = y - bh

        local r, g, b = 0.12, 0.12, 0.14
        if it.kind == "discover" then r, g, b = 0.12, 0.18, 0.24 end
        if it.kind == "error" then r, g, b = 0.22, 0.10, 0.10 end

        love.graphics.setColor(r, g, b, 0.92 * alpha)
        love.graphics.rectangle("fill", bx, by, bw, bh, 8, 8)
        love.graphics.setColor(1, 1, 1, 0.92 * alpha)
        love.graphics.rectangle("line", bx, by, bw, bh, 8, 8)
        love.graphics.print(it.text, bx + pad, by + pad)

        y = y - (bh + 10)
    end

    love.graphics.pop()
end

return Toasts

