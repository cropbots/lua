--- HUD: compact HP hearts (screen space).

local HUD = {}
HUD.__index = HUD

local HEART_SIZE = 76
local HEART_GAP = -44
local HEART_PAD = 10

function HUD.new(player)
    local heart, heartEmpty, cogImg
    local ok1, h1 = pcall(love.graphics.newImage, "assets/ui/heart.png")
    local ok2, h2 = pcall(love.graphics.newImage, "assets/ui/heart-empty.png")
    local ok3, c3 = pcall(love.graphics.newImage, "assets/items/gear.png")
    if ok1 then
        h1:setFilter("nearest", "nearest"); heart = h1
    end
    if ok2 then
        h2:setFilter("nearest", "nearest"); heartEmpty = h2
    end
    if ok3 then
        c3:setFilter("nearest", "nearest"); cogImg = c3
    end
    return setmetatable({
        player = player,
        heart = heart,
        heartEmpty = heartEmpty,
        cogImg = cogImg,
    }, HUD)
end

function HUD:uiScale()
    return math.max(0.8, math.min(1.35, love.graphics.getHeight() / 540))
end

function HUD:draw()
    local size = HEART_SIZE
    local gap = HEART_GAP

    local hp, maxHp = self.player:getHp()
    local hearts = 10
    local hpPerHeart = math.max(1, maxHp / hearts)
    local full = math.ceil(hp / hpPerHeart)
    local cols = 5
    local rows = 2
    local blockW = cols * size + (cols - 1) * gap
    local blockH = rows * size + (rows - 1) * gap
    local x = love.graphics.getWidth() - blockW - HEART_PAD
    local y = HEART_PAD

    for i = 1, hearts do
        local img = (i <= full) and self.heart or self.heartEmpty
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        if img then
            love.graphics.draw(
                img, x + col * (size + gap), y + row * (size + gap),
                0, size / img:getWidth(), size / img:getHeight()
            )
        end
    end

    -- Draw Cogs currency in bottom-left
    local scale = self:uiScale()
    local cogs = self.player:getCogs()
    local bx = 20 * scale
    local by = love.graphics.getHeight() - 52 * scale
    local iconSize = 28 * scale
    local padding = 6 * scale

    local text = tostring(cogs)
    local font = love.graphics.getFont()
    local textW = font:getWidth(text)
    local textH = font:getHeight()
    local pillW = iconSize + textW + padding * 4
    local pillH = iconSize + padding * 2

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", bx, by - padding, pillW, pillH, 6 * scale, 6 * scale)
    love.graphics.setColor(0.9, 0.6, 0.2, 0.8)
    love.graphics.setLineWidth(1.5 * scale)
    love.graphics.rectangle("line", bx, by - padding, pillW, pillH, 6 * scale, 6 * scale)

    if self.cogImg then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            self.cogImg, bx + padding, by,
            0, iconSize / self.cogImg:getWidth(), iconSize / self.cogImg:getHeight()
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(text, bx + padding * 2.5 + iconSize, by + (iconSize - textH) * 0.5)
end

return HUD
