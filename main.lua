-- main.lua — Cropbots entry (title screen → game).

-- Preload bit shim for environments without LuaJIT (like love.js)
local has_bit = pcall(require, "bit")
if not has_bit then
	package.preload['bit'] = function() return require("vendor.bit") end
end

local has_ffi = pcall(require, "ffi")
if not has_ffi then
	package.preload['ffi'] = function() return require("vendor.ffi") end
end

require("src.Gfx") -- package.path for Khoron before UI modules load
local Gfx = require("src.Gfx")
local TitleScreen = require("src.TitleScreen")
local SceneManager = require("src.SceneManager")
local CustomUI = require("src.ui.CustomUI")

local appState = "title"
local titleScreen
local scene

function love.load()
	Gfx.init()
	love.graphics.setLineStyle("rough")

	titleScreen = TitleScreen.new()
	scene = SceneManager.new()
end

function love.update(dt)
	CustomUI.clearEvents(dt)

	if appState == "title" then
		titleScreen:update(dt)
		if titleScreen:shouldStart() then
			appState = "game"
			scene:load()
		end
		CustomUI.flushEvents()
		return
	end

	scene:update(dt)
	CustomUI.flushEvents()
end

function love.draw()
	if appState == "title" then
		titleScreen:draw()
		return
	end
	scene:draw()
	CustomUI.draw()
	scene:drawPostUI()
end

function love.keypressed(key)
	if appState == "title" then
		if key == "return" or key == "space" then
			appState = "game"
			scene:load()
		end
		return
	end
	scene:keypressed(key)
end

function love.keyreleased(key)
	if appState ~= "game" then
		return
	end
	scene:keyreleased(key)
end

function love.textinput(text)
	CustomUI.textinput(text)
end

function love.mousepressed(x, y, button)
	CustomUI.mousepressed(x, y, button)

	if appState == "title" then
		if button == 1 then
			appState = "game"
			scene:load()
		end
		return
	end
	scene:mousepressed(x, y, button)
end

function love.mousemoved(x, y, dx, dy)
	local CustomUI = require("src.ui.CustomUI")
	CustomUI.mousemoved(x, y, dx, dy)
end

function love.mousereleased(x, y, button)
	local CustomUI = require("src.ui.CustomUI")
	CustomUI.mousereleased(x, y, button)
end

function love.wheelmoved(x, y)
	CustomUI.wheelmoved(x, y)

	if appState ~= "game" or not scene or not scene.player then
		return
	end
	if scene.notebook and scene.notebook:capturesInput() then
		return
	end
	local inv = scene.player:getInventory()
	if inv and inv:isWheelOpen() then
		local mx, my = love.mouse.getPosition()
		if inv:handleWheel(mx, my, y) then
			return
		end
	end
	if inv and not scene.lootUI:isOpen() then
		if y > 0 then
			inv:cycleSelection(-1)
		elseif y < 0 then
			inv:cycleSelection(1)
		end
	end
end

function love.resize(w, h)
	if scene and scene.camera then
		scene.camera:setSize(w, h)
	end
end
