--- Pure Lua bitop shim for environments without LuaJIT/bitop (like love.js)
local bit = {}

local MOD = 4294967296

function bit.bnot(n)
    return (MOD - 1) - (n % MOD)
end

function bit.band(a, b)
    a, b = (a or 0) % MOD, (b or 0) % MOD
    local r = 0
    local f = 1
    for i = 0, 31 do
        if a % 2 == 1 and b % 2 == 1 then r = r + f end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        f = f * 2
        if a == 0 or b == 0 then break end
    end
    return r
end

function bit.bor(a, b)
    a, b = (a or 0) % MOD, (b or 0) % MOD
    local r = 0
    local f = 1
    for i = 0, 31 do
        if a % 2 == 1 or b % 2 == 1 then r = r + f end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        f = f * 2
        if a == 0 and b == 0 then break end
    end
    return r
end

function bit.bxor(a, b)
    a, b = (a or 0) % MOD, (b or 0) % MOD
    local r = 0
    local f = 1
    for i = 0, 31 do
        if a % 2 ~= b % 2 then r = r + f end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        f = f * 2
        if a == 0 and b == 0 then break end
    end
    return r
end

function bit.lshift(a, b)
    return ((a or 0) * (2 ^ ((b or 0) % 32))) % MOD
end

function bit.rshift(a, b)
    return math.floor(((a or 0) % MOD) / (2 ^ ((b or 0) % 32)))
end

function bit.arshift(a, b)
    a = (a or 0) % MOD
    b = (b or 0) % 32
    local r = math.floor(a / (2 ^ b))
    if a >= 2147483648 then
        local fill = MOD - (2 ^ (32 - b))
        r = r + fill
    end
    return r
end

return bit
