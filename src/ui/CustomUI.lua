--- Custom UI system: pure LÖVE2D implementation of Slab widgets
-- with a custom code editor, syntax highlighting, and layout helper.

local LuaHighlighter = require("src.ui.LuaHighlighter")
local utf8 = require("utf8")

local CustomUI = {}

-- Style configuration (dark charcoal premium theme)
CustomUI.style = {
    bg = {0.07, 0.07, 0.08, 0.95},      -- Dialog background
    border = {0.18, 0.18, 0.22, 1},    -- Border outline
    headerBg = {0.11, 0.11, 0.14, 1},  -- Titlebar background
    text = {0.9, 0.9, 0.92, 1},         -- Normal text
    textDim = {0.55, 0.55, 0.6, 1},    -- Dimmed text (cogs, descriptions)
    accent = {0.85, 0.4, 0.1, 1},       -- Accent color (orange)
    accentHover = {0.95, 0.5, 0.15, 1}, -- Accent hover
    accentActive = {0.7, 0.3, 0.05, 1}, -- Accent active
    widgetBg = {0.04, 0.04, 0.05, 1},  -- Listbox/Editor background
    itemHover = {0.18, 0.18, 0.22, 1},  -- Listbox item hover
    itemSelect = {0.85, 0.4, 0.1, 0.35},-- Selected listbox item
    separator = {0.15, 0.15, 0.18, 1}, -- Separator line
    lineRunning = {0.1, 0.4, 0.15, 0.3},-- Running code line highlight
}

-- Global state
CustomUI.drawQueue = {}
CustomUI.widgetsState = {}
CustomUI.focusedWidgetId = nil

-- Click & Wheel event caches
local clickEvent = nil
local wheelEvent = nil
local activeDialog = nil

-- Layout context
local layout = {
    startX = 0,
    startY = 0,
    w = 0,
    h = 0,
    penX = 0,
    penY = 0,
    sameLine = false,
    prevX = 0,
    prevY = 0,
    prevW = 0,
    prevH = 0,
    columns = 1,
    currentCol = 1,
    colStartX = {},
    colWidths = {},
    colMaxY = {},
    scrollAreaId = nil,
    scrollAreaX = 0,
    scrollAreaY = 0,
    scrollAreaW = 0,
    scrollAreaH = 0,
    parentScrollY = 0,
    scrollY = 0,
}

-- TEXT SELECTION AND HISTORY HELPERS

local function hasSelection(state)
    return state.anchorLine ~= state.cursorLine or state.anchorCol ~= state.cursorCol
end

local function getSelectionRange(state)
    if not hasSelection(state) then
        return state.cursorLine, state.cursorCol, state.cursorLine, state.cursorCol
    end
    if state.anchorLine < state.cursorLine then
        return state.anchorLine, state.anchorCol, state.cursorLine, state.cursorCol
    elseif state.anchorLine > state.cursorLine then
        return state.cursorLine, state.cursorCol, state.anchorLine, state.anchorCol
    else
        if state.anchorCol < state.cursorCol then
            return state.anchorLine, state.anchorCol, state.cursorLine, state.cursorCol
        else
            return state.cursorLine, state.cursorCol, state.anchorLine, state.anchorCol
        end
    end
end

local function getSelectionText(state)
    if not hasSelection(state) then return "" end
    local startL, startC, endL, endC = getSelectionRange(state)
    
    if startL == endL then
        return (state.lines[startL] or ""):sub(startC, endC - 1)
    end
    
    local out = {}
    out[#out + 1] = (state.lines[startL] or ""):sub(startC)
    for idx = startL + 1, endL - 1 do
        out[#out + 1] = state.lines[idx] or ""
    end
    out[#out + 1] = (state.lines[endL] or ""):sub(1, endC - 1)
    return table.concat(out, "\n")
end

local function saveUndoState(state, kind)
    if kind == "type" and state.lastUndoKind == "type" then
        return
    end
    state.lastUndoKind = kind
    
    table.insert(state.undoStack, {
        text = state.rawText,
        cursorLine = state.cursorLine,
        cursorCol = state.cursorCol,
        anchorLine = state.anchorLine,
        anchorCol = state.anchorCol
    })
    state.redoStack = {}
    if #state.undoStack > 50 then
        table.remove(state.undoStack, 1)
    end
end

local function syncRawText(state)
    state.rawText = table.concat(state.lines, "\n")
end

local function deleteSelection(state, skipUndo)
    if not hasSelection(state) then return false end
    if not skipUndo then
        saveUndoState(state, "delete")
    end
    local startL, startC, endL, endC = getSelectionRange(state)
    
    local startLineText = state.lines[startL] or ""
    local endLineText = state.lines[endL] or ""
    
    local left = startLineText:sub(1, startC - 1)
    local right = endLineText:sub(endC)
    
    state.lines[startL] = left .. right
    
    for idx = endL, startL + 1, -1 do
        table.remove(state.lines, idx)
    end
    
    state.cursorLine = startL
    state.cursorCol = startC
    state.anchorLine = startL
    state.anchorCol = startC
    syncRawText(state)
    return true
end

local function insertText(state, text)
    text = tostring(text or "")
    saveUndoState(state, "type")
    if hasSelection(state) then
        deleteSelection(state, true)
    end
    
    local curLine = state.cursorLine
    local curCol = state.cursorCol
    local lineText = state.lines[curLine] or ""
    
    if text:find("\n") or text:find("\r") then
        local subLines = {}
        for l in string.gmatch(text .. "\n", "(.-)\r?\n") do
            table.insert(subLines, l)
        end
        if #subLines == 0 then subLines = {""} end
        
        local left = lineText:sub(1, curCol - 1)
        local right = lineText:sub(curCol)
        
        state.lines[curLine] = left .. subLines[1]
        for idx = 2, #subLines do
            table.insert(state.lines, curLine + idx - 1, subLines[idx])
        end
        
        local lastIdx = curLine + #subLines - 1
        local oldLastText = state.lines[lastIdx] or ""
        state.lines[lastIdx] = oldLastText .. right
        state.cursorLine = lastIdx
        state.cursorCol = #oldLastText + 1
    else
        local left = lineText:sub(1, curCol - 1)
        local right = lineText:sub(curCol)
        state.lines[curLine] = left .. text .. right
        state.cursorCol = curCol + #text
    end
    
    state.anchorLine = state.cursorLine
    state.anchorCol = state.cursorCol
    syncRawText(state)
end

local function utf8Align(str, col)
    local len = #str
    if col <= 1 then return 1 end
    if col > len then return len + 1 end
    
    local cleanCol = 1
    while cleanCol <= len + 1 do
        local nextOffset = utf8.offset(str, 2, cleanCol) or (len + 1)
        if nextOffset >= col then
            if math.abs(cleanCol - col) < math.abs(nextOffset - col) then
                return cleanCol
            else
                return nextOffset
            end
        end
        cleanCol = nextOffset
    end
    return col
end

local function findWordBoundaryLeft(lineText, startCol)
    if startCol <= 1 then return 1 end
    local idx = startCol - 1
    while idx > 1 and lineText:sub(idx, idx):match("%s") do
        idx = idx - 1
    end
    local isWordChar = lineText:sub(idx, idx):match("[%w_]")
    while idx > 1 do
        local prev = lineText:sub(idx - 1, idx - 1)
        if prev:match("[%w_]") ~= isWordChar then
            break
        end
        idx = idx - 1
    end
    return idx
end

local function findWordBoundaryRight(lineText, startCol)
    local len = #lineText
    if startCol > len then return len + 1 end
    local idx = startCol
    while idx <= len and lineText:sub(idx, idx):match("%s") do
        idx = idx + 1
    end
    local isWordChar = lineText:sub(idx, idx):match("[%w_]")
    while idx <= len do
        local nxt = lineText:sub(idx + 1, idx + 1)
        if nxt:match("[%w_]") ~= isWordChar then
            idx = idx + 1
            break
        end
        idx = idx + 1
    end
    return idx
end

local function cursorFromMouse(state, mx, my, extendSelection)
    if not state or not state.lines then return end
    local x = state.widgetX or 0
    local y = state.widgetY or 0
    local textX = state.textX or (x + 40)
    local lineHeight = 16
    local line = math.floor((my - (y + 4) + state.scrollY) / lineHeight) + 1
    line = math.max(1, math.min(#state.lines, line))

    local lineText = state.lines[line] or ""
    local relX = mx - textX + state.scrollX
    local font = love.graphics.getFont()
    local bestCol = 1
    local minDiff = math.abs(relX)
    for col = 2, #lineText + 1 do
        local wText = font:getWidth(lineText:sub(1, col - 1))
        local diff = math.abs(wText - relX)
        if diff < minDiff then
            minDiff = diff
            bestCol = col
        end
    end

    state.cursorLine = line
    state.cursorCol = bestCol
    if not extendSelection then
        state.anchorLine = line
        state.anchorCol = bestCol
    end
    state.cursorTimer = 0
    return line, bestCol
end

local function safeGetClipboardText()
    if not love.system or not love.system.getClipboardText then return "" end
    local ok, text = pcall(love.system.getClipboardText)
    if ok and type(text) == "string" then return text end
    return ""
end

local function safeSetClipboardText(text)
    if not love.system or not love.system.setClipboardText then return end
    pcall(love.system.setClipboardText, tostring(text or ""))
end

-- Input forwarding
function CustomUI.mousepressed(x, y, button)
    clickEvent = { x = x, y = y, button = button }
end

function CustomUI.mousemoved(x, y, dx, dy)
    if not CustomUI.focusedWidgetId then return end
    local state = CustomUI.widgetsState[CustomUI.focusedWidgetId]
    if not state or not state.lines then return end
    if state.isDragging and love.mouse.isDown(1) then
        cursorFromMouse(state, x, y, true)
    end
end

function CustomUI.mousereleased(x, y, button)
    if not CustomUI.focusedWidgetId then return end
    local state = CustomUI.widgetsState[CustomUI.focusedWidgetId]
    if not state then return end
    state.isDragging = false
end

function CustomUI.wheelmoved(x, y)
    wheelEvent = { x = x, y = y }
end

function CustomUI.textinput(text)
    if not CustomUI.focusedWidgetId then return end
    local id = CustomUI.focusedWidgetId
    local state = CustomUI.widgetsState[id]
    if not state or not state.lines then return end

    insertText(state, text)
end

function CustomUI.keypressed(key)
    if not CustomUI.focusedWidgetId then return false end
    local id = CustomUI.focusedWidgetId
    local state = CustomUI.widgetsState[id]
    if not state or not state.lines then return false end

    state.cursorTimer = 0
    state.isEditing = true

    local isShift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local isCtrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")

    local curLine = state.cursorLine
    local curCol = state.cursorCol
    local lineText = state.lines[curLine] or ""

    -- 1. Undo / Redo
    if key == "z" and isCtrl then
        if #state.undoStack > 0 then
            local last = table.remove(state.undoStack)
            table.insert(state.redoStack, {
                text = state.rawText,
                cursorLine = state.cursorLine,
                cursorCol = state.cursorCol,
                anchorLine = state.anchorLine,
                anchorCol = state.anchorCol
            })
            state.rawText = last.text
            state.lines = {}
            for l in string.gmatch(last.text .. "\n", "(.-)\r?\n") do
                table.insert(state.lines, l)
            end
            if #state.lines == 0 then state.lines = {""} end
            state.cursorLine = last.cursorLine
            state.cursorCol = last.cursorCol
            state.anchorLine = last.anchorLine
            state.anchorCol = last.anchorCol
            state.lastUndoKind = nil
        end
        return true
    elseif key == "y" and isCtrl then
        if #state.redoStack > 0 then
            local nextState = table.remove(state.redoStack)
            table.insert(state.undoStack, {
                text = state.rawText,
                cursorLine = state.cursorLine,
                cursorCol = state.cursorCol,
                anchorLine = state.anchorLine,
                anchorCol = state.anchorCol
            })
            state.rawText = nextState.text
            state.lines = {}
            for l in string.gmatch(nextState.text .. "\n", "(.-)\r?\n") do
                table.insert(state.lines, l)
            end
            if #state.lines == 0 then state.lines = {""} end
            state.cursorLine = nextState.cursorLine
            state.cursorCol = nextState.cursorCol
            state.anchorLine = nextState.anchorLine
            state.anchorCol = nextState.anchorCol
            state.lastUndoKind = nil
        end
        return true
    end

    -- Clear undo grouping on cursor move
    if key ~= "backspace" and key ~= "delete" then
        state.lastUndoKind = nil
    end

    -- 2. Clipboard controls
    if key == "c" and isCtrl then
        if hasSelection(state) then
            local text = getSelectionText(state)
            safeSetClipboardText(text)
        end
        return true
    elseif key == "x" and isCtrl then
        if hasSelection(state) then
            local text = getSelectionText(state)
            safeSetClipboardText(text)
            deleteSelection(state)
        end
        return true
    elseif key == "v" and isCtrl then
        local text = safeGetClipboardText()
        if text and text ~= "" then
            insertText(state, text)
        end
        return true
    elseif key == "a" and isCtrl then
        state.anchorLine = 1
        state.anchorCol = 1
        state.cursorLine = #state.lines
        state.cursorCol = #(state.lines[#state.lines] or "") + 1
        return true
    end

    -- 3. Backspace & Delete
    if key == "backspace" then
        if hasSelection(state) then
            deleteSelection(state)
        else
            saveUndoState(state, "delete")
            if isCtrl then
                if curCol > 1 then
                    local targetCol = findWordBoundaryLeft(lineText, curCol)
                    local left = lineText:sub(1, targetCol - 1)
                    local right = lineText:sub(curCol)
                    state.lines[curLine] = left .. right
                    state.cursorCol = targetCol
                    state.anchorCol = targetCol
                elseif curLine > 1 then
                    local prevLineText = state.lines[curLine - 1] or ""
                    local prevLen = #prevLineText
                    state.lines[curLine - 1] = prevLineText .. lineText
                    table.remove(state.lines, curLine)
                    state.cursorLine = curLine - 1
                    state.cursorCol = prevLen + 1
                    state.anchorLine = curLine - 1
                    state.anchorCol = prevLen + 1
                end
            else
                if curCol > 1 then
                    local offset = utf8.offset(lineText, -1, curCol)
                    if offset then
                        local left = lineText:sub(1, offset - 1)
                        local right = lineText:sub(curCol)
                        state.lines[curLine] = left .. right
                        state.cursorCol = offset
                        state.anchorCol = offset
                    end
                elseif curLine > 1 then
                    local prevLineText = state.lines[curLine - 1] or ""
                    local prevLen = #prevLineText
                    state.lines[curLine - 1] = prevLineText .. lineText
                    table.remove(state.lines, curLine)
                    state.cursorLine = curLine - 1
                    state.cursorCol = prevLen + 1
                    state.anchorLine = curLine - 1
                    state.anchorCol = prevLen + 1
                end
            end
        end
        syncRawText(state)
        return true
    elseif key == "delete" then
        if hasSelection(state) then
            deleteSelection(state)
        else
            saveUndoState(state, "delete")
            if isCtrl then
                if curCol <= #lineText then
                    local targetCol = findWordBoundaryRight(lineText, curCol)
                    local left = lineText:sub(1, curCol - 1)
                    local right = lineText:sub(targetCol)
                    state.lines[curLine] = left .. right
                elseif curLine < #state.lines then
                    local nextLineText = state.lines[curLine + 1] or ""
                    state.lines[curLine] = lineText .. nextLineText
                    table.remove(state.lines, curLine + 1)
                end
            else
                if curCol <= #lineText then
                    local nextOffset = utf8.offset(lineText, 2, curCol) or (#lineText + 1)
                    local left = lineText:sub(1, curCol - 1)
                    local right = lineText:sub(nextOffset)
                    state.lines[curLine] = left .. right
                elseif curLine < #state.lines then
                    local nextLineText = state.lines[curLine + 1] or ""
                    state.lines[curLine] = lineText .. nextLineText
                    table.remove(state.lines, curLine + 1)
                end
            end
        end
        syncRawText(state)
        return true
    end

    -- 4. Newline and Tabs
    if key == "return" then
        saveUndoState(state, "type")
        if hasSelection(state) then
            deleteSelection(state, true)
        end
        curLine = state.cursorLine
        curCol = state.cursorCol
        lineText = state.lines[curLine] or ""
        
        local left = lineText:sub(1, curCol - 1)
        local right = lineText:sub(curCol)
        local indent = left:match("^(%s*)") or ""
        if left:match(":%s*$") then
            indent = indent .. "    "
        end
        state.lines[curLine] = left
        table.insert(state.lines, curLine + 1, indent .. right)
        state.cursorLine = curLine + 1
        state.cursorCol = #indent + 1
        state.anchorLine = curLine + 1
        state.anchorCol = #indent + 1
        syncRawText(state)
        return true
    elseif key == "tab" and isShift then
        saveUndoState(state, "delete")
        if hasSelection(state) then
            local startL, _, endL = getSelectionRange(state)
            for idx = startL, endL do
                local textLine = state.lines[idx] or ""
                if textLine:sub(1, 4) == "    " then
                    state.lines[idx] = textLine:sub(5)
                elseif textLine:sub(1, 1) == "\t" then
                    state.lines[idx] = textLine:sub(2)
                end
            end
            syncRawText(state)
        else
            if lineText:sub(1, 4) == "    " and curCol > 4 then
                state.lines[curLine] = lineText:sub(5)
                state.cursorCol = curCol - 4
                state.anchorCol = state.cursorCol
                syncRawText(state)
            elseif lineText:sub(1, 1) == "\t" and curCol > 1 then
                state.lines[curLine] = lineText:sub(2)
                state.cursorCol = math.max(1, curCol - 1)
                state.anchorCol = state.cursorCol
                syncRawText(state)
            end
        end
        return true
    elseif key == "tab" then
        saveUndoState(state, "type")
        if hasSelection(state) then
            deleteSelection(state, true)
        end
        curLine = state.cursorLine
        curCol = state.cursorCol
        lineText = state.lines[curLine] or ""

        local left = lineText:sub(1, curCol - 1)
        local right = lineText:sub(curCol)
        state.lines[curLine] = left .. "    " .. right
        state.cursorCol = curCol + 4
        state.anchorCol = curCol + 4
        syncRawText(state)
        return true
    end

    -- 5. Cursor movement
    if key == "up" or key == "down" or key == "left" or key == "right" or key == "home" or key == "end" or key == "pageup" or key == "pagedown" then
        local targetLine = curLine
        local targetCol = curCol
        if key == "up" then
            if targetLine > 1 then
                targetLine = targetLine - 1
                local nextLen = #(state.lines[targetLine] or "")
                targetCol = math.min(targetCol, nextLen + 1)
                targetCol = utf8Align(state.lines[targetLine], targetCol)
            end
        elseif key == "down" then
            if targetLine < #state.lines then
                targetLine = targetLine + 1
                local nextLen = #(state.lines[targetLine] or "")
                targetCol = math.min(targetCol, nextLen + 1)
                targetCol = utf8Align(state.lines[targetLine], targetCol)
            end
        elseif key == "left" then
            if isCtrl then
                if targetCol > 1 then
                    targetCol = findWordBoundaryLeft(lineText, targetCol)
                elseif targetLine > 1 then
                    targetLine = targetLine - 1
                    targetCol = #(state.lines[targetLine] or "") + 1
                end
            else
                if targetCol > 1 then
                    local offset = utf8.offset(lineText, -1, targetCol)
                    if offset then targetCol = offset end
                elseif targetLine > 1 then
                    targetLine = targetLine - 1
                    targetCol = #(state.lines[targetLine] or "") + 1
                end
            end
        elseif key == "right" then
            if isCtrl then
                if targetCol <= #lineText then
                    targetCol = findWordBoundaryRight(lineText, targetCol)
                elseif targetLine < #state.lines then
                    targetLine = targetLine + 1
                    targetCol = 1
                end
            else
                if targetCol <= #lineText then
                    local offset = utf8.offset(lineText, 2, targetCol) or (#lineText + 1)
                    targetCol = offset
                elseif targetLine < #state.lines then
                    targetLine = targetLine + 1
                    targetCol = 1
                end
            end
        elseif key == "home" then
            if isCtrl then
                targetLine = 1
                targetCol = 1
            else
                targetCol = 1
            end
        elseif key == "end" then
            if isCtrl then
                targetLine = #state.lines
                targetCol = #(state.lines[targetLine] or "") + 1
            else
                targetCol = #lineText + 1
            end
        elseif key == "pageup" then
            targetLine = math.max(1, targetLine - 10)
            local nextLen = #(state.lines[targetLine] or "")
            targetCol = math.min(targetCol, nextLen + 1)
            targetCol = utf8Align(state.lines[targetLine], targetCol)
        elseif key == "pagedown" then
            targetLine = math.min(#state.lines, targetLine + 10)
            local nextLen = #(state.lines[targetLine] or "")
            targetCol = math.min(targetCol, nextLen + 1)
            targetCol = utf8Align(state.lines[targetLine], targetCol)
        end

        state.cursorLine = targetLine
        state.cursorCol = targetCol
        if not isShift then
            state.anchorLine = targetLine
            state.anchorCol = targetCol
        end
        syncRawText(state)
        return true
    end

    return false
end

-- Call at the start of frame (love.update)
function CustomUI.clearEvents(dt)
    CustomUI.drawQueue = {}

    -- Update cursor blinking timers
    for _, state in pairs(CustomUI.widgetsState) do
        if state.cursorTimer then
            state.cursorTimer = state.cursorTimer + dt
        end
    end
end

function CustomUI.flushEvents()
    clickEvent = nil
    wheelEvent = nil
end

-- Layout Helpers
local function getColumnWidth()
    return layout.colWidths[layout.currentCol] or (layout.w - 32)
end

local function advanceLayout(w, h)
    layout.prevX = layout.penX
    layout.prevY = layout.penY
    layout.prevW = w
    layout.prevH = h

    layout.penY = layout.penY + h + 8
    if layout.colMaxY then
        layout.colMaxY[layout.currentCol] = math.max(layout.colMaxY[layout.currentCol] or 0, layout.penY)
    end
end

-- Draw commands queuing
local function queueDraw(cmd)
    table.insert(CustomUI.drawQueue, cmd)
end

-- Dialog window container
function CustomUI.beginDialog(id, title, options)
    local w = math.max(1, math.floor(tonumber(options.W) or 600))
    local h = math.max(1, math.floor(tonumber(options.H) or 400))
    local x = math.floor((love.graphics.getWidth() - w) / 2)
    local y = math.floor((love.graphics.getHeight() - h) / 2)

    activeDialog = { id = id, x = x, y = y, w = w, h = h }

    -- Setup initial layout pen
    layout.startX = x + 16
    layout.startY = y + 40
    layout.w = w
    layout.h = h
    layout.penX = layout.startX
    layout.penY = layout.startY
    layout.sameLine = false
    layout.columns = 1
    layout.currentCol = 1
    layout.colStartX = { layout.startX }
    layout.colWidths = { w - 32 }
    layout.colMaxY = { layout.startY }
    layout.scrollAreaId = nil
    layout.scrollY = 0

    -- Draw dialog background and header
    queueDraw({ type = "dialog", x = x, y = y, w = w, h = h, title = title })

    return true
end

function CustomUI.endDialog()
    activeDialog = nil
end

function CustomUI.dialogCloseButton()
    if not activeDialog then return false end

    local size = 16
    local x = activeDialog.x + activeDialog.w - size - 8
    local y = activeDialog.y + 7
    local mx, my = love.mouse.getPosition()
    local hovered = mx >= x and mx <= x + size and my >= y and my <= y + size
    local active = hovered and love.mouse.isDown(1)

    local clicked = false
    if clickEvent and clickEvent.button == 1 and clickEvent.x >= x and clickEvent.x <= x + size and clickEvent.y >= y and clickEvent.y <= y + size then
        clicked = true
        clickEvent = nil
    end

    queueDraw({ type = "dialog_close", x = x, y = y, w = size, h = size, hovered = hovered, active = active })
    return clicked
end

-- Multi-column layouts
function CustomUI.beginLayout(id, options)
    layout.columns = options.Columns or 1
    layout.currentCol = 1
    layout.startY = layout.penY

    local availW = layout.w - 32
    layout.colStartX = {}
    layout.colWidths = {}
    layout.colMaxY = {}

    if options.widths then
        local curX = layout.startX
        for i = 1, layout.columns do
            layout.colStartX[i] = curX
            layout.colWidths[i] = options.widths[i] or (availW / layout.columns)
            layout.colMaxY[i] = layout.startY
            curX = curX + layout.colWidths[i] + 16
        end
    else
        -- Divide evenly
        local colW = (availW - (layout.columns - 1) * 16) / layout.columns
        for i = 1, layout.columns do
            layout.colStartX[i] = layout.startX + (i - 1) * (colW + 16)
            layout.colWidths[i] = colW
            layout.colMaxY[i] = layout.startY
        end
    end

    layout.penX = layout.colStartX[1]
    layout.penY = layout.startY

    return true
end

function CustomUI.setLayoutColumn(col)
    layout.currentCol = col
    layout.penX = layout.colStartX[col]
    layout.penY = layout.startY
end

function CustomUI.endLayout()
    -- Advance layout penY to the maximum height reached by any column
    local maxY = layout.startY
    for i = 1, layout.columns do
        maxY = math.max(maxY, layout.colMaxY[i] or layout.startY)
    end
    
    -- Reset to single column
    layout.columns = 1
    layout.currentCol = 1
    layout.colStartX = { layout.startX }
    layout.colWidths = { layout.w - 32 }
    layout.colMaxY = { maxY }
    layout.penX = layout.startX
    layout.penY = maxY
end

-- Force next widget onto the same horizontal line
function CustomUI.sameLine()
    layout.sameLine = true
end

-- Separator line
function CustomUI.separator()
    local x = layout.penX
    local y = layout.penY + 4
    local drawY = y
    if layout.scrollAreaId then
        drawY = y - layout.scrollY
    end
    local textX = x + 40
    local w = getColumnWidth()
    queueDraw({ type = "separator", x = x, y = drawY, w = w })
    layout.penY = layout.penY + 12
end

-- Text labels with wrapping
function CustomUI.text(str, options)
    options = options or {}
    local x = math.floor(tonumber(layout.penX) or 0)
    if layout.sameLine then
        x = math.floor((tonumber(layout.prevX) or 0) + (tonumber(layout.prevW) or 0) + 8)
        layout.penY = layout.prevY
        layout.sameLine = false
    end
    local w = math.max(1, math.floor(tonumber(options.W or getColumnWidth()) or 1))
    local font = love.graphics.getFont()
    local _, lines = font:getWrap(tostring(str or ""), w)
    local h = #lines * 16

    local drawY = math.floor(tonumber(layout.penY) or 0)
    if layout.scrollAreaId then
        drawY = layout.penY - layout.scrollY
    end

    queueDraw({ type = "text", x = x, y = drawY, text = tostring(str or ""), w = w, color = options.Color or CustomUI.style.text })
    advanceLayout(w, h)
end

-- Buttons
function CustomUI.button(id, label, options)
    options = options or {}
    local w = math.max(1, math.floor(tonumber(options.W) or 80))
    local h = math.max(1, math.floor(tonumber(options.H) or 24))

    local x = layout.penX
    local y = layout.penY
    if layout.sameLine then
        x = layout.prevX + layout.prevW + 8
        y = layout.prevY
        layout.sameLine = false
    end

    local drawY = y
    if layout.scrollAreaId then
        drawY = y - layout.scrollY
    end

    local mx, my = love.mouse.getPosition()
    local insideScrollArea = true
    if layout.scrollAreaId then
        insideScrollArea = (my >= layout.scrollAreaY and my <= layout.scrollAreaY + layout.scrollAreaH)
    end
    local hovered = insideScrollArea and (mx >= x and mx <= x + w and my >= drawY and my <= drawY + h)
    local active = hovered and love.mouse.isDown(1)

    local clicked = false
    if clickEvent and clickEvent.button == 1 then
        local clickInsideScroll = true
        if layout.scrollAreaId then
            clickInsideScroll = (clickEvent.y >= layout.scrollAreaY and clickEvent.y <= layout.scrollAreaY + layout.scrollAreaH)
        end
        if clickInsideScroll and clickEvent.x >= x and clickEvent.x <= x + w and clickEvent.y >= drawY and clickEvent.y <= drawY + h then
            clicked = true
            clickEvent = nil -- Consume click
        end
    end

    queueDraw({ type = "button", x = x, y = drawY, w = w, h = h, label = tostring(label or ""), hovered = hovered, active = active })
    advanceLayout(w, h)

    return clicked
end

-- Image display widget
function CustomUI.image(id, canvas, w, h)
    local x = layout.penX
    local y = layout.penY
    if layout.sameLine then
        x = layout.prevX + layout.prevW + 8
        y = layout.prevY
        layout.sameLine = false
    end

    local drawY = y
    if layout.scrollAreaId then
        drawY = y - layout.scrollY
    end

    queueDraw({ type = "image", x = x, y = drawY, w = w, h = h, image = canvas })
    advanceLayout(w, h)
end

-- Quad Image display widget (scaled)
function CustomUI.quadImage(id, image, quad, w, h)
    local x = layout.penX
    local y = layout.penY
    if layout.sameLine then
        x = layout.prevX + layout.prevW + 8
        y = layout.prevY
        layout.sameLine = false
    end

    local drawY = y
    if layout.scrollAreaId then
        drawY = y - layout.scrollY
    end

    queueDraw({ type = "quad_image", x = x, y = drawY, w = w, h = h, image = image, quad = quad })
    advanceLayout(w, h)
end

-- Scrollable Area Container
function CustomUI.beginScrollArea(id, options)
    local w = options.W or getColumnWidth()
    local h = options.H or 200

    local x = layout.penX
    local y = layout.penY
    if layout.sameLine then
        x = layout.prevX + layout.prevW + 8
        y = layout.prevY
        layout.sameLine = false
    end

    local state = CustomUI.widgetsState[id]
    if not state then
        state = { scrollY = 0, totalHeight = 0 }
        CustomUI.widgetsState[id] = state
    end

    local mx, my = love.mouse.getPosition()
    if wheelEvent and mx >= x and mx <= x + w and my >= y and my <= y + h then
        state.scrollY = state.scrollY - wheelEvent.y * 30
        wheelEvent = nil
    end

    -- Save parent scroll states
    layout.scrollAreaId = id
    layout.scrollAreaX = x
    layout.scrollAreaY = y
    layout.scrollAreaW = w
    layout.scrollAreaH = h
    layout.parentScrollY = layout.scrollY
    layout.scrollY = state.scrollY

    queueDraw({ type = "listbox_bg", x = x, y = y, w = w, h = h })
    queueDraw({ type = "push_scissor", x = x + 1, y = y + 1, w = w - 2, h = h - 2 })

    layout.scrollAreaStartY = y
    layout.penX = x + 8
    layout.penY = y + 8

    return true
end

function CustomUI.endScrollArea()
    local id = layout.scrollAreaId
    local state = CustomUI.widgetsState[id]

    local contentH = layout.penY - (layout.scrollAreaY + 8)
    state.totalHeight = contentH

    local maxScroll = math.max(0, contentH - layout.scrollAreaH + 16)
    state.scrollY = math.max(0, math.min(maxScroll, state.scrollY))

    queueDraw({ type = "pop_scissor" })

    if contentH > layout.scrollAreaH then
        local sbH = math.max(10, (layout.scrollAreaH / contentH) * layout.scrollAreaH)
        local sbY = layout.scrollAreaY + (state.scrollY / contentH) * layout.scrollAreaH
        queueDraw({ type = "scrollbar", x = layout.scrollAreaX + layout.scrollAreaW - 6, y = sbY, w = 4, h = sbH })
    end

    layout.scrollY = layout.parentScrollY or 0
    layout.scrollAreaId = nil
    
    layout.penX = layout.scrollAreaX
    layout.penY = layout.scrollAreaY + layout.scrollAreaH + 8
end

-- Premium Grid Cell Card widget for build structures
function CustomUI.gridItem(id, image, quad, label, costLabel, selected, w, h)
    local x = layout.penX
    local y = layout.penY
    if layout.sameLine then
        x = layout.prevX + layout.prevW + 8
        y = layout.prevY
        layout.sameLine = false
    end

    local drawY = y
    if layout.scrollAreaId then
        drawY = y - layout.scrollY
    end

    local mx, my = love.mouse.getPosition()
    local insideScrollArea = true
    if layout.scrollAreaId then
        insideScrollArea = (my >= layout.scrollAreaY and my <= layout.scrollAreaY + layout.scrollAreaH)
    end
    local hovered = insideScrollArea and (mx >= x and mx <= x + w and my >= drawY and my <= drawY + h)
    local active = hovered and love.mouse.isDown(1)

    local clicked = false
    if clickEvent and clickEvent.button == 1 then
        local clickInsideScroll = true
        if layout.scrollAreaId then
            clickInsideScroll = (clickEvent.y >= layout.scrollAreaY and clickEvent.y <= layout.scrollAreaY + layout.scrollAreaH)
        end
        if clickInsideScroll and clickEvent.x >= x and clickEvent.x <= x + w and clickEvent.y >= drawY and clickEvent.y <= drawY + h then
            clicked = true
            clickEvent = nil -- Consume
        end
    end

    queueDraw({
        type = "grid_item",
        x = x,
        y = drawY,
        w = w,
        h = h,
        image = image,
        quad = quad,
        label = label,
        costLabel = costLabel,
        selected = selected,
        hovered = hovered,
        active = active
    })

    advanceLayout(w, h)
    return clicked
end

-- Scrollable listbox widget (original)
function CustomUI.beginListBox(id, options)
    local w = options.W or getColumnWidth()
    local h = options.H or 150

    local x = layout.penX
    local y = layout.penY
    if layout.sameLine then
        x = layout.prevX + layout.prevW + 8
        y = layout.prevY
        layout.sameLine = false
    end

    local state = CustomUI.widgetsState[id]
    if not state then
        state = { scrollY = 0 }
        CustomUI.widgetsState[id] = state
    end

    local mx, my = love.mouse.getPosition()
    if wheelEvent and mx >= x and mx <= x + w and my >= y and my <= y + h then
        state.scrollY = state.scrollY - wheelEvent.y * 20
        wheelEvent = nil
    end

    layout.listBoxId = id
    layout.listBoxX = x
    layout.listBoxY = y
    layout.listBoxW = w
    layout.listBoxH = h
    layout.listBoxItemIndex = 0

    queueDraw({ type = "listbox_bg", x = x, y = y, w = w, h = h })
    queueDraw({ type = "push_scissor", x = x + 1, y = y + 1, w = w - 2, h = h - 2 })

    return true
end

function CustomUI.listBoxItem(id, label, selected)
    local parentId = layout.listBoxId
    local state = CustomUI.widgetsState[parentId]
    
    local idx = layout.listBoxItemIndex
    layout.listBoxItemIndex = layout.listBoxItemIndex + 1

    local x = layout.listBoxX
    local y = layout.listBoxY + idx * 20 - state.scrollY
    local w = layout.listBoxW

    local mx, my = love.mouse.getPosition()
    local hovered = false
    if mx >= x and mx <= x + w and my >= layout.listBoxY and my <= layout.listBoxY + layout.listBoxH then
        if my >= y and my <= y + 20 then
            hovered = true
        end
    end

    local clicked = false
    if clickEvent and clickEvent.button == 1 then
        if clickEvent.x >= x and clickEvent.x <= x + w and clickEvent.y >= layout.listBoxY and clickEvent.y <= layout.listBoxY + layout.listBoxH then
            if clickEvent.y >= y and clickEvent.y <= y + 20 then
                clicked = true
                clickEvent = nil -- Consume
            end
        end
    end

    queueDraw({ type = "listbox_item", x = x, y = y, w = w, label = label, selected = selected, hovered = hovered })

    return clicked
end

function CustomUI.endListBox()
    local parentId = layout.listBoxId
    local state = CustomUI.widgetsState[parentId]
    local totalItemsH = layout.listBoxItemIndex * 20
    local maxScroll = math.max(0, totalItemsH - layout.listBoxH)
    state.scrollY = math.max(0, math.min(maxScroll, state.scrollY))

    queueDraw({ type = "pop_scissor" })

    if totalItemsH > layout.listBoxH then
        local sbH = math.max(10, (layout.listBoxH / totalItemsH) * layout.listBoxH)
        local sbY = layout.listBoxY + (state.scrollY / totalItemsH) * layout.listBoxH
        queueDraw({ type = "scrollbar", x = layout.listBoxX + layout.listBoxW - 6, y = sbY, w = 4, h = sbH })
    end

    advanceLayout(layout.listBoxW, layout.listBoxH)
    layout.listBoxId = nil
end

-- Premium Code Editor Widget with Syntax Highlighting and line numbering
function CustomUI.editor(id, text, w, h, runningLine)
    w = math.max(1, math.floor(tonumber(w) or 1))
    h = math.max(1, math.floor(tonumber(h) or 1))
    local x = layout.penX
    local y = layout.penY
    if layout.sameLine then
        x = layout.prevX + layout.prevW + 8
        y = layout.prevY
        layout.sameLine = false
    end

    local drawY = y
    if layout.scrollAreaId then
        drawY = y - layout.scrollY
    end

    -- Scroll & caret state
    local state = CustomUI.widgetsState[id]
    if not state or (state.rawText ~= text and not state.isEditing) then
        state = {
            rawText = text,
            lines = {},
            cursorLine = 1,
            cursorCol = 1,
            anchorLine = 1,
            anchorCol = 1,
            scrollY = 0,
            scrollX = 0,
            cursorTimer = 0,
            isEditing = false,
            undoStack = {},
            redoStack = {},
            lastUndoKind = nil,
        }
        for l in string.gmatch(text .. "\n", "(.-)\r?\n") do
            table.insert(state.lines, l)
        end
        if #state.lines == 0 then state.lines = {""} end
        CustomUI.widgetsState[id] = state
    end
    state.widgetX = x
    state.widgetY = drawY
    state.textX = x + 40

    -- Focus check
    local mx, my = love.mouse.getPosition()
    local insideScrollArea = true
    if layout.scrollAreaId then
        insideScrollArea = (my >= layout.scrollAreaY and my <= layout.scrollAreaY + layout.scrollAreaH)
    end
    local inside = insideScrollArea and (mx >= x and mx <= x + w and my >= drawY and my <= drawY + h)

    -- Mouse click cursor positioning
    if clickEvent and clickEvent.button == 1 then
        local clickInsideScroll = true
        if layout.scrollAreaId then
            clickInsideScroll = (clickEvent.y >= layout.scrollAreaY and clickEvent.y <= layout.scrollAreaY + layout.scrollAreaH)
        end
        if clickInsideScroll and clickEvent.x >= x + 36 and clickEvent.x <= x + w and clickEvent.y >= drawY and clickEvent.y <= drawY + h then
            CustomUI.focusedWidgetId = id
            local extendSelection = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
            cursorFromMouse(state, clickEvent.x, clickEvent.y, extendSelection)
            state.cursorTimer = 0
            state.isDragging = true
            clickEvent = nil -- Consume
        elseif inside then
            CustomUI.focusedWidgetId = id
            clickEvent = nil -- Focus but don't reposition cursor
        end
    end

    -- Drag to select text
    if love.mouse.isDown(1) and CustomUI.focusedWidgetId == id and state.isDragging then
        cursorFromMouse(state, mx, my, true)
    else
        state.isDragging = false
    end

    -- Mouse wheel scrolling
    if wheelEvent and inside then
        state.scrollY = state.scrollY - wheelEvent.y * 32
        wheelEvent = nil
    end

    -- Clamp scrollY
    local maxScroll = math.max(0, #state.lines * 16 - h + 16)
    state.scrollY = math.max(0, math.min(maxScroll, state.scrollY))

    -- Keep cursor in view vertically
    local visibleLines = math.floor((h - 8) / 16)
    if state.cursorLine - 1 < math.floor(state.scrollY / 16) then
        state.scrollY = (state.cursorLine - 1) * 16
    elseif state.cursorLine > math.floor((state.scrollY + h - 16) / 16) then
        state.scrollY = state.cursorLine * 16 - h + 16
    end

    -- Keep cursor in view horizontally (approximate)
    local font = love.graphics.getFont()
    local currentLineText = state.lines[state.cursorLine] or ""
    local cursorX = font:getWidth(currentLineText:sub(1, state.cursorCol - 1))
    local viewW = w - 44
    if cursorX < state.scrollX then
        state.scrollX = cursorX
    elseif cursorX > state.scrollX + viewW then
        state.scrollX = cursorX - viewW
    end

    -- Queue drawing
    queueDraw({
        type = "editor",
        id = id,
        x = x,
        y = drawY,
        w = w,
        h = h,
        lines = state.lines,
        cursorLine = state.cursorLine,
        cursorCol = state.cursorCol,
        anchorLine = state.anchorLine,
        anchorCol = state.anchorCol,
        scrollY = state.scrollY,
        scrollX = state.scrollX,
        cursorTimer = state.cursorTimer,
        focused = (CustomUI.focusedWidgetId == id),
        runningLine = runningLine,
    })

    advanceLayout(w, h)

    state.isEditing = false -- reset state editing for next frame
    return state.rawText
end

-- RENDER PIPELINE: Execute the queued draw commands
function CustomUI.draw()
    local font = love.graphics.getFont()
    local function safe(v, fallback)
        v = tonumber(v)
        if v == nil then return fallback or 0 end
        return v
    end

    for _, cmd in ipairs(CustomUI.drawQueue) do
        if cmd.type == "dialog" then
            local x, y, w, h = safe(cmd.x), safe(cmd.y), safe(cmd.w, 1), safe(cmd.h, 1)
            -- Drop shadow
            love.graphics.setColor(0, 0, 0, 0.4)
            love.graphics.rectangle("fill", math.floor(x + 3), math.floor(y + 3), math.floor(w), math.floor(h), 2, 2)

            -- Window body
            love.graphics.setColor(CustomUI.style.bg)
            love.graphics.rectangle("fill", math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5), 2, 2)

            -- Header border & background
            love.graphics.setColor(CustomUI.style.headerBg)
            love.graphics.rectangle("fill", math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), 30, 2, 2)
            love.graphics.rectangle("fill", math.floor(x + 0.5), math.floor(y + 20.5), math.floor(w + 0.5), 10)

            -- Outer border
            love.graphics.setColor(CustomUI.style.border)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5), 2, 2)
            love.graphics.line(x, y + 30, x + w, y + 30)

            -- Header title
            love.graphics.setColor(CustomUI.style.text)
            love.graphics.print(cmd.title, math.floor(x + 12), math.floor(y + 7))

        elseif cmd.type == "text" then
            local x, y, w = safe(cmd.x), safe(cmd.y), math.max(1, safe(cmd.w, 1))
            love.graphics.setColor(cmd.color)
            love.graphics.printf(tostring(cmd.text or ""), x, y, w, "left")

        elseif cmd.type == "dialog_close" then
            local x, y, w, h = safe(cmd.x), safe(cmd.y), safe(cmd.w, 1), safe(cmd.h, 1)
            if cmd.active then
                love.graphics.setColor(CustomUI.style.accentActive)
            elseif cmd.hovered then
                love.graphics.setColor(CustomUI.style.accentHover)
            else
                love.graphics.setColor(CustomUI.style.widgetBg)
            end
            love.graphics.rectangle("fill", x, y, w, h, 1, 1)
            love.graphics.setColor(CustomUI.style.border)
            love.graphics.rectangle("line", x, y, w, h, 1, 1)
            love.graphics.setColor(CustomUI.style.text)
            love.graphics.line(x + 4, y + 4, x + w - 4, y + h - 4)
            love.graphics.line(x + w - 4, y + 4, x + 4, y + h - 4)

        elseif cmd.type == "separator" then
            local x, y, w = safe(cmd.x), safe(cmd.y), safe(cmd.w, 1)
            love.graphics.setColor(CustomUI.style.separator)
            love.graphics.line(x, y, x + w, y)

        elseif cmd.type == "button" then
            local x, y, w, h = safe(cmd.x), safe(cmd.y), safe(cmd.w, 1), safe(cmd.h, 1)
            if cmd.active then
                love.graphics.setColor(CustomUI.style.accentActive)
            elseif cmd.hovered then
                love.graphics.setColor(CustomUI.style.accentHover)
            else
                love.graphics.setColor(CustomUI.style.accent)
            end

            local bx = math.floor(x + 0.5)
            local by = math.floor(y + 0.5)
            local bw = math.floor(w + 0.5)
            local bh = math.floor(h + 0.5)
            love.graphics.rectangle("fill", bx, by, bw, bh, 1, 1)
            love.graphics.setColor(1, 1, 1, 0.08)
            love.graphics.rectangle("fill", bx + 1, by + 1, math.max(0, bw - 2), 2)

            love.graphics.setColor(CustomUI.style.border)
            love.graphics.rectangle("line", bx, by, bw, bh, 1, 1)

            love.graphics.setColor(1, 1, 1, 1)
            local txtW = font:getWidth(cmd.label)
            love.graphics.print(cmd.label, math.floor(bx + (bw - txtW) * 0.5 + 0.5), math.floor(by + (bh - font:getHeight()) * 0.5 + 0.5))

        elseif cmd.type == "image" then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(cmd.image, safe(cmd.x), safe(cmd.y))

        elseif cmd.type == "quad_image" then
            if cmd.image and cmd.quad then
                love.graphics.setColor(1, 1, 1, 1)
                local qx, qy, qw, qh = cmd.quad:getViewport()
                local scale = math.min(safe(cmd.w, 1) / qw, safe(cmd.h, 1) / qh)
                love.graphics.draw(
                    cmd.image,
                    cmd.quad,
                    safe(cmd.x) + (safe(cmd.w, 1) - qw * scale) * 0.5,
                    safe(cmd.y) + (safe(cmd.h, 1) - qh * scale) * 0.5,
                    0, scale, scale
                )
            end

        elseif cmd.type == "grid_item" then
            local x, y, w, h = safe(cmd.x), safe(cmd.y), safe(cmd.w, 1), safe(cmd.h, 1)
            -- Card background and outline
            if cmd.selected then
                love.graphics.setColor(CustomUI.style.accent)
                love.graphics.rectangle("fill", x, y, w, h, 2, 2)
                love.graphics.setColor(CustomUI.style.widgetBg)
                love.graphics.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 1, 1)
            else
                if cmd.hovered then
                    love.graphics.setColor(CustomUI.style.itemHover)
                else
                    love.graphics.setColor(CustomUI.style.widgetBg)
                end
                love.graphics.rectangle("fill", x, y, w, h, 2, 2)
                
                love.graphics.setColor(CustomUI.style.border)
                love.graphics.rectangle("line", x, y, w, h, 2, 2)
            end

            -- Center and draw the quad image in the upper area (top 58% of the card)
            if cmd.image and cmd.quad then
                local imgH = h * 0.58
                local qx, qy, qw, qh = cmd.quad:getViewport()
                local scale = math.min((w - 12) / qw, imgH / qh)
                
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(
                    cmd.image,
                    cmd.quad,
                    x + (w - qw * scale) * 0.5,
                    y + 6 + (imgH - qh * scale) * 0.5,
                    0, scale, scale
                )
            end

            -- Draw labels in the lower area
            local textY = y + h * 0.64
            
            -- Title/Name
            love.graphics.setColor(CustomUI.style.text)
            local shortLabel = cmd.label
            if font:getWidth(shortLabel) > w - 8 then
                while #shortLabel > 3 and font:getWidth(shortLabel .. "...") > w - 8 do
                    shortLabel = shortLabel:sub(1, #shortLabel - 1)
                end
                shortLabel = shortLabel .. "..."
            end
            love.graphics.printf(shortLabel, x + 4, textY, w - 8, "center")

            -- Cost label
            if cmd.costLabel then
                love.graphics.setColor(CustomUI.style.textDim)
                love.graphics.printf(cmd.costLabel, x + 4, textY + 16, w - 8, "center")
            end

        elseif cmd.type == "listbox_bg" then
            local x, y, w, h = safe(cmd.x), safe(cmd.y), safe(cmd.w, 1), safe(cmd.h, 1)
            love.graphics.setColor(CustomUI.style.widgetBg)
            love.graphics.rectangle("fill", x, y, w, h, 2, 2)
            love.graphics.setColor(CustomUI.style.border)
            love.graphics.rectangle("line", x, y, w, h, 2, 2)

        elseif cmd.type == "listbox_item" then
            local x, y, w = safe(cmd.x), safe(cmd.y), safe(cmd.w, 1)
            if cmd.selected then
                love.graphics.setColor(CustomUI.style.itemSelect)
                love.graphics.rectangle("fill", x + 2, y, w - 4, 20, 1, 1)
            elseif cmd.hovered then
                love.graphics.setColor(CustomUI.style.itemHover)
                love.graphics.rectangle("fill", x + 2, y, w - 4, 20, 1, 1)
            end

            love.graphics.setColor(CustomUI.style.text)
            love.graphics.print(cmd.label, x + 8, y + 3)

        elseif cmd.type == "scrollbar" then
            love.graphics.setColor(0.3, 0.3, 0.35, 0.7)
            love.graphics.rectangle("fill", safe(cmd.x), safe(cmd.y), safe(cmd.w, 1), safe(cmd.h, 1), 2, 2)

        elseif cmd.type == "push_scissor" then
            love.graphics.push("all")
            love.graphics.intersectScissor(safe(cmd.x), safe(cmd.y), safe(cmd.w, 1), safe(cmd.h, 1))

        elseif cmd.type == "pop_scissor" then
            love.graphics.pop()

        elseif cmd.type == "editor" then
            local x, y, w, h = safe(cmd.x), safe(cmd.y), safe(cmd.w, 1), safe(cmd.h, 1)
            -- Editor background box
            love.graphics.setColor(CustomUI.style.widgetBg)
            love.graphics.rectangle("fill", x, y, w, h, 2, 2)
            
            if cmd.focused then
                love.graphics.setColor(CustomUI.style.accent)
            else
                love.graphics.setColor(CustomUI.style.border)
            end
            love.graphics.rectangle("line", x, y, w, h, 2, 2)

            -- Line number sidebar background
            love.graphics.setColor(0.08, 0.08, 0.09, 1)
            love.graphics.rectangle("fill", x + 1, y + 1, 35, h - 2, 2, 2)
            love.graphics.rectangle("fill", x + 10, y + 1, 26, h - 2) -- square corners
            love.graphics.setColor(CustomUI.style.border)
            love.graphics.line(x + 36, y + 1, x + 36, y + h - 2)

            love.graphics.push("all")
            love.graphics.intersectScissor(x + 37, y + 1, w - 38, h - 2)

            local visibleLines = math.floor((h - 8) / 16)
            local startLine = math.max(1, math.floor(cmd.scrollY / 16))
            local endLine = math.min(#cmd.lines, math.floor((cmd.scrollY + h) / 16) + 1)

            local hasSel = (cmd.anchorLine ~= cmd.cursorLine or cmd.anchorCol ~= cmd.cursorCol)
            local startL, startC, endL, endC
            if hasSel then
                if cmd.anchorLine < cmd.cursorLine then
                    startL, startC, endL, endC = cmd.anchorLine, cmd.anchorCol, cmd.cursorLine, cmd.cursorCol
                elseif cmd.anchorLine > cmd.cursorLine then
                    startL, startC, endL, endC = cmd.cursorLine, cmd.cursorCol, cmd.anchorLine, cmd.anchorCol
                else
                    if cmd.anchorCol < cmd.cursorCol then
                        startL, startC, endL, endC = cmd.anchorLine, cmd.anchorCol, cmd.cursorLine, cmd.cursorCol
                    else
                        startL, startC, endL, endC = cmd.cursorLine, cmd.cursorCol, cmd.anchorLine, cmd.anchorCol
                    end
                end
            end

            for idx = startLine, endLine do
                local lineY = y + 4 + (idx - 1) * 16 - cmd.scrollY

                -- 1. Draw running line highlight background
                if idx == cmd.runningLine then
                    love.graphics.setColor(CustomUI.style.lineRunning)
                    love.graphics.rectangle("fill", x + 37, lineY, w - 38, 16)
                end

                -- 2. Draw selection highlight background
                if hasSel and idx >= startL and idx <= endL then
                    local lineText = cmd.lines[idx] or ""
                    local c1 = (idx == startL) and startC or 1
                    local c2 = (idx == endL) and endC or (#lineText + 1)
                    local x1 = font:getWidth(lineText:sub(1, c1 - 1))
                    local x2 = font:getWidth(lineText:sub(1, c2 - 1))
                    if idx < endL then
                        x2 = x2 + 8 -- extend for newline
                    end
                    love.graphics.setColor(0.18, 0.38, 0.65, 0.45)
                    love.graphics.rectangle("fill", x + 40 + x1 - cmd.scrollX, lineY, x2 - x1, 16)
                end

                -- 3. Draw syntax highlighted text
                local tokens = LuaHighlighter.highlightLine(cmd.lines[idx] or "")
                local curX = x + 40 - cmd.scrollX

                for _, token in ipairs(tokens) do
                    local str, tokenType = token[1], token[2]
                    local color = LuaHighlighter.colors[tokenType] or LuaHighlighter.colors.normal
                    
                    love.graphics.setColor(color)
                    love.graphics.print(str, curX, lineY)
                    curX = curX + font:getWidth(str)
                end

                -- 4. Draw blinking cursor
                if cmd.focused and idx == cmd.cursorLine and (cmd.cursorTimer % 1.0 < 0.5) then
                    local cursorOffset = font:getWidth((cmd.lines[idx] or ""):sub(1, cmd.cursorCol - 1))
                    love.graphics.setColor(CustomUI.style.accent)
                    love.graphics.line(x + 40 + cursorOffset - cmd.scrollX, lineY + 1, x + 40 + cursorOffset - cmd.scrollX, lineY + 15)
                end
            end

            love.graphics.pop() -- pop scissor

            love.graphics.push("all")
            love.graphics.intersectScissor(x + 1, y + 1, 35, h - 2)
            
            for idx = startLine, endLine do
                local lineY = y + 4 + (idx - 1) * 16 - cmd.scrollY
                love.graphics.setColor(CustomUI.style.textDim)
                love.graphics.printf(tostring(idx), x, lineY, 32, "right")
            end
            love.graphics.pop()

            local totalLinesH = #cmd.lines * 16
            if totalLinesH > h then
                local sbH = math.max(10, (h / totalLinesH) * h)
                local sbY = y + (cmd.scrollY / totalLinesH) * h
                love.graphics.setColor(0.3, 0.3, 0.35, 0.7)
                love.graphics.rectangle("fill", x + w - 6, sbY, 4, sbH, 1, 1)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return CustomUI
