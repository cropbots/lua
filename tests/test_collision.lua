package.path = package.path .. ";./src/?.lua;./src/?/init.lua;./?.lua"

local CollisionSystem = require("src.CollisionSystem")

describe("CollisionSystem", function()
    it("resolveAxis removes overlap on X", function()
        local hitbox = { x = 0, y = 0, w = 16, h = 16 }
        local pos = { x = 40, y = 40 }
        local colliders = { { x = 48, y = 40, w = 16, h = 16 } }
        local newPos, newVel = CollisionSystem.resolveAxis(hitbox, pos, 10, colliders, "x")
        local wx = newPos.x + hitbox.x
        assert.is_true(wx + hitbox.w <= colliders[1].x + 0.01 or newVel == 0)
    end)

    it("resolveAxis is idempotent", function()
        local hitbox = { x = 0, y = 0, w = 16, h = 16 }
        local pos = { x = 40, y = 40 }
        local colliders = { { x = 48, y = 40, w = 16, h = 16 } }
        local p1, v1 = CollisionSystem.resolveAxis(hitbox, pos, 10, colliders, "x")
        local p2, v2 = CollisionSystem.resolveAxis(hitbox, p1, v1, colliders, "x")
        assert.are.equal(p1.x, p2.x)
        assert.are.equal(v1, v2)
    end)
end)
