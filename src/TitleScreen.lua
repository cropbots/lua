--- Title screen shown before entering the game.

local TitleScreen = {}
TitleScreen.__index = TitleScreen

function TitleScreen.new()
    local ok, img = pcall(love.graphics.newImage, "assets/loading.png")
    if ok then
        img:setFilter("nearest", "nearest")
    end
    return setmetatable({
        logo = ok and img or nil,
        timer = 0,
        ready = false,
    }, TitleScreen)
end

function TitleScreen:update(dt)
    self.timer = self.timer + dt
    self.ready = true
end

function TitleScreen:draw()
    local w, h = love.graphics.getDimensions()
    love.graphics.clear(0.06, 0.08, 0.12, 1)
    love.graphics.setColor(0.95, 0.88, 0.55, 1)
    local title = "Cropbots"
    local font = love.graphics.getFont()
    local tw = font:getWidth(title)
    love.graphics.print(title, (w - tw) * 0.5, h * 0.32)

    love.graphics.setColor(0.75, 0.78, 0.82, 1)
    local sub = "Press Enter or Click to Start"
    local sw = font:getWidth(sub)
    love.graphics.print(sub, (w - sw) * 0.5, h * 0.48)

    if self.logo then
        local lw, lh = self.logo:getDimensions()
        local scale = math.min(280 / lw, 120 / lh)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(self.logo, (w - lw * scale) * 0.5, h * 0.58, 0, scale, scale)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function TitleScreen:shouldStart()
    return self.ready and (
        love.keyboard.isDown("return")
        or love.mouse.isDown(1)
    )
end

return TitleScreen
