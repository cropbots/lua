--[[

MIT License

Copyright (c) 2019-2021 Love2D Community <love2d.org>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]]

-- Global path used in all modules in this library
SLAB_PATH = ...
if SLAB_PATH then
	SLAB_PATH = SLAB_PATH:gsub("%.init$", "")
end

-- Preload bit/ffi shims if not present
local has_bit = pcall(require, "bit")
if not has_bit then
	package.preload['bit'] = function() return require("vendor.bit") end
end

local has_ffi = pcall(require, "ffi")
if not has_ffi then
	package.preload['ffi'] = function() return require("vendor.ffi") end
end

---@type Slab
local Slab = require(SLAB_PATH .. '.API')

---@type Slab
return Slab
