-- main.lua — Cropbots entry (title screen → game).

-- Preload bit shim for environments without LuaJIT (like love.js)
package.preload['bit'] = function() return require("vendor.bit") end
package.preload['ffi'] = function() return require("vendor.ffi") end

require("src.Gfx") -- package.path for Khoron before UI modules load
local Gfx = require("src.Gfx")
local Slab = require("vendor.slab")
local TitleScreen = require("src.TitleScreen")
local SceneManager = require("src.SceneManager")

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
	Slab.Update(dt)

	if appState == "title" then
		titleScreen:update(dt)
		if titleScreen:shouldStart() then
			appState = "game"
			scene:load()
		end
		return
	end

	scene:update(dt)
end

function love.draw()
	if appState == "title" then
		titleScreen:draw()
		return
	end
	scene:draw()
	Slab.Draw()
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

function love.textinput(text) end

function love.mousepressed(x, y, button)
	if appState == "title" then
		if button == 1 then
			appState = "game"
			scene:load()
		end
		return
	end
	scene:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button) end

function love.mousemoved(x, y, dx, dy) end

function love.wheelmoved(x, y)
	if appState ~= "game" or not scene or not scene.player then
		return
	end
	local inv = scene.player:getInventory()
	if inv and (inv:isWheelOpen() or not scene.lootUI:isOpen()) then
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
