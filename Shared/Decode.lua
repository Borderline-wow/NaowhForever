-- Decode.lua: a pasted import string read back as plain data, within size, depth and bomb caps (ns.Shared.Decode).
local ns = _G.NaowhForever

local byte, sub, gsub, type, pairs, pcall = string.byte, string.sub, string.gsub, type, pairs, pcall
local huge = math.huge

local MAX_DEPTH = 32
local MAX_VALUES = 200000

local BYTE_BITS = 8
local MAX_BITS = 15
local WIDEST_READ = 32
local LITERALS = 256
local END_OF_BLOCK = 256
local MAX_LENGTH_CODE = 29
local MAX_DIST_CODE = 29

local BLOCK_TYPE_BITS = 2
local BLOCK_STORED, BLOCK_FIXED, BLOCK_DYNAMIC = 0, 1, 2
local STORED_HEADER = 4
local STORED_CHECK = 65535
local BYTE_RANGE = 256

local FIXED_LIT_COUNT = 288
local FIXED_LIT_RUNS = { { 143, 8 }, { 255, 9 }, { 279, 7 }, { 287, 8 } }
local FIXED_DIST_COUNT, FIXED_DIST_LENGTH = 30, 5

local HLIT_BITS, HDIST_BITS, HCLEN_BITS = 5, 5, 4
local HLIT_BASE, HDIST_BASE, HCLEN_BASE = 257, 1, 4
local MAX_LIT_CODES, MAX_DIST_CODES = 286, 30
local CODE_LENGTH_CODES = 19
local CODE_LENGTH_BITS = 3
local COPY_PREVIOUS, REPEAT_ZERO = 16, 17
local COPY_PREVIOUS_BITS, COPY_PREVIOUS_MIN = 2, 3
local REPEAT_ZERO_BITS, REPEAT_ZERO_MIN = 3, 3
local REPEAT_ZERO_LONG_BITS, REPEAT_ZERO_LONG_MIN = 7, 11

local LENGTH_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
    115, 131, 163, 195, 227, 258 }
local LENGTH_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
    13, 13 }
local ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local POW = {}
for i = 0, WIDEST_READ do POW[i] = 2 ^ i end

local Decode = {}

local src, pos, buf, cnt
local seen, budget

local function Bits(n)
    if n == 0 then return 0 end
    while cnt < n do
        local b = byte(src, pos)
        if not b then return nil end
        pos = pos + 1
        buf = buf + b * POW[cnt]
        cnt = cnt + BYTE_BITS
    end
    local v = buf % POW[n]
    buf = (buf - v) / POW[n]
    cnt = cnt - n
    return v
end

local function NewCode() return { count = {}, symbol = {} } end

local function Build(h, lengths, first, n)
    local count, symbol = h.count, h.symbol
    for len = 0, MAX_BITS do count[len] = 0 end
    for i = first, first + n - 1 do count[lengths[i]] = count[lengths[i]] + 1 end
    if count[0] == n then return true end
    local left = 1
    for len = 1, MAX_BITS do
        left = left * 2 - count[len]
        if left < 0 then return false end
    end
    local offs = h.offs or {}
    h.offs = offs
    offs[1] = 0
    for len = 1, MAX_BITS - 1 do offs[len + 1] = offs[len] + count[len] end
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
    for len = 1, MAX_BITS do
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

local function BuildFixed()
    local from = 0
    for r = 1, #FIXED_LIT_RUNS do
        local run = FIXED_LIT_RUNS[r]
        for i = from, run[1] do lengths[i] = run[2] end
        from = run[1] + 1
    end
    Build(fixedLit, lengths, 0, FIXED_LIT_COUNT)
    for i = 0, FIXED_DIST_COUNT - 1 do lengths[i] = FIXED_DIST_LENGTH end
    Build(fixedDist, lengths, 0, FIXED_DIST_COUNT)
end

BuildFixed()

local function Codes(lit, dist, size, max)
    while true do
        local s = Symbol(lit)
        if not s then return nil end
        if s < LITERALS then
            size = size + 1
        elseif s == END_OF_BLOCK then
            return size
        else
            s = s - END_OF_BLOCK
            if s > MAX_LENGTH_CODE then return nil end
            local extra = Bits(LENGTH_EXTRA[s])
            local d = extra and Symbol(dist)
            if not d or d > MAX_DIST_CODE or not Bits(DIST_EXTRA[d + 1]) then return nil end
            size = size + LENGTH_BASE[s] + extra
        end
        if size > max then return nil end
    end
end

local function Repeat(s, index)
    if s == COPY_PREVIOUS then
        if index == 0 then return nil end
        local rep = Bits(COPY_PREVIOUS_BITS)
        return rep and rep + COPY_PREVIOUS_MIN, lengths[index - 1]
    end
    if s == REPEAT_ZERO then
        local rep = Bits(REPEAT_ZERO_BITS)
        return rep and rep + REPEAT_ZERO_MIN, 0
    end
    local rep = Bits(REPEAT_ZERO_LONG_BITS)
    return rep and rep + REPEAT_ZERO_LONG_MIN, 0
end

local function CodeLengths(total)
    local index = 0
    while index < total do
        local s = Symbol(lenCode)
        if not s then return false end
        if s < COPY_PREVIOUS then
            lengths[index] = s
            index = index + 1
        else
            local rep, value = Repeat(s, index)
            if not rep or index + rep > total then return false end
            for _ = 1, rep do
                lengths[index] = value
                index = index + 1
            end
        end
    end
    return true
end

local function Dynamic(size, max)
    local nlen, ndist, ncode = Bits(HLIT_BITS), Bits(HDIST_BITS), Bits(HCLEN_BITS)
    if not ncode then return nil end
    nlen, ndist, ncode = nlen + HLIT_BASE, ndist + HDIST_BASE, ncode + HCLEN_BASE
    if nlen > MAX_LIT_CODES or ndist > MAX_DIST_CODES then return nil end
    for i = 0, CODE_LENGTH_CODES - 1 do lengths[i] = 0 end
    for i = 1, ncode do
        local v = Bits(CODE_LENGTH_BITS)
        if not v then return nil end
        lengths[ORDER[i]] = v
    end
    if not Build(lenCode, lengths, 0, CODE_LENGTH_CODES) then return nil end
    if not CodeLengths(nlen + ndist) then return nil end
    if lengths[END_OF_BLOCK] == 0 then return nil end
    if not (Build(dynLit, lengths, 0, nlen) and Build(dynDist, lengths, nlen, ndist)) then return nil end
    return Codes(dynLit, dynDist, size, max)
end

local function Stored(size, max)
    buf, cnt = 0, 0
    local a, b, c, d = byte(src, pos, pos + STORED_HEADER - 1)
    local len = d and a + b * BYTE_RANGE
    if not len or len + c + d * BYTE_RANGE ~= STORED_CHECK or pos + STORED_HEADER - 1 + len > #src then return nil end
    pos = pos + STORED_HEADER + len
    size = size + len
    if size > max then return nil end
    return size
end

local function Block(kind, size, max)
    if kind == BLOCK_STORED then return Stored(size, max) end
    if kind == BLOCK_FIXED then return Codes(fixedLit, fixedDist, size, max) end
    if kind == BLOCK_DYNAMIC then return Dynamic(size, max) end
    return nil
end

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

local function Libraries()
    local LS = LibStub and LibStub("LibSerialize", true)
    local LD = LibStub and LibStub("LibDeflate", true)
    if LS and LD then return LS, LD end
end

function Decode.InflatedSize(data, max)
    if type(data) ~= "string" then return nil end
    src, pos, buf, cnt = data, 1, 0, 0
    local size, last = 0, 0
    while last == 0 and size do
        last = Bits(1)
        local kind = last and Bits(BLOCK_TYPE_BITS)
        size = kind and Block(kind, size, max) or nil
    end
    src = nil
    return size
end

function Decode.Plain(v, maxDepth, maxValues)
    local depthWas = MAX_DEPTH
    MAX_DEPTH, budget, seen = maxDepth or depthWas, maxValues or MAX_VALUES, {}
    local ok = Walk(v, 0)
    MAX_DEPTH, seen = depthWas, nil
    return ok
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

if ns and ns.Shared then ns.Shared.Decode = Decode end
return Decode
