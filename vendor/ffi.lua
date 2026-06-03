--- Minimal FFI shim for environments without LuaJIT FFI (like love.js)
local ffi = {
    os = "Web",
    arch = "wasm",
    C = {},
}

function ffi.cdef() end
function ffi.load() return {} end
function ffi.typeof() end
function ffi.new() end
function ffi.cast() end
function ffi.metatype() end
function ffi.gc() end
function ffi.sizeof() return 0 end
function ffi.alignof() return 0 end
function ffi.istype() return false end
function ffi.errno() return 0 end
function ffi.string(ptr, len) return "" end
function ffi.copy() end
function ffi.fill() end

return ffi
