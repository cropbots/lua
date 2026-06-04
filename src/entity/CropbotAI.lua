--- Cropbot farm automation: wander farm tiles, harvest, replant from bot inventory.

local Pathfinder = require("src.Pathfinder")
local Crops = require("src.farm.Crops")

local CropbotAI = {}
local SEARCH_RADIUS = 8
local WORK_DELAY = 0.8

local function key(tx, ty)
    return tx .. ":" .. ty
end

local function botInventory(ctx, inst)
    if ctx.cropbotInv then
        return ctx.cropbotInv(inst.uid)
    end
    return nil
end

local function isFarmTile(farmSystem, map, tx, ty)
    if farmSystem:isSoil(map, tx, ty) then return true end
    if farmSystem:get(tx, ty) then return true end
    return false
end

local function findFarmTarget(farmSystem, map, cx, cy, wantEmpty)
    local best, bestD2 = nil, nil
    for ty = cy - SEARCH_RADIUS, cy + SEARCH_RADIUS do
        for tx = cx - SEARCH_RADIUS, cx + SEARCH_RADIUS do
            if isFarmTile(farmSystem, map, tx, ty) then
                local plant = farmSystem:get(tx, ty)
                local empty = (not plant) and farmSystem:isSoil(map, tx, ty)
                local harvestable = false
                if plant then
                    local def = Crops.defs[plant.cropId]
                    harvestable = def and plant.stage >= #def.stages
                end
                if wantEmpty and empty then
                    local d2 = (tx - cx) * (tx - cx) + (ty - cy) * (ty - cy)
                    if not bestD2 or d2 < bestD2 then
                        best, bestD2 = { tx = tx, ty = ty, kind = "empty" }, d2
                    end
                elseif (not wantEmpty) and harvestable then
                    local d2 = (tx - cx) * (tx - cx) + (ty - cy) * (ty - cy)
                    if not bestD2 or d2 < bestD2 then
                        best, bestD2 = { tx = tx, ty = ty, kind = "harvest" }, d2
                    end
                elseif (not wantEmpty) and not plant and farmSystem:isSoil(map, tx, ty) then
                    local d2 = (tx - cx) * (tx - cx) + (ty - cy) * (ty - cy)
                    if not bestD2 or d2 < bestD2 then
                        best, bestD2 = { tx = tx, ty = ty, kind = "wander" }, d2
                    end
                end
            end
        end
    end
    return best
end

local function moveTowardTile(inst, map, tx, ty, speed)
    local wx, wy = map:tileToWorld(tx, ty)
    wx = wx + map.tileSize * 0.5
    wy = wy + map.tileSize * 0.5
    local dx, dy = wx - inst.pos.x, wy - inst.pos.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= map.tileSize * 0.45 then
        inst.vel.x, inst.vel.y = 0, 0
        return true
    end
    inst.vel.x = dx / len * speed
    inst.vel.y = dy / len * speed
    return false
end

local function pickSeed(inv)
    for seed in pairs(Crops.seedToCrop) do
        if inv:get(seed) > 0 then
            return seed
        end
    end
    if inv:get("potato") > 0 then
        return "potato"
    end
    return nil
end

local function followPath(inst, map, tx, ty, speed, state, dt)
    state.pathFollow = state.pathFollow or {
        replanTimer = 0,
        path = nil,
        idx = 1,
        goalTx = nil,
        goalTy = nil,
    }

    local pf = state.pathFollow
    pf.replanTimer = (pf.replanTimer or 0) - dt
    if pf.goalTx ~= tx or pf.goalTy ~= ty or pf.replanTimer <= 0 then
        local stx, sty = map:worldToTile(inst.pos.x, inst.pos.y)
        pf.path = Pathfinder.findPath(map, stx, sty, tx, ty)
        pf.idx = pf.path and 2 or 1
        pf.goalTx = tx
        pf.goalTy = ty
        pf.replanTimer = 0.65
    end

    if pf.path and pf.idx then
        local nextIdx = Pathfinder.nextWaypoint(pf.path, pf.idx, inst.pos.x, inst.pos.y, map.tileSize)
        if nextIdx then
            pf.idx = nextIdx
            local wp = pf.path[nextIdx]
            local wx, wy = map:tileToWorld(wp[1], wp[2])
            wx = wx + map.tileSize * 0.5
            wy = wy + map.tileSize * 0.5
            local dx, dy = wx - inst.pos.x, wy - inst.pos.y
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.001 then
                inst.vel.x = dx / len * speed
                inst.vel.y = dy / len * speed
            else
                inst.vel.x, inst.vel.y = 0, 0
            end
            return true, false
        end
    end

    local goalX, goalY = map:tileToWorld(tx, ty)
    goalX = goalX + map.tileSize * 0.5
    goalY = goalY + map.tileSize * 0.5
    local dx, dy = goalX - inst.pos.x, goalY - inst.pos.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= map.tileSize * 0.45 then
        inst.vel.x, inst.vel.y = 0, 0
        return false, true
    end

    return false, false
end

function CropbotAI.runFarm(inst, dt, ctx)
    CropbotAI.runAction("smart_seek_farm_tile", inst, dt, ctx)
    if inst.vel.x == 0 and inst.vel.y == 0 then
        CropbotAI.runAction("bonemeal_current_tile", inst, dt, ctx)
        CropbotAI.runAction("seed_current_tile", inst, dt, ctx)
    end
end

function CropbotAI.runAction(name, inst, dt, ctx)
    local farmSystem = ctx.farmSystem
    local map = ctx.map
    if not farmSystem or not map then
        inst.vel.x, inst.vel.y = 0, 0
        return
    end

    inst.cropbot = inst.cropbot or {}
    local state = inst.cropbot
    local speed = (ctx.actionParams and ctx.actionParams.seek_speed) or inst.def.speed or 130
    local inv = botInventory(ctx, inst)

    if state.workTimer and state.workTimer > 0 then
        state.workTimer = state.workTimer - dt
        inst.vel.x, inst.vel.y = 0, 0
        if state.workTimer <= 0 and state.pendingSeed and inv then
            if inv:remove(state.pendingSeed, 1) then
                farmSystem:plant(map, state.workTx, state.workTy, state.pendingSeed)
            end
            state.pendingSeed = nil
        end
        return
    end

    local cx, cy = map:worldToTile(inst.pos.x, inst.pos.y)

    if name == "bonemeal_current_tile" or name == "seed_current_tile" then
        local plant = farmSystem:get(cx, cy)
        if plant then
            local def = Crops.defs[plant.cropId]
            if def and plant.stage >= #def.stages and inv then
                if farmSystem:harvest(map, cx, cy, inv) then
                    local seed = pickSeed(inv)
                    if seed then
                        state.workTimer = WORK_DELAY
                        state.workTx, state.workTy = cx, cy
                        state.pendingSeed = seed
                    end
                end
            end
        elseif name == "seed_current_tile" and farmSystem:isSoil(map, cx, cy) and inv then
            local seed = pickSeed(inv)
            if seed and inv:get(seed) > 0 then
                if inv:remove(seed, 1) then
                    if not farmSystem:plant(map, cx, cy, seed) then
                        inv:add(seed, 1)
                    end
                end
            end
        end
        inst.vel.x, inst.vel.y = 0, 0
        return
    end

    local wantEmpty = (name == "seek_nearest_empty_farm_tile")
    local target = findFarmTarget(farmSystem, map, cx, cy, wantEmpty)
    if not target then
        inst.vel.x = math.cos(state.wanderAngle or 0) * speed * 0.25
        inst.vel.y = math.sin(state.wanderAngle or 0) * speed * 0.25
        state.wanderAngle = (state.wanderAngle or 0) + dt
        return
    end

    local moving, reached = followPath(inst, map, target.tx, target.ty, speed, state, dt)
    if not moving and not reached then
        moving = moveTowardTile(inst, map, target.tx, target.ty, speed)
        reached = moving
    end

    if reached then
        if target.kind == "harvest" and inv then
            if farmSystem:harvest(map, target.tx, target.ty, inv) then
                local seed = pickSeed(inv)
                if seed then
                    state.workTimer = WORK_DELAY
                    state.workTx, state.workTy = target.tx, target.ty
                    state.pendingSeed = seed
                end
            end
        elseif target.kind == "empty" and inv then
            local seed = pickSeed(inv)
            if seed and inv:remove(seed, 1) then
                if not farmSystem:plant(map, target.tx, target.ty, seed) then
                    inv:add(seed, 1)
                end
            end
        end
    end
end

return CropbotAI
