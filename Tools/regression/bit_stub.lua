-- bit_stub.lua: the game's bit.bxor for tests on stock Lua 5.1, which has no bit library.
local TWO_32 = 4294967296

local function bxor(a, b)
    a, b = a % TWO_32, b % TWO_32
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local x, y = a % 2, b % 2
        if x ~= y then result = result + place end
        a, b, place = (a - x) / 2, (b - y) / 2, place * 2
    end
    return result
end

return { bxor = bxor }
