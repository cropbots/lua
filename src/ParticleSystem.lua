local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

function ParticleSystem.new()
    return setmetatable({
        particles = {},
        trailTimer = 0,
    }, ParticleSystem)
end

local function add(particles, p)
    particles[#particles + 1] = p
end

function ParticleSystem:emitDashAfterimage(x, y, tex, scale)
    add(self.particles, {
        kind = "afterimage",
        x = x,
        y = y,
        tex = tex,
        scale = scale or 1,
        life = 0.25,
        ttl = 0.25,
        color = { 1, 1, 1, 0.6 },
    })
end

function ParticleSystem:emitDustTrail(x, y, vx, vy)
    for _ = 1, 2 do
        local angle = love.math.random() * math.pi * 2
        local speed = 10 + love.math.random() * 10
        add(self.particles, {
            kind = "dust",
            x = x,
            y = y,
            vx = math.cos(angle) * speed + vx * 0.4,
            vy = math.sin(angle) * speed + vy * 0.4,
            life = 0.4 + love.math.random() * 0.1,
            ttl = 0.4,
            size0 = 2.5,
            size1 = 0,
            color0 = { 1.0, 0.86, 0.70, 0.78 },
        })
    end
end

function ParticleSystem:update(dt)
    local nextList = {}
    for _, p in ipairs(self.particles) do
        p.life = p.life - dt
        if p.life > 0 then
            if p.kind == "dust" then
                p.vy = p.vy + 40 * dt
                p.vx = p.vx * (1 - (1 - 0.9) * dt * 60)
                p.vy = p.vy * (1 - (1 - 0.9) * dt * 60)
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
            end
            nextList[#nextList + 1] = p
        end
    end
    self.particles = nextList
end

function ParticleSystem:draw()
    for _, p in ipairs(self.particles) do
        local t = 1 - (p.life / p.ttl)
        if p.kind == "afterimage" and p.tex then
            love.graphics.setColor(1, 1, 1, (1 - t) * 0.6)
            local tw, th = p.tex:getWidth(), p.tex:getHeight()
            local dw, dh = tw * p.scale, th * p.scale
            love.graphics.draw(p.tex, p.x - dw * 0.5, p.y - dh * 0.5, 0, p.scale, p.scale)
        elseif p.kind == "dust" then
            local sz = p.size0 + (p.size1 - p.size0) * t
            love.graphics.setColor(1.0, 0.86, 0.70, (1 - t) * 0.78)
            love.graphics.rectangle("fill", p.x - sz * 0.5, p.y - sz * 0.5, sz, sz)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return ParticleSystem
