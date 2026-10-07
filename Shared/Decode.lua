-------------------------------------------------------------------------------
--  Decode.lua -- a pasted string read back as plain data (ns.Shared.Decode), for every import:
--  profiles, Reminder Packs, BiS lists, Forge macros, talent builds. The print encoding is
--  undone, the deflate stream is measured before LibDeflate builds it (a bomb is refused at
--  its cap, not after), LibSerialize runs in a pcall, and the value is walked once: no cycles,
--  no deeper than the cap, shared tables counted every time they are reached, numbers finite.
--  Decode.Text cleans a name or note from outside before it is shown. Loads with nothing
--  else from the addon, so the offline tests can dofile it.
-------------------------------------------------------------------------------
local byte, sub, gsub, type, pairs, pcall = string.byte, string.sub, string.gsub, type, pairs, pcall
local huge = math.huge

local Decode = {}

local MAX_DEPTH = 32
local MAX_VALUES = 200000

local POW = {}
for i = 0, 32 do POW[i] = 2 ^ i end

local LENGTH_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
    115, 131, 163, 195, 227, 258 }
local LENGTH_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
    13, 13 }
local ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local src, pos, buf, cnt

local function Bits(n)
    if n == 0 then return 0 end
    while cnt < n do
        local b = byte(src, pos)
        if not b then return nil end
        pos = pos + 1
        buf = buf + b * POW[cnt]
        cnt = cnt + 8
    end
    local v = buf % POW[n]
    buf = (buf - v) / POW[n]
    cnt = cnt - n
    return v
end

local function NewCode() return { count = {}, symbol = {} } end

local function Build(h, lengths, first, n)
    local count, symbol = h.count, h.symbol
    for len = 0, 15 do count[len] = 0 end
    for i = first, first + n - 1 do count[lengths[i]] = count[lengths[i]] + 1 end
    if count[0] == n then return true end
    local left = 1
    for len = 1, 15 do
        left = left * 2 - count[len]
        if left < 0 then return false end
    end
    local offs = h.offs or {}
    h.offs = offs
    offs[1] = 0
    for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
    for i = first, first + n - 1 do
        local len = lengths[i]
        if len ~= 0 then
            symbol[offs[len]] = i - first
            offs[len] = offs[len] + 1
        end
    end
    return true
end

local function Symbol(h)
    local count, code, first, index = h.count, 0, 0, 0
    for len = 1, 15 do
        local bit = Bits(1)
        if not bit then return nil end
        code = code + bit
        local c = count[len]
        if code - c < first then return h.symbol[index + code - first] end
        index = index + c
        first = (first + c) * 2
        code = code * 2
    end
end

local fixedLit, fixedDist, dynLit, dynDist, lenCode = NewCode(), NewCode(), NewCode(), NewCode(), NewCode()
local lengths = {}
do
    for i = 0, 143 do lengths[i] = 8 end
    for i = 144, 255 do lengths[i] = 9 end
    for i = 256, 279 do lengths[i] = 7 end
    for i = 280, 287 do lengths[i] = 8 end
    Build(fixedLit, lengths, 0, 288)
    for i = 0, 29 do lengths[i] = 5 end
    Build(fixedDist, lengths, 0, 30)
end

local function Codes(lit, dist, size, max)
    while true do
        local s = Symbol(lit)
        if not s then return nil end
        if s < 256 then
            size = size + 1
        elseif s == 256 then
            return size
        else
            s = s - 256
            if s > 29 then return nil end
            local extra = Bits(LENGTH_EXTRA[s])
            local d = extra and Symbol(dist)
            if not d or d > 29 or not Bits(DIST_EXTRA[d + 1]) then return nil end
            size = size + LENGTH_BASE[s] + extra
        end
        if size > max then return nil end
    end
end

local function Dynamic(size, max)
    local nlen, ndist, ncode = Bits(5), Bits(5), Bits(4)
    if not ncode then return nil end
    nlen, ndist, ncode = nlen + 257, ndist + 1, ncode + 4
    if nlen > 286 or ndist > 30 then return nil end
    for i = 0, 18 do lengths[i] = 0 end
    for i = 1, ncode do
        local v = Bits(3)
        if not v then return nil end
        lengths[ORDER[i]] = v
    end
    if not Build(lenCode, lengths, 0, 19) then return nil end
    local index, total = 0, nlen + ndist
    while index < total do
        local s = Symbol(lenCode)
        if not s then return nil end
        if s < 16 then
            lengths[index] = s
            index = index + 1
        else
            local value, rep = 0
            if s == 16 then
                if index == 0 then return nil end
                value, rep = lengths[index - 1], Bits(2)
                rep = rep and rep + 3
            elseif s == 17 then
                rep = Bits(3)
                rep = rep and rep + 3
            else
                rep = Bits(7)
                rep = rep and rep + 11
            end
            if not rep or index + rep > total then return nil end
            for _ = 1, rep do
                lengths[index] = value
                index = index + 1
            end
        end
    end
    if lengths[256] == 0 then return nil end
    if not (Build(dynLit, lengths, 0, nlen) and Build(dynDist, lengths, nlen, ndist)) then return nil end
    return Codes(dynLit, dynDist, size, max)
end

function Decode.InflatedSize(data, max)
    if type(data) ~= "string" then return nil end
    src, pos, buf, cnt = data, 1, 0, 0
    local size, last = 0, 0
    while last == 0 and size do
        last = Bits(1)
        local kind = last and Bits(2)
        if not kind then
            size = nil
        elseif kind == 0 then
            buf, cnt = 0, 0
            local a, b, c, d = byte(src, pos, pos + 3)
            local len = d and a + b * 256
            if not len or len + c + d * 256 ~= 65535 or pos + 3 + len > #src then
                size = nil
            else
                pos = pos + 4 + len
                size = size + len
                if size > max then size = nil end
            end
        elseif kind == 1 then
            size = Codes(fixedLit, fixedDist, size, max)
        elseif kind == 2 then
            size = Dynamic(size, max)
        else
            size = nil
        end
    end
    src = nil
    return size
end

local seen, budget

local function Walk(v, depth)
    local kind = type(v)
    if kind == "number" then return v == v and v > -huge and v < huge end
    if kind == "string" or kind == "boolean" then return true end
    if kind ~= "table" or depth > MAX_DEPTH or seen[v] then return false end
    seen[v] = true
    for k, val in pairs(v) do
        budget = budget - 1
        local kk = type(k)
        if budget < 0 or (kk ~= "string" and kk ~= "number") or not Walk(k, depth)
            or not Walk(val, depth + 1) then
            seen[v] = nil
            return false
        end
    end
    seen[v] = nil
    return true
end

function Decode.Plain(v, maxDepth, maxValues)
    local depthWas = MAX_DEPTH
    MAX_DEPTH, budget, seen = maxDepth or depthWas, maxValues or MAX_VALUES, {}
    local ok = Walk(v, 0)
    MAX_DEPTH, seen = depthWas, nil
    return ok
end

local function Libraries()
    local LS = LibStub and LibStub("LibSerialize", true)
    local LD = LibStub and LibStub("LibDeflate", true)
    if LS and LD then return LS, LD end
end

function Decode.String(body, limits)
    local LS, LD = Libraries()
    if not LS then return nil, "missing" end
    if type(body) ~= "string" or body == "" then return nil, "damaged" end
    if #body > limits.maxChars then return nil, "big" end
    local ok, packed = pcall(LD.DecodeForPrint, LD, body)
    if not (ok and type(packed) == "string") then return nil, "damaged" end
    local size = Decode.InflatedSize(packed, limits.maxBytes)
    if not size then return nil, "damaged" end
    local raw
    ok, raw = pcall(LD.DecompressDeflate, LD, packed)
    if not (ok and type(raw) == "string") or #raw > limits.maxBytes then return nil, "damaged" end
    local done, value = LS:Deserialize(raw)
    if not done or not Decode.Plain(value, limits.maxDepth, limits.maxValues) then return nil, "damaged" end
    return value
end

function Decode.Text(text, max)
    if type(text) ~= "string" then return nil end
    text = gsub(gsub(text, "[%c|]", ""), "^%s+", "")
    if max and #text > max then text = sub(text, 1, max) end
    return (gsub(text, "%s+$", ""))
end

local ns = _G.NaowhForever
if ns and ns.Shared then ns.Shared.Decode = Decode end
return Decode
