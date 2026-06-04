--- SceneManager: farm / expedition scenes, warps, interaction, spawners.

local TileSet = require("src.TileSet")
local TileMap = require("src.TileMap")
local CollisionSystem = require("src.CollisionSystem")
local Player = require("src.Player")
local EntitySystem = require("src.EntitySystem")
local StructureSystem = require("src.StructureSystem")
local FarmBlockSystem = require("src.FarmBlockSystem")
local BuildMenu = require("src.BuildMenu")
local FarmScene = require("src.FarmScene")
local DungeonGenerator = require("src.DungeonGenerator")
local SoilInteraction = require("src.SoilInteraction")
local FarmSystem = require("src.farm.FarmSystem")
local Crafting = require("src.farm.Crafting")
local Placement = require("src.farm.Placement")
local Inventory = require("src.Inventory")
local Camera = require("src.Camera")
local HUD = require("src.HUD")
local LootUI = require("src.LootUI")
local SpawnerSystem = require("src.spawner.SpawnerSystem")
local Gfx = require("src.Gfx")
local Notebook = require("src.ui.Notebook")
local ParticleSystem = require("src.ParticleSystem")
local ItemIcons = require("src.ui.ItemIcons")
local Tools = require("src.items.Tools")
local DialogueSystem = require("src.dialogue.DialogueSystem")
local ExpeditionTracker = require("src.ExpeditionTracker")
local Toasts = require("src.ui.Toasts")
local RobotPuzzleBank = require("src.puzzle.RobotPuzzleBank")

local SceneManager = {}
SceneManager.__index = SceneManager

local GROUND_TILE = 24

local function buildCollisionGrid(map)
    local rects = {}
    local ts = map.tileSize
    for ty = 0, map.height - 1 do
        for tx = 0, map.width - 1 do
            if map:isSolid(tx, ty) then
                rects[#rects + 1] = { x = tx * ts, y = ty * ts, w = ts, h = ts }
            end
        end
    end
    return CollisionSystem.buildGrid(rects, 32)
end

function SceneManager.new()
    return setmetatable({
        currentScene = "farm",
        tileset = nil,
        map = nil,
        player = nil,
        entitySystem = nil,
        structureSystem = nil,
        farmBlockSystem = nil,
        buildMenu = nil,
        farmSystem = nil,
        crafting = nil,
        placement = nil,
        camera = Camera.new(),
        hud = nil,
        lootUI = LootUI.new(),
        spawnerSystem = SpawnerSystem.new(),
        collisionGrid = nil,
        dungeonLayout = nil,
        groundTile = GROUND_TILE,
        farmSpawnX = 0,
        farmSpawnY = 0,
        hoveredInteractor = nil,
        hotbarSlotTex = nil,
        notebook = Notebook.new(),
        notebookRobotDir = 0,
        particles = ParticleSystem.new(),
        itemIcons = ItemIcons.new(),
        notebookBtnRect = { x = 0, y = 0, w = 110, h = 34 },
        pendingBreaks = {},
        dialogue = DialogueSystem.new(),
        expeditionTracker = ExpeditionTracker.new(),
        toasts = Toasts.new(),
        robotPuzzleBank = RobotPuzzleBank.new(),
        activeRobotPuzzle = nil,
        cropbotInvByUid = {},
        expeditionSnapshot = nil,
        pendingExpeditionReturn = false,
    }, SceneManager)
end

function SceneManager:load()
    if self.map then return end
    local tileset, err = TileSet.load("assets/tileset.json", "assets/tileset.png")
    if not tileset then
        error("TileSet load failed: " .. tostring(err))
    end
    self.tileset = tileset

    local okSlot, slotTex = pcall(love.graphics.newImage, "assets/ui/hotbar-slot.png")
    if okSlot then
        Gfx.setNearest(slotTex)
        self.hotbarSlotTex = slotTex
    end

    self.structureSystem = StructureSystem.new()
    self.structureSystem:loadDefs("src/structure")

    self.farmBlockSystem = FarmBlockSystem.new()
    SoilInteraction.registerSoilType(self.farmBlockSystem, GROUND_TILE)
    self.farmSystem = FarmSystem.new()
    self.crafting = Crafting.new()

    self.entitySystem = EntitySystem.new()
    self.entitySystem:loadDefs({
        "src/entity/enemy",
        "src/entity/friend",
        "src/entity/misc",
    })

    FarmScene.resetSave()
    self:loadFarmScene()

    -- Load generated robot puzzles (ok if missing during dev).
    self.robotPuzzleBank:load()

    local tex
    local ok, img = pcall(love.graphics.newImage, "assets/objects/player01.png")
    if ok then Gfx.setNearest(img); tex = img end

    -- Centered hitbox so movement and sprite alignment stay in sync.
    self.player = Player.new(
        { x = self.farmSpawnX, y = self.farmSpawnY },
        tex,
        { x = -4, y = -4, w = 8, h = 8 }
    )

    local inv = Inventory.new()
    inv:add("wooden_hoe", 1)
    inv:add("wooden_axe", 1)
    self.player:setInventory(inv)
    self.placement = Placement.new(self.structureSystem, self.entitySystem)
    self.player:setHooks({
        onDashStart = function(p)
            local px, py = p:getPosition()
            self.particles:emitDashAfterimage(px, py, p:getTexture(), p:getDrawScale())
        end,
        onUpdated = function(p, dt)
            if p:isDashing() or p:isMoving(40) then
                local px, py = p:getPosition()
                local vx, vy = p:getVelocity()
                self.particles:emitDustTrail(px, py, vx, vy)
            end
        end
    })

    self.notebook:setRobotHooks({
        move = function()
            local px, py = self.player:getPosition()
            local step = self.map and self.map.tileSize or 16
            if self.notebookRobotDir == 0 then
                self.player:setPosition(px, py - step)
            elseif self.notebookRobotDir == 1 then
                self.player:setPosition(px + step, py)
            elseif self.notebookRobotDir == 2 then
                self.player:setPosition(px, py + step)
            else
                self.player:setPosition(px - step, py)
            end
            self.notebook:log("[game] move")
            return true
        end,
        left_turn = function()
            self.notebookRobotDir = (self.notebookRobotDir + 3) % 4
            self.notebook:log("[game] left_turn")
            return true
        end,
        right_turn = function()
            self.notebookRobotDir = (self.notebookRobotDir + 1) % 4
            self.notebook:log("[game] right_turn")
            return true
        end,
        half_turn = function()
            self.notebookRobotDir = (self.notebookRobotDir + 2) % 4
            self.notebook:log("[game] half_turn")
            return true
        end,
        collect = function()
            self.notebook:log("[game] collect")
            return true
        end,
        unlock = function()
            self.notebook:log("[game] unlock")
            return true
        end,
        attack = function()
            self.notebook:log("[game] attack")
            return true
        end,
        flag = function()
            self.notebook:log("[game] flag")
            return true
        end,
    })
    self.notebook:setRobotViz(function()
        local px, py = self.player:getPosition()
        local ts = self.map and self.map.tileSize or 16
        local dir = ({ "up", "right", "down", "left" })[(self.notebookRobotDir % 4) + 1]
        return { tx = math.floor(px / ts), ty = math.floor(py / ts), dir = dir }
    end)
    self.notebook:setToastCallback(function(text, opts)
        self.toasts:push(text, opts)
    end)

    self.buildMenu = BuildMenu.new(self.structureSystem, self.tileset)
    self.hud = HUD.new(self.player)
    inv:setCrafting({
        list = function()
            local rows = self.crafting:getVisible(inv, self.player)
            local out = {}
            for _, r in ipairs(rows) do
                out[#out + 1] = {
                    id = r.recipe.id,
                    label = r.recipe.label,
                    craftable = r.craftable,
                    outItem = r.recipe.out and r.recipe.out.item or nil,
                    outCount = r.recipe.out and r.recipe.out.count or nil,
                    outCogs = r.recipe.outCogs,
                    inItems = r.recipe.inItems,
                    inCogs = r.recipe.inCogs,
                }
            end
            return out
        end,
        craft = function(recipeId, amount)
            self.crafting:craft(inv, self.player, recipeId, amount)
        end
    })

    self.collisionGrid = buildCollisionGrid(self.map)
    self.camera:setSize(love.graphics.getDimensions())
end

function SceneManager:loadFarmScene()
    local w, h = FarmScene.MAP_WIDTH, FarmScene.MAP_HEIGHT
    self.map = TileMap.new(w, h, 16, self.tileset)
    self.currentScene = "farm"
    self.dungeonLayout = nil
    self.spawnerSystem:clear()

    local loaded = FarmScene.load(self.map, self.farmBlockSystem, self.farmSystem, self.structureSystem)
    if not loaded then
        self.farmSpawnX, self.farmSpawnY = FarmScene.generate(
            self.map,
            self.structureSystem,
            self.farmBlockSystem,
            self.groundTile
        )
    else
        local inset = FarmScene.insetCoreRect()
        local ts = self.map.tileSize
        self.farmSpawnX = (inset.x + inset.w * 0.5) * ts
        self.farmSpawnY = (inset.y + inset.h * 0.5) * ts
        self.map:setBorderRect({
            x = inset.x * ts,
            y = inset.y * ts,
            w = inset.w * ts,
            h = inset.h * ts,
        })
    end

    if self.player then
        self.player:setPosition(self.farmSpawnX, self.farmSpawnY)
        self.player:healFull()
    end
    self.collisionGrid = buildCollisionGrid(self.map)
end

function SceneManager:loadExpeditionScene()
    self.currentScene = "expedition"
    local w, h = DungeonGenerator.WIDTH, DungeonGenerator.HEIGHT
    self.map = TileMap.new(w, h, 16, self.tileset)
    self.structureSystem:clearInteractors()
    self.dungeonLayout = DungeonGenerator.generate(self.map, self.structureSystem, DungeonGenerator.SEED)
    self.spawnerSystem:registerFromMap(self.map, self.structureSystem, self.dungeonLayout.rooms)

    local ts = self.map.tileSize
    local spawnX = (w * 0.5 + 0.5) * ts
    local spawnY = (h * 0.5 + 0.5) * ts
    if self.player then
        self.player:setPosition(spawnX, spawnY)
    end
    local inv = self.player and self.player:getInventory() or nil
    self.expeditionSnapshot = {
        inventory = inv and inv:snapshot() or nil,
        cogs = self.player and self.player:getCogs() or 0,
    }
    self.pendingExpeditionReturn = false
    self.collisionGrid = buildCollisionGrid(self.map)

    -- Start expedition timer & hook kill tracking
    self.expeditionTracker:start()
    self.entitySystem.onKill = function(inst)
        self.expeditionTracker:addKill()
    end
end

function SceneManager:warp(sceneName)
    if sceneName == self.currentScene then return end

    self.lootUI:close()

    -- Leaving expedition -> show victory
    if self.currentScene == "expedition" and sceneName == "farm" then
        self.expeditionTracker:finishVictory()
        self.pendingExpeditionReturn = true
        self.entitySystem.onKill = nil
        return
    end

    if self.currentScene == "farm" then
        FarmScene.save(self.map, self.farmBlockSystem, self.farmSystem, self.structureSystem)
    end

    self.entitySystem:clear()

    if sceneName == "expedition" or sceneName == "dungeon" then
        self:loadExpeditionScene()
    elseif sceneName == "farm" then
        self:loadFarmScene()
    end
end

function SceneManager:handleInteract()
    local px, py = self.player:getPosition()
    local mx, my = love.mouse.getPosition()
    local mwx, mwy = self.camera:screenToWorld(mx, my)

    if self.hoveredInteractor then
        local results = self.structureSystem:executeInteract(self.hoveredInteractor)
        for _, res in ipairs(results) do
            if res.type == "warp" then
                self:warp(res.target)
                return
            elseif res.type == "loot" then
                self.lootUI:open(res.tableId, res.area)
                return
            elseif res.type == "lock_puzzle" then
                self.notebook:open()
                self.notebook:showTab("programming")
                local puzzle = self.robotPuzzleBank:get(res.puzzleId)
                    or (res.puzzleId == "basic_lock" and self.robotPuzzleBank:random("VERY_EASY"))
                    or (res.puzzleId == "locked_loot" and self.robotPuzzleBank:random("MEDIUM_HARD"))
                if puzzle and puzzle.robot then
                    self.notebook:setRobotPuzzle(puzzle.robot)
                    self.notebook:setSource("-- Write your program to solve the lock.\n")
                    self.notebook:discoverFromPuzzle(puzzle)
                    self.notebook:log("[lock] Objective: " .. tostring((puzzle.robot.objective and puzzle.robot.objective.kind) or "flag"))
                else
                    -- fallback tiny tutorial puzzle if generation not present
                    self.notebook:setRobotPuzzle({
                        dir = "right",
                        objective = { kind = "flag" },
                        lines = {
                            ". . . . .",
                            ". R . . F",
                            ". # # # .",
                            ". . . . .",
                            ". . . . .",
                        },
                    })
                    self.notebook:setSource("-- Write your program to solve the lock.\n")
                    self.notebook:discover("move")
                    self.notebook:discover("flag")
                    self.notebook:log("[lock] (fallback puzzle)")
                end
                self.activeRobotPuzzle = {
                    interactor = self.hoveredInteractor,
                    puzzleId = res.puzzleId,
                    area = res.area,
                }
                self.dialogue:say("Lock", "Solve the lock puzzle to pass this hallway.")
                return
            elseif res.type == "chop" then
                local item = self.player:getInventory():getActiveItem()
                local axeTier = item and Tools.getAxeTier(item.id) or nil
                if axeTier then
                    local tx, ty = self.map:worldToTile(res.area.x + 1, res.area.y + 1)
                    local inst = self.structureSystem:findInstanceAt(tx, ty)
                    if inst then
                        local t = math.max(0.3, 1.5 - (axeTier or 1) * 0.2)
                        self.structureSystem:shakeInstance(inst, t)
                        for _, p in ipairs(self.pendingBreaks) do
                            if p.inst == inst then return end
                        end
                        self.pendingBreaks[#self.pendingBreaks + 1] = {
                            inst = inst,
                            t = t,
                            kind = res.target,
                        }
                    end
                end
                return
            elseif res.type == "rock" then
                local tx, ty = self.map:worldToTile(res.area.x + 1, res.area.y + 1)
                local inst = self.structureSystem:findInstanceAt(tx, ty)
                if not inst then return end
                if res.target == "small" then
                    self.player:getInventory():add("stone", 1)
                    self.structureSystem:removeInstance(self.map, inst)
                    self.collisionGrid = buildCollisionGrid(self.map)
                    return
                end
                local item = self.player:getInventory():getActiveItem()
                local pickTier = item and Tools.getPickaxeTier(item.id) or nil
                if pickTier then
                    self.player:getInventory():add("stone", 2)
                    self.structureSystem:removeInstance(self.map, inst)
                    self.collisionGrid = buildCollisionGrid(self.map)
                else
                    self.dialogue:say("Rock", "This one needs a pickaxe.")
                end
                return
            end
        end
    end

    -- Interact with nearby cropbot to open its inventory (loot-chest style).
    do
        local best, bestD2 = nil, 999999
        for _, inst in ipairs(self.entitySystem.instances or {}) do
            if inst.alive and inst.defId == "cropbot" then
                local dx = inst.pos.x - px
                local dy = inst.pos.y - py
                local d2 = dx * dx + dy * dy
                if d2 < bestD2 then
                    best, bestD2 = inst, d2
                end
            end
        end
        if best and bestD2 <= (60 * 60) then
            local Inventory = require("src.Inventory")
            self.cropbotInvByUid[best.uid] = self.cropbotInvByUid[best.uid] or Inventory.new()
            self.lootUI:openCustom("cropbot:" .. tostring(best.uid), self.cropbotInvByUid[best.uid], "Cropbot")
            self.dialogue:say("Cropbot", "Put seeds in, take crops out. It will farm nearby soil.")
            return
        end
    end

    local tx, ty = self.map:worldToTile(mwx, mwy)
    local inv = self.player:getInventory()
    if self.farmSystem and self.farmSystem:tryInteract(self.map, tx, ty, inv) then
        return
    end
end

function SceneManager:update(dt)
    self.notebook:update(dt)
    self.dialogue:update(dt)
    self.toasts:update(dt)
    local inv = self.player:getInventory()
    local uiBlocked = self.notebook:capturesInput()
        or self.lootUI:isOpen()
        or (inv and inv:isWheelOpen())
        or self.buildMenu:capturesInput()
        or self.dialogue:isActive()
        or (self.player:isDead() and self.currentScene == "expedition")

    if not uiBlocked then
        self.player:update(dt, self.map, self.collisionGrid)
    end

    local px, py = self.player:getPosition()
    local phb = self.player:getWorldHitbox()
    local playerInfo = { x = phb.x, y = phb.y, w = phb.w, h = phb.h }

    if self.currentScene == "expedition" then
        self.spawnerSystem:update(dt, px, py, self.map, self.entitySystem)
    end

    self.entitySystem:update(dt, self.map, self.collisionGrid, playerInfo, {
        farmSystem = self.farmSystem,
        cropbotInv = function(uid) return self.cropbotInvByUid[uid] end,
    })
    self.entitySystem:processDamageEvents(self.player)

    if self.currentScene == "expedition" and self.player:isDead()
        and not self.expeditionTracker:isShowingResult() then
        self.expeditionTracker.corrupted = true
        self.expeditionTracker.active = false
        self.expeditionTracker.showResult = true
        self.expeditionTracker.resultAlpha = 0
        self.pendingExpeditionReturn = true
        self.entitySystem.onKill = nil
    end

    self.farmBlockSystem:update(dt, self.map)
    self.structureSystem:update(dt)
    self:updatePendingBreaks(dt)
    if self.farmSystem then
        self.farmSystem:update(dt, self.map)
    end

    local mx, my = love.mouse.getPosition()
    local mwx, mwy = self.camera:screenToWorld(mx, my)
    local hovered = self.structureSystem:findHovered(mwx, mwy, px, py)
    if hovered then
        local actions = self.structureSystem:executeInteract(hovered)
        local inv = self.player:getInventory()
        local item = inv and inv:getActiveItem() or nil
        local hasAxe = item and Tools.getAxeTier(item.id)
        for _, act in ipairs(actions) do
            if act.type == "chop" and not hasAxe then
                hovered = nil
                break
            end
        end
    end
    self.hoveredInteractor = hovered

    self.buildMenu:update(dt, self.map, mwx, mwy, self.player, self.groundTile)
    self.particles:update(dt)
    self.camera:follow(px, py, dt)
    self.map:update()

    -- Resolve active robot puzzle -> unlock/transform structures.
    if self.activeRobotPuzzle and self.notebook.robotPuzzle then
        local st = self.notebook.robotPuzzle:getVizState()
        if st and st.solved then
            local area = self.activeRobotPuzzle.area
            local tx, ty = self.map:worldToTile(area.x + 1, area.y + 1)
            local inst = self.structureSystem:findInstanceAt(tx, ty)
            if inst then
                self.structureSystem:removeInstance(self.map, inst)
                if self.activeRobotPuzzle.puzzleId == "locked_loot" then
                    self.structureSystem:place(self.map, "unlocked_loot_block", tx, ty)
                    self.toasts:push("Unlocked loot chest!", { kind = "discover" })
                else
                    self.toasts:push("Unlocked!", { kind = "discover" })
                end
                self.collisionGrid = buildCollisionGrid(self.map)
            end
            self.activeRobotPuzzle = nil
            self.notebook:setRobotPuzzle(nil)
            self.notebook:close()
        end
    end

    -- Expedition timer
    local tracker = self.expeditionTracker
    local wasActive = tracker:isActive()
    tracker:update(dt)
    if wasActive and not tracker:isActive() and tracker:isCorrupted() then
        -- Time ran out: show corruption result, then return to farm on dismiss.
        self.pendingExpeditionReturn = true
    end
end

function SceneManager:updatePendingBreaks(dt)
    local keep = {}
    for _, br in ipairs(self.pendingBreaks) do
        br.t = br.t - dt
        if br.t <= 0 then
            if br.inst and self.structureSystem:removeInstance(self.map, br.inst) then
                if br.kind == "tree" then
                    self.player:getInventory():add("wood", love.math.random(2, 3))
                elseif br.kind == "stump" then
                    self.player:getInventory():add("wood", 1)
                end
                self.collisionGrid = buildCollisionGrid(self.map)
            end
        else
            keep[#keep + 1] = br
        end
    end
    self.pendingBreaks = keep
end

function SceneManager:draw()
    local cam = self.camera
    local view = cam:getViewRect()
    love.graphics.clear(0.08, 0.1, 0.12, 1)

    cam:apply()
    self.map:drawBackground(view.x, view.y, view.w, view.h)
    self.map:drawForeground(view.x, view.y, view.w, view.h)
    self.entitySystem:draw()
    self.particles:draw()
    if not (self.player:isDead() and self.currentScene == "expedition") then
        self.player:draw()
    end
    self:drawHeldItem()
    self.map:drawOverlay(view.x, view.y, view.w, view.h)

    self.structureSystem:drawHighlight(self.hoveredInteractor)
    self.structureSystem:drawShaking(self.map, self.tileset, view)
    self.structureSystem:drawEffects()

    local mx, my = love.mouse.getPosition()
    local mwx, mwy = cam:screenToWorld(mx, my)
    local tx, ty = self.map:worldToTile(mwx, mwy)
    if self.farmSystem then
        self.farmSystem:drawHighlight(self.map, tx, ty, self.player:getInventory())
    end

    if self.buildMenu:isOpen() then
        self.buildMenu:draw(self.map, self.tileset, mwx, mwy, self.groundTile)
    end

    cam:reset()

    self.hud:draw()
    local inv = self.player:getInventory()
    if inv then
        inv:draw(self.tileset, self.hotbarSlotTex)
    end
    if self.lootUI:isOpen() then
        self.lootUI:draw(inv, self.tileset, self.hotbarSlotTex)
    end

    self.notebook:draw()
    self:drawNotebookButton()
end

function SceneManager:drawPostUI()
    self.dialogue:draw()
    self:drawSoilStageTooltip()
    self.toasts:draw()

    -- Expedition overlays
    self.expeditionTracker:drawDangerAura()
    self.expeditionTracker:drawTimer()
    self.expeditionTracker:drawResultScreen()
end

function SceneManager:drawSoilStageTooltip()
    if not self.farmSystem or not self.map then return end
    local mx, my = love.mouse.getPosition()
    local mwx, mwy = self.camera:screenToWorld(mx, my)
    local tx, ty = self.map:worldToTile(mwx, mwy)
    local text = self.farmSystem:getHoverStageText(self.map, tx, ty)
    if not text then return end

    local font = love.graphics.getFont()
    local pad = 8
    local w = font:getWidth(text) + pad * 2
    local h = font:getHeight() + pad * 2
    local x = love.graphics.getWidth() - w - 14
    local y = love.graphics.getHeight() - h - 14
    love.graphics.setColor(0, 0, 0, 0.76)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    love.graphics.setColor(0.95, 0.95, 0.95, 1)
    love.graphics.rectangle("line", x, y, w, h, 4, 4)
    love.graphics.print(text, x + pad, y + pad)
    love.graphics.setColor(1, 1, 1, 1)
end

function SceneManager:drawHeldItem()
    local inv = self.player:getInventory()
    if not inv then return end
    local item = inv:getActiveItem()
    if not item then return end
    local img = self.itemIcons:getImage(item.id)
    if not img then return end
    local ptex = self.player:getTexture()
    if not ptex then return end

    local px, py = self.player:getPosition()
    local _, pH = ptex:getDimensions()
    local playerH = pH * self.player:getDrawScale()
    local itemH = playerH / 3
    local itemW = img:getWidth() * (itemH / img:getHeight())
    local dx, dy = self.player:getFacingDirection()
    local ox = dx * (itemW * 0.6)
    local oy = -itemH * 0.25 + dy * 3
    if math.abs(dx) > math.abs(dy) then
        oy = oy - 2
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, px + ox - itemW * 0.5, py + oy - itemH * 0.5, 0, itemW / img:getWidth(), itemH / img:getHeight())
end

function SceneManager:drawNotebookButton()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local w, h = 116, 34
    local x, y = sw - w - 10, sh - h - 10
    self.notebookBtnRect = { x = x, y = y, w = w, h = h }
    love.graphics.setColor(0.06, 0.06, 0.08, 0.96)
    love.graphics.rectangle("fill", x, y, w, h, 1, 1)
    love.graphics.setColor(0.22, 0.18, 0.12, 1)
    love.graphics.rectangle("fill", x + 1, y + 1, w - 2, 5)
    love.graphics.setColor(0.95, 0.82, 0.42, 1)
    love.graphics.rectangle("line", x, y, w, h, 1, 1)

    love.graphics.setColor(0.92, 0.87, 0.75, 1)
    love.graphics.rectangle("fill", x + 9, y + 8, 11, 18, 1, 1)
    love.graphics.setColor(0.48, 0.35, 0.18, 1)
    love.graphics.rectangle("line", x + 9, y + 8, 11, 18, 1, 1)
    love.graphics.line(x + 15, y + 8, x + 15, y + 26)
    love.graphics.line(x + 13, y + 12, x + 17, y + 12)

    love.graphics.setColor(0.97, 0.95, 0.86, 1)
    love.graphics.print("Notebook", x + 24, y + 9)
    love.graphics.setColor(1, 1, 1, 1)
end

function SceneManager:keypressed(key)
    -- Dismiss expedition result screen first
    if self.expeditionTracker:isShowingResult() then
        if self.pendingExpeditionReturn then
            self.pendingExpeditionReturn = false
            self.entitySystem.onKill = nil
            self.entitySystem:clear()
            self.lootUI:close()
            if self.expeditionTracker:isCorrupted() and self.expeditionSnapshot then
                local inv = self.player:getInventory()
                if inv then inv:applySnapshot(self.expeditionSnapshot.inventory) end
                self.player:removeCogs(self.player:getCogs())
                self.player:addCogs(self.expeditionSnapshot.cogs or 0)
            end
            self:loadFarmScene()
            if self.player then self.player:healFull() end
        end
        self.expeditionTracker:dismissResult()
        return
    end

    local inv = self.player:getInventory()
    self.dialogue:keypressed(key)
    if self.dialogue:isActive() then
        return
    end

    if self.notebook:capturesInput() then
        if key == "escape" then
            self.notebook:close()
            return
        end
        local CustomUI = require("src.ui.CustomUI")
        CustomUI.keypressed(key)
        return
    end

    if self.lootUI:isOpen() then
        if key == "escape" then
            self.lootUI:close()
        end
        return
    end

    if inv and (key == "i" or key == "tab") then
        inv:toggleWheel()
        return
    end

    if inv and inv:isWheelOpen() then
        if key == "escape" then
            inv.wheelOpen = false
            return
        end
        -- allow mouse/keyboard escape handling first, digits handled below
    end

    -- global number hotkeys: 1-9 and 0 map to slots 1-10 even if empty
    local n = tonumber(key)
    if inv and n and ((n >= 1 and n <= 9) or n == 0) then
        local slot = (n == 0) and 10 or n
        inv.selectedSlot = slot - 1
        inv.wheelOpen = false
        return
    end

    if self.buildMenu:capturesInput() then
        if key == "escape" then
            self.buildMenu:closeAll()
        end
        return
    end

    if key == "b" then
        self.buildMenu:openGallery()
    elseif key == "p" or key == "n" then
        self.notebook:toggle()
    elseif key == "f3" then
        if self.currentScene == "farm" then
            self:warp("expedition")
        else
            self:warp("farm")
        end
    end
end

function SceneManager:keyreleased(key)
    self.dialogue:keyreleased(key)
end

function SceneManager:mousepressed(x, y, button)
    -- Dismiss expedition result screen first
    if self.expeditionTracker:isShowingResult() then
        if self.pendingExpeditionReturn then
            self.pendingExpeditionReturn = false
            self.entitySystem.onKill = nil
            self.entitySystem:clear()
            self.lootUI:close()
            if self.expeditionTracker:isCorrupted() and self.expeditionSnapshot then
                local inv = self.player:getInventory()
                if inv then inv:applySnapshot(self.expeditionSnapshot.inventory) end
                self.player:removeCogs(self.player:getCogs())
                self.player:addCogs(self.expeditionSnapshot.cogs or 0)
            end
            self:loadFarmScene()
            if self.player then self.player:healFull() end
        end
        self.expeditionTracker:dismissResult()
        return
    end

    local inv = self.player:getInventory()

    if button == 1 then
        local r = self.notebookBtnRect
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            self.notebook:toggle()
            return
        end
    end

    if self.notebook:capturesInput() then
        return
    end

    if self.lootUI:isOpen() then
        if button == 1 then
            self.lootUI:handleClick(inv, x, y, self.player)
        end
        return
    end

    if inv and inv:handlePointer(x, y, button == 1) then
        return
    end

    if inv and inv:isWheelOpen() then
        return
    end

    local cam = self.camera
    local mwx, mwy = cam:screenToWorld(x, y)
    local tx, ty = self.map:worldToTile(mwx, mwy)

    if button == 1 and inv then
        local item = inv:getActiveItem()
        local hoeTier = item and Tools.getHoeTier(item.id) or nil
        if hoeTier and self.farmSystem and self.farmSystem:tryHoe(self.map, tx, ty, inv) then
            return
        end
    end

    if button == 1 and inv and self.farmSystem and self.farmSystem:tryInteract(self.map, tx, ty, inv) then
        return
    end

    if button == 1 and self.hoveredInteractor and not self.buildMenu:capturesInput() then
        self:handleInteract()
        return
    end

    if button == 1 and inv then
        local item = inv:getActiveItem()
        if item and self.placement then
            local placed = self.placement:tryPlace(item.id, self.map, tx, ty, mwx, mwy)
            if placed then
                inv:remove(item.id, 1)
                self.collisionGrid = buildCollisionGrid(self.map)
                if type(placed) == "table" and placed.defId == "cropbot" then
                    local Inventory = require("src.Inventory")
                    self.cropbotInvByUid[placed.uid] = self.cropbotInvByUid[placed.uid] or Inventory.new()
                    self.toasts:push("Cropbot deployed (has its own inventory).", { kind = "discover" })
                end
                return
            end
        end
    end

    if self.buildMenu:capturesInput() then
        if self.buildMenu:mousepressed(button, self.map, mwx, mwy, self.player, self.groundTile) then
            self.collisionGrid = buildCollisionGrid(self.map)
        end
    end
end

function SceneManager:getCurrentScene()
    return self.currentScene
end

return SceneManager
