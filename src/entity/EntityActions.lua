--- Movement and combat actions ported from cropbot/rust semantics.

local Pathfinder = require("src.Pathfinder")
local CropbotAI = require("src.entity.CropbotAI")

local EntityActions = {}

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function normalize(dx, dy)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return 0, 0 end
    return dx / len, dy / len
end

local function seekToward(inst, tx, ty, speed)
    local dx, dy = normalize(tx - inst.pos.x, ty - inst.pos.y)
    inst.vel.x = dx * speed
    inst.vel.y = dy * speed
end

local function ensureRuntime(inst)
    inst.runtime = inst.runtime or {}
    return inst.runtime
end

local function followPath(inst, map, tx, ty, speed, rt)
    rt.pathFollow = rt.pathFollow or { replanTimer = 0, path = nil, idx = 1 }
    local pf = rt.pathFollow
    pf.replanTimer = pf.replanTimer - (rt.dt or 0)
    if pf.replanTimer <= 0 then
        local stx, sty = map:worldToTile(inst.pos.x, inst.pos.y)
        pf.path = Pathfinder.findPath(map, stx, sty, tx, ty)
        pf.idx = pf.path and 2 or 1
        pf.replanTimer = 0.85
    end
    if pf.path and pf.idx then
        local nextIdx = Pathfinder.nextWaypoint(pf.path, pf.idx, inst.pos.x, inst.pos.y, map.tileSize)
        if nextIdx then
            pf.idx = nextIdx
            local wp = pf.path[nextIdx]
            local wx, wy = map:tileToWorld(wp[1], wp[2])
            wx = wx + map.tileSize * 0.5
            wy = wy + map.tileSize * 0.5
            seekToward(inst, wx, wy, speed)
            return true
        end
    end
    return false
end

function EntityActions.run(name, inst, dt, ctx)
    local params = ctx.actionParams or {}
    local speed = params.speed or params.seek_speed or inst.def.speed or 100
    local rt = ensureRuntime(inst)
    rt.dt = dt

    if name == "idle" then
        inst.vel.x, inst.vel.y = 0, 0
        return
    end

    if name == "wander" then
        rt.wanderTimer = (rt.wanderTimer or 0) - dt
        if rt.wanderTimer <= 0 then
            rt.wanderAngle = love.math.random() * math.pi * 2
            rt.wanderTimer = 0.6 + love.math.random() * 1.2
        end
        local sp = params.speed or speed * 0.35
        inst.vel.x = math.cos(rt.wanderAngle or 0) * sp
        inst.vel.y = math.sin(rt.wanderAngle or 0) * sp
        return
    end

    if name == "seek_player" or name == "chase_target" then
        if ctx.playerInfo then
            local px = ctx.playerInfo.x + (ctx.playerInfo.w or 8) * 0.5
            local py = ctx.playerInfo.y + (ctx.playerInfo.h or 8) * 0.5
            if ctx.usePathfinding and ctx.map then
                local tx, ty = ctx.map:worldToTile(px, py)
                if not followPath(inst, ctx.map, tx, ty, speed, rt) then
                    seekToward(inst, px, py, speed)
                end
            else
                seekToward(inst, px, py, speed)
            end
        end
        return
    end

    if name == "seek" then
        local target = inst.currentTarget
        if target and target.alive then
            if ctx.usePathfinding and ctx.map then
                local tx, ty = ctx.map:worldToTile(target.pos.x, target.pos.y)
                if not followPath(inst, ctx.map, tx, ty, speed, rt) then
                    seekToward(inst, target.pos.x, target.pos.y, speed)
                end
            else
                seekToward(inst, target.pos.x, target.pos.y, speed)
            end
        end
        return
    end

    if name == "watch" then
        local seekRange = params.seek_range or 280
        local fleeRange = params.flee_range or 48
        local seekForce = params.seek_force or 90
        local fleeForce = params.flee_force or 220
        if ctx.playerInfo then
            local px = ctx.playerInfo.x + (ctx.playerInfo.w or 8) * 0.5
            local py = ctx.playerInfo.y + (ctx.playerInfo.h or 8) * 0.5
            local d = dist(inst.pos.x, inst.pos.y, px, py)
            if d > seekRange then
                seekToward(inst, px, py, seekForce)
            elseif d < fleeRange then
                local dx, dy = normalize(inst.pos.x - px, inst.pos.y - py)
                inst.vel.x = dx * fleeForce
                inst.vel.y = dy * fleeForce
            else
                inst.vel.x, inst.vel.y = 0, 0
            end
        end
        return
    end

    if name == "dash_at_target" or name == "curve_dash_at_target" then
        rt.dashCd = (rt.dashCd or 0) - dt
        if rt.dashTimer and rt.dashTimer > 0 then
            rt.dashTimer = rt.dashTimer - dt
            local target = inst.currentTarget
            if target then
                local arc = (name == "curve_dash_at_target") and (params.arc_strength or 0.1) or 0
                local dx, dy = normalize(target.pos.x - inst.pos.x, target.pos.y - inst.pos.y)
                if arc ~= 0 then
                    dx, dy = dx + dy * arc, dy - dx * arc
                    dx, dy = normalize(dx, dy)
                end
                inst.vel.x = dx * (rt.dashSpeed or speed)
                inst.vel.y = dy * (rt.dashSpeed or speed)
            end
            return
        end
        if rt.dashCd <= 0 and inst.currentTarget and inst.stats:get("target_in_range", 0) > 0 then
            rt.dashTimer = params.dash_duration or 0.2
            rt.dashCd = params.dash_cooldown or 1.5
            rt.dashSpeed = params.dash_speed or inst.def.speed or 300
        end
        inst.vel.x, inst.vel.y = 0, 0
        return
    end

    if name == "cropbot_farm" then
        CropbotAI.runFarm(inst, dt, ctx)
        return
    end

    if name == "smart_seek_farm_tile"
        or name == "seek_nearest_empty_farm_tile"
        or name == "bonemeal_current_tile"
        or name == "seed_current_tile" then
        CropbotAI.runAction(name, inst, dt, ctx)
        return
    end
end

return EntityActions
