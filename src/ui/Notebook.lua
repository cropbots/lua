--- Programming notebook (CustomUI): Programming + Discovery tabs.

local CustomUI = require("src.ui.CustomUI")
local Khoron = require("init")
local RobotPuzzle = require("src.puzzle.RobotPuzzle")
local LuaHighlighter = require("src.ui.LuaHighlighter")

local Notebook = {}
Notebook.__index = Notebook

local ALMANAC = {
    { id = "print",      desc = "Print values to the console." },
    { id = "input",      desc = "Read a line of text." },
    { id = "move",       desc = "Move the robot forward." },
    { id = "left_turn",  desc = "Turn the robot left." },
    { id = "right_turn", desc = "Turn the robot right." },
    { id = "half_turn",  desc = "Turn the robot around (180°)." },
    { id = "collect",    desc = "Collect the key node in front of the robot." },
    { id = "unlock",     desc = "Unlock the lock node in front (matching key color)." },
    { id = "attack",     desc = "Delete the enemy node in front." },
    { id = "flag",       desc = "Win if there is a flag node in front." },
    { id = "turn_left",  desc = "Legacy alias for left_turn()." },
    { id = "turn_right", desc = "Legacy alias for right_turn()." },
}

function Notebook.new()
    local self = setmetatable({
        opened = false,
        tab = "programming",
        source = 'print("Hello from Khoron")\n',
        consoleLog = "",
        stepper = nil,
        discovered = {
            print = true,
            input = true,
            move = true,
            left_turn = true,
            right_turn = true,
            half_turn = true,
            collect = true,
            unlock = true,
            attack = true,
            flag = true,
            turn_left = true,
            turn_right = true,
        },
        puzzleDef = nil,
        robotHooks = {},
        speedIdx = 4,
        speedNames = { "cheetah", "speedster", "fast", "regular", "slow", "turtle" },
        speedLabels = { "Cheetah", "Speedster", "Fast", "Regular", "Slow", "Turtle" },
        robotViz = nil,
        onToast = nil,
        robotPuzzle = nil,
        robotCanvas = nil,
        robotCanvasW = 0,
        robotCanvasH = 0,
        editorInputId = 1,
        runningLine = nil,
    }, Notebook)
    return self
end

function Notebook:setToastCallback(fn)
    self.onToast = fn
end

function Notebook:discover(id)
    if self.discovered[id] then return end
    self.discovered[id] = true
    if self.onToast then
        self.onToast("Discovered " .. tostring(id) .. "()", { kind = "discover" })
    end
end

function Notebook:log(line)
    self.consoleLog = self.consoleLog .. line .. "\n"
end

function Notebook:setRobotPuzzle(def)
    if not def then
        self.robotPuzzle = nil
        self.runningLine = nil
        return
    end
    self.robotPuzzle = RobotPuzzle.fromLines(def.lines or {}, {
        dir = def.dir or "up",
        objective = def.objective or { kind = "flag" },
    })
    local p = self.robotPuzzle
    self:setRobotHooks({
        move = function() return p:move() end,
        right_turn = function() return p:right_turn() end,
        left_turn = function() return p:left_turn() end,
        half_turn = function() return p:half_turn() end,
        collect = function() return p:collect() end,
        unlock = function() return p:unlock() end,
        attack = function() return p:attack() end,
        flag = function() return p:flag() end,
    })
    self.stepper = nil
    self.consoleLog = ""
    self.runningLine = nil
end

function Notebook:builtins()
    return Khoron.defaultBuiltins(self)
end

function Notebook:setSource(text)
    self.source = tostring(text or "")
    self.editorInputId = self.editorInputId + 1
    if self.opened and self.tab == "programming" then
        CustomUI.focusedWidgetId = "Editor" .. tostring(self.editorInputId)
    end
end

function Notebook:discoverFromPuzzle(puzzle)
    if not puzzle then return end
    local robot = puzzle.robot or {}
    self:discover("move")
    self:discover("left_turn")
    self:discover("right_turn")
    self:discover("half_turn")
    self:discover("turn_left")
    self:discover("turn_right")

    local obj = robot.objective and robot.objective.kind
    if obj == "flag" or not obj then self:discover("flag") end
    if obj == "collect_all_keys" then self:discover("collect") end
    if obj == "kill_all_enemies" then self:discover("attack") end

    for _, ln in ipairs(robot.lines or {}) do
        local s = tostring(ln)
        if s:match("[^%w]F[^%w]") or s:match("F$") or s:match("^F ") or s:match(" R .- F") then
            self:discover("flag")
        end
        if s:match("K[1-8]") then self:discover("collect") end
        if s:match("L[1-8]") then self:discover("unlock") end
        if s:match("E") then self:discover("attack") end
    end
end

function Notebook:loadPuzzle(path)
    local chunk, err = love.filesystem.load(path)
    if not chunk then return false, err end
    local ok, def = pcall(chunk)
    if not ok then return false, def end
    self.puzzleDef = def
    if def.starter then self:setSource(def.starter) end
    if def.robot then
        self:setRobotPuzzle(def.robot)
    end
    self:discoverFromPuzzle(def)
    return true
end

function Notebook:fillAlmanac()
    local lines = {}
    for _, e in ipairs(ALMANAC) do
        if self.discovered[e.id] then
            lines[#lines + 1] = e.id .. ": " .. e.desc
        else
            lines[#lines + 1] = "?: ???"
        end
    end
    return table.concat(lines, "\n")
end

function Notebook:showTab(name)
    self.tab = name
    if self.opened and self.tab == "programming" then
        CustomUI.focusedWidgetId = "Editor" .. tostring(self.editorInputId)
    elseif self.opened then
        CustomUI.focusedWidgetId = nil
    end
end

function Notebook:open()
    self.opened = true
    pcall(love.keyboard.setTextInput, true)
    pcall(love.keyboard.setKeyRepeat, true)
    if self.tab == "programming" then
        CustomUI.focusedWidgetId = "Editor" .. tostring(self.editorInputId)
    end
end

function Notebook:close()
    self.opened = false
    self.stepper = nil
    pcall(love.keyboard.setTextInput, false)
    pcall(love.keyboard.setKeyRepeat, false)
    CustomUI.focusedWidgetId = nil
end

function Notebook:toggle()
    if self.opened then self:close() else self:open() end
end

function Notebook:setRobotHooks(hooks)
    self.robotHooks = hooks or {}
end

function Notebook:setRobotViz(getter)
    self.robotViz = getter
end

local function ensureCanvas(self, w, h)
    w = math.max(1, math.floor(w))
    h = math.max(1, math.floor(h))
    if not self.robotCanvas or self.robotCanvasW ~= w or self.robotCanvasH ~= h then
        self.robotCanvas = love.graphics.newCanvas(w, h)
        self.robotCanvas:setFilter("nearest", "nearest")
        self.robotCanvasW, self.robotCanvasH = w, h
    end
end

function Notebook:drawRobotGridCanvas(st, w, h)
    ensureCanvas(self, w, h)
    love.graphics.push("all")
    love.graphics.setCanvas(self.robotCanvas)
    love.graphics.clear(0.08, 0.08, 0.1, 1)

    if not st or not st.grid then
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.print("No robot puzzle loaded.", 10, 10)
        love.graphics.setCanvas()
        love.graphics.pop()
        return
    end

    local pad = 10
    local gw = w - pad * 2
    local gh = h - pad * 2
    local cell = math.floor(math.min(gw / st.w, gh / st.h))
    cell = math.max(10, cell)
    local ox = pad + math.floor((gw - cell * st.w) * 0.5)
    local oy = pad + math.floor((gh - cell * st.h) * 0.5)

    local PALETTE = {
        { 0.92, 0.27, 0.28 }, -- 1 red
        { 0.98, 0.58, 0.18 }, -- 2 orange
        { 0.95, 0.86, 0.24 }, -- 3 yellow
        { 0.32, 0.86, 0.36 }, -- 4 green
        { 0.22, 0.76, 0.88 }, -- 5 cyan
        { 0.32, 0.48, 0.96 }, -- 6 blue
        { 0.72, 0.40, 0.95 }, -- 7 purple
        { 0.92, 0.40, 0.73 }, -- 8 pink
    }

    local function paletteColor(i)
        local c = PALETTE[math.max(1, math.min(8, tonumber(i) or 1))]
        return c[1], c[2], c[3]
    end

    local function tokenKind(tok)
        if tok == "#" then return "wall" end
        if tok == "M" then return "movable" end
        if tok == "E" then return "enemy" end
        if tok == "F" then return "flag" end
        if type(tok) == "string" and tok:match("^K[1-8]$") then return "key" end
        if type(tok) == "string" and tok:match("^L[1-8]$") then return "lock" end
        if tok == "." then return "empty" end
        return "other"
    end

    -- HUD
    do
        love.graphics.setColor(1, 1, 1, 0.9)
        local obj = st.objective and st.objective.kind or "flag"
        local extra = ""
        if obj == "kill_all_enemies" then
            extra = " | remaining enemies: " .. tostring(st.remainingEnemies or 0)
        elseif obj == "collect_all_keys" then
            extra = " | remaining keys: " .. tostring(st.remainingKeys or 0)
        end
        love.graphics.print("Objective: " .. tostring(obj) .. extra, 10, 8)
    end

    -- highlight "front of robot"
    local frontX, frontY = st.rx, st.ry
    do
        local fx, fy = 0, -1
        if st.dir == "right" then fx, fy = 1, 0 end
        if st.dir == "down" then fx, fy = 0, 1 end
        if st.dir == "left" then fx, fy = -1, 0 end
        frontX, frontY = st.rx + fx, st.ry + fy
    end

    for y = 1, st.h do
        for x = 1, st.w do
            local tok = st.grid[y][x]
            local px = ox + (x - 1) * cell
            local py = oy + (y - 1) * cell

            -- base tile
            love.graphics.setColor(0.14, 0.14, 0.18, 1)
            love.graphics.rectangle("fill", px, py, cell, cell)

            if x == frontX and y == frontY then
                love.graphics.setColor(1, 1, 1, 0.14)
                love.graphics.rectangle("fill", px, py, cell, cell)
            end

            local kind = tokenKind(tok)
            if kind == "wall" then
                love.graphics.setColor(0.10, 0.10, 0.12, 1)
                love.graphics.rectangle("fill", px, py, cell, cell)
            elseif kind == "movable" then
                love.graphics.setColor(0.55, 0.45, 0.28, 1)
                love.graphics.rectangle("fill", px + 2, py + 2, cell - 4, cell - 4, 3, 3)
                love.graphics.setColor(0.15, 0.10, 0.05, 0.8)
                love.graphics.print("M", px + 4, py + 2)
            elseif kind == "enemy" then
                love.graphics.setColor(0.90, 0.20, 0.22, 1)
                love.graphics.rectangle("fill", px + 2, py + 2, cell - 4, cell - 4, 3, 3)
                love.graphics.setColor(0.10, 0.02, 0.02, 0.85)
                love.graphics.print("E", px + 4, py + 2)
            elseif kind == "flag" then
                love.graphics.setColor(0.22, 0.86, 0.35, 1)
                love.graphics.rectangle("fill", px + 2, py + 2, cell - 4, cell - 4, 3, 3)
                love.graphics.setColor(0.02, 0.10, 0.03, 0.9)
                love.graphics.print("F", px + 4, py + 2)
            elseif kind == "key" then
                local col = tonumber(tok:sub(2, 2)) or 1
                local r, g, b = paletteColor(col)
                love.graphics.setColor(r, g, b, 1)
                love.graphics.rectangle("fill", px + 2, py + 2, cell - 4, cell - 4, 3, 3)
                love.graphics.setColor(0, 0, 0, 0.75)
                love.graphics.print("K", px + 4, py + 2)
            elseif kind == "lock" then
                local col = tonumber(tok:sub(2, 2)) or 1
                local r, g, b = paletteColor(col)
                love.graphics.setColor(r * 0.55, g * 0.55, b * 0.55, 1)
                love.graphics.rectangle("fill", px + 2, py + 2, cell - 4, cell - 4, 3, 3)
                love.graphics.setColor(1, 1, 1, 0.85)
                love.graphics.print("L", px + 4, py + 2)
            end

            love.graphics.setColor(0, 0, 0, 0.28)
            love.graphics.rectangle("line", px, py, cell, cell)
        end
    end

    -- robot body
    love.graphics.setColor(0.96, 0.96, 0.98, 1)
    local rpx = ox + (st.rx - 1) * cell
    local rpy = oy + (st.ry - 1) * cell
    love.graphics.rectangle("fill", rpx + 2, rpy + 2, cell - 4, cell - 4, 4, 4)
    love.graphics.setColor(0.05, 0.05, 0.07, 0.55)
    love.graphics.rectangle("line", rpx + 2, rpy + 2, cell - 4, cell - 4, 4, 4)

    -- facing marker (dot)
    local dx, dy = 0, -1
    if st.dir == "right" then dx, dy = 1, 0 end
    if st.dir == "down" then dx, dy = 0, 1 end
    if st.dir == "left" then dx, dy = -1, 0 end
    love.graphics.setColor(0, 0, 0, 0.65)
    local cx = ox + (st.rx - 0.5) * cell
    local cy = oy + (st.ry - 0.5) * cell
    love.graphics.circle("fill", cx + dx * (cell * 0.25), cy + dy * (cell * 0.25), math.max(2, cell * 0.08))

    -- held keys summary (bottom-left)
    do
        local keys = st.keys or {}
        local x0, y0 = 10, h - 44
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.print("Keys:", x0, y0)
        local kx = x0 + 46
        for i = 1, 8 do
            local n = keys[i] or 0
            if n > 0 then
                local r, g, b = paletteColor(i)
                love.graphics.setColor(r, g, b, 1)
                love.graphics.rectangle("fill", kx, y0 + 2, 12, 12, 3, 3)
                love.graphics.setColor(0, 0, 0, 0.75)
                love.graphics.print(tostring(n), kx + 14, y0 - 1)
                kx = kx + 30
            end
        end
    end

    -- status line
    love.graphics.setColor(1, 1, 1, 0.9)
    local status = st.solved and "SOLVED" or (st.failed and ("FAILED: " .. tostring(st.reason or "")) or "READY")
    love.graphics.print(status, w - 110, h - 22)

    love.graphics.setCanvas()
    love.graphics.pop()
end

function Notebook:update(dt)
    if not self.opened then return end

    if self.stepper and self.stepper.running then
        self.stepper:update(dt)
        self.runningLine = self.stepper.currentLine
    elseif self.stepper and not self.stepper.running then
        self.runningLine = nil
        self.stepper = nil
    end

    local w = math.min(1040, love.graphics.getWidth() - 18)
    local h = math.min(620, love.graphics.getHeight() - 18)
    local leftW = math.floor((w - 42) * 0.62)
    local rightW = (w - 42) - leftW
    local bodyH = h - 64
    local topTabW = math.max(88, math.min(140, math.floor((w - 32 - 24 - 84) / 3)))
    local actionW = math.max(56, math.min(76, math.floor((rightW - 16) / 4)))

    if not CustomUI.beginDialog("Notebook", "Notebook", { W = w, H = h }) then
        self.opened = false
        return
    end

    local shouldClose = false
    local ok, err = pcall(function()
        if CustomUI.dialogCloseButton() then
            shouldClose = true
        end

        -- Top bar: tabs + close on one row.
        if CustomUI.beginLayout("NotebookTopBar", { Columns = 2, widths = { w - 132, 100 } }) then
            CustomUI.setLayoutColumn(1)
            if CustomUI.button("btn_programming", "Programming", { W = topTabW }) then
                self:showTab("programming")
            end
            CustomUI.sameLine()
            if CustomUI.button("btn_discovery", "Discovery", { W = topTabW }) then
                self:showTab("discovery")
            end
            CustomUI.setLayoutColumn(2)
            if CustomUI.button("btn_close", "Close", { W = 92 }) then
                shouldClose = true
            end
            CustomUI.endLayout()
        end

        CustomUI.separator()

        if self.tab == "discovery" then
            CustomUI.text("Discovered functions", { W = w - 32 })
            CustomUI.separator()
            if CustomUI.beginScrollArea("DiscoveryScrollArea", { W = w - 32, H = bodyH - 44 }) then
                for _, e in ipairs(ALMANAC) do
                    if self.discovered[e.id] then
                        CustomUI.text(e.id .. "()", { Color = CustomUI.style.accent })
                        CustomUI.sameLine()
                        CustomUI.text("— " .. e.desc, { Color = CustomUI.style.text })
                    else
                        CustomUI.text("???()", { Color = CustomUI.style.textDim })
                        CustomUI.sameLine()
                        CustomUI.text("— Solve lock puzzles to discover this function.", { Color = CustomUI.style.textDim })
                    end
                end
                CustomUI.endScrollArea()
            end
        else
            -- IDE split: editor left, robot visualization + console right
            if CustomUI.beginLayout("NotebookIDE", { Columns = 2, widths = { leftW, rightW } }) then
                CustomUI.setLayoutColumn(1)
                self.source = CustomUI.editor("Editor" .. tostring(self.editorInputId), self.source, leftW, bodyH - 32, self.runningLine)
                if self.runningLine then
                    CustomUI.text("Running line: " .. tostring(self.runningLine), { W = leftW })
                end

                CustomUI.setLayoutColumn(2)
                -- Run controls above robot visualization
                if CustomUI.button("btn_play", "Play", { W = actionW }) then
                    if not self.stepper then
                        self.consoleLog = ""
                        local ok, s_err = pcall(function()
                            self.stepper = Khoron.stepper(self.source, self:builtins())
                        end)
                        if ok and self.stepper then
                            self.stepper.onPrint = function(line) self:log(line) end
                            self.stepper:setSpeed(self.speedNames[self.speedIdx] or "regular")
                            self.stepper:reset()
                        else
                            self:log("[notebook error] Parse failed: " .. tostring(s_err))
                        end
                    else
                        self.stepper.running = true
                    end
                end

                CustomUI.sameLine()
                if CustomUI.button("btn_pause", "Pause", { W = actionW }) then
                    if self.stepper then
                        self.stepper.running = false
                    end
                end

                CustomUI.sameLine()
                if CustomUI.button("btn_stop", "Stop", { W = actionW }) then
                    self.stepper = nil
                end

                CustomUI.sameLine()
                if CustomUI.button("btn_speed", "Speed: " .. self.speedLabels[self.speedIdx], { W = math.max(120, rightW - actionW * 3 - 24) }) then
                    self.speedIdx = self.speedIdx % 6 + 1
                    if self.stepper then
                        self.stepper:setSpeed(self.speedNames[self.speedIdx] or "regular")
                    end
                end

                CustomUI.separator()

                local vizW = rightW
                local vizH = math.floor((bodyH - 150) * 0.56)
                if self.robotPuzzle then
                    self:drawRobotGridCanvas(self.robotPuzzle:getVizState(), vizW, vizH)
                    CustomUI.image("RobotCanvas", self.robotCanvas, vizW, vizH)
                else
                    local st = self.robotViz and self.robotViz() or {}
                    CustomUI.text("Robot Visualization", { W = rightW })
                    CustomUI.text(("(%s, %s) dir=%s"):format(tostring(st.tx or 0), tostring(st.ty or 0), tostring(st.dir or "up")),
                        { W = rightW, H = vizH })
                end

                CustomUI.separator()
                CustomUI.text("Console", { W = rightW })
                CustomUI.text(self.consoleLog, { W = rightW, H = bodyH - 140 - vizH })

                CustomUI.endLayout()
            end
        end
    end)

    CustomUI.endDialog()

    if not ok then
        self:log("[notebook error] " .. tostring(err))
        self:close()
    elseif shouldClose then
        self:close()
    end
end

function Notebook:draw()
    -- CustomUI handles all dialog drawing; nothing to do here.
end

function Notebook:capturesInput()
    return self.opened
end

return Notebook
