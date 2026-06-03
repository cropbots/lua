describe("Player HP clamping", function()
    local function clampHp(hp, maxHp, delta)
        return math.max(0, math.min(maxHp, hp + delta))
    end

    it("clamps damage", function()
        assert.are.equal(0, clampHp(5, 50, -100))
        assert.are.equal(40, clampHp(50, 50, -10))
    end)

    it("clamps heal", function()
        assert.are.equal(50, clampHp(45, 50, 100))
    end)
end)

describe("Player speed cap", function()
    it("caps after acceleration", function()
        local MAX_SPEED = 640
        local vel = { x = 600, y = 200 }
        local dt = 0.016
        vel.x = vel.x + 1 * 1800 * dt
        vel.y = vel.y + 0 * 1800 * dt
        local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
        if speed > MAX_SPEED then
            vel.x = vel.x / speed * MAX_SPEED
            vel.y = vel.y / speed * MAX_SPEED
        end
        speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
        assert.is_true(speed <= MAX_SPEED + 1e-4)
    end)
end)
