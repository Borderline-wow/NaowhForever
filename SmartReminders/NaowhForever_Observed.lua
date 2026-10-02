-------------------------------------------------------------------------------
--  NaowhForever_Observed.lua -- when boss abilities actually landed, recorded
--  from the player's own pulls so reminders can be built from real times.
--
--  Nothing is written mid-pull: a bar is only a prediction until it runs out (a
--  stopped bar means the cast never happened), so predictions are held in memory
--  and committed at ENCOUNTER_END. Storage keeps a running mean per ability per
--  occurrence, bounded by ability count rather than pull count.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
if not ns then return end

local SCHEMA = 1              -- bump to retire every stored shape at once
local EXPIRY = 30 * 24 * 60 * 60
local MAX_SAMPLES = 10        -- mean stops averaging past this, so recent pulls keep moving it
local MAX_OCCURRENCES = 12    -- per ability; later casts of a long fight drift too far to be useful
local MAX_ABILITIES = 40      -- per encounter and difficulty
local SAME_CAST = 2           -- a message landing this close to a prediction is that same cast
local ENGAGE_GRACE = 3        -- casts this far ahead of our ENCOUNTER_START still belong to the pull
local MAX_BUFFER = 200        -- bounds what accumulates outside an encounter

-- Live for the current pull only.
local pending = {}   -- [barIdentity] = { sid, mod, landing, stage, stageAt }
local landed = {}    -- array of { sid, mod, at, stage, stageAt }

-- ENCOUNTER_END clears the main file's currentEncounter before a slash command can run,
-- so /nutank observed reads the last committed pull from here.
local lastPullEnc, lastPullDiff

function ns.ObservedLastPull()
    return lastPullEnc, lastPullDiff
end

-------------------------------------------------------------------------------
--  Storage
-------------------------------------------------------------------------------
-- At the SavedVariables root, not in a profile, so Reset Profile does not wipe weeks of pulls.
local function Root()
    local sv = _G.NaowhForeverDB
    if type(sv) ~= "table" then return nil end
    local o = sv.observed
    if type(o) ~= "table" or o.v ~= SCHEMA then
        o = { v = SCHEMA }
        sv.observed = o
    end
    return o
end

function ns.ObservedFor(encounterID, difficultyID)
    local o = Root()
    local enc = o and o[tostring(encounterID or 0)]
    if not enc then return nil end
    if difficultyID == nil then return enc end
    return enc[tostring(difficultyID)]
end

function ns.ObservedDifficulties(encounterID)
    local enc = ns.ObservedFor(encounterID, nil)
    local out = {}
    if type(enc) ~= "table" then return out end
    for diffKey, block in pairs(enc) do
        if type(block) == "table" then
            out[#out + 1] = { key = diffKey, at = block.at or 0, pulls = block.pulls or 0 }
        end
    end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

-- Runs once at login; nothing else prunes this store.
function ns.ObservedPrune()
    local o = Root()
    if not o then return end
    local cutoff = time() - EXPIRY
    for encKey, enc in pairs(o) do
        if encKey ~= "v" and type(enc) == "table" then
            for diffKey, block in pairs(enc) do
                if type(block) ~= "table" or (block.at or 0) < cutoff then
                    enc[diffKey] = nil
                end
            end
            if next(enc) == nil then o[encKey] = nil end
        end
    end
end

-------------------------------------------------------------------------------
--  Recording
-------------------------------------------------------------------------------
local function DropBefore(cutoff)
    for key, p in pairs(pending) do
        if p.at < cutoff then pending[key] = nil end
    end
    for i = #landed, 1, -1 do
        if landed[i].at < cutoff then table.remove(landed, i) end
    end
end

-- Not a wipe: boss mods broadcast their engage bars from their own ENCOUNTER_START
-- handler, which runs before ours, so the opening cast arrives just before this.
function ns.ObserveBeginPull()
    DropBefore(GetTime() - ENGAGE_GRACE)
end

function ns.ObserveCancel(barIdentity)
    if barIdentity ~= nil then pending[barIdentity] = nil end
end

function ns.ObserveCancelAll()
    wipe(pending)
end

-- With duration it is a bar (a cast still to come); without, a message (landing now).
-- Times are absolute until commit, so casts from before our ENCOUNTER_START still count.
function ns.ObserveCast(sid, mod, duration, barIdentity)
    if type(sid) ~= "number" or sid <= 0 then return end
    local startedAt, _, stage, stageAt = ns.PullContext()
    local now = GetTime()
    if not startedAt then DropBefore(now - ENGAGE_GRACE) end

    if type(duration) == "number" and duration > 0.5 then
        local key = barIdentity
        if key == nil then key = "sid:" .. sid end
        pending[key] = { sid = sid, mod = mod, at = now, landing = now + duration,
            stage = stage, stageAt = stageAt }
        return
    end
    if #landed >= MAX_BUFFER then return end

    -- Modules can pair a bar with a message for the same cast; keep only one.
    for key, p in pairs(pending) do
        if p.sid == sid and math.abs(p.landing - now) <= SAME_CAST then
            pending[key] = nil
            break
        end
    end
    landed[#landed + 1] = { sid = sid, mod = mod, at = now, stage = stage, stageAt = stageAt }
end

local function MergeSample(slot, t, stage, ts)
    if not slot.n then
        slot.t, slot.lo, slot.hi, slot.n = t, t, t, 1
    else
        local n = math.min(slot.n + 1, MAX_SAMPLES)
        slot.t = slot.t + (t - slot.t) / n
        slot.n = n
        if t < slot.lo then slot.lo = t end
        if t > slot.hi then slot.hi = t end
    end
    -- Later phases are health-gated, so phase-relative times drift far less than pull-relative.
    if stage then
        slot.stage = stage
        if ts then slot.ts = slot.ts and (slot.ts + (ts - slot.ts) / (slot.n or 1)) or ts end
    end
end

function ns.ObserveCommitPull(encounterID, difficultyID)
    local startedAt = ns.PullContext()
    local endedAt = GetTime()
    if encounterID then
        lastPullEnc, lastPullDiff = encounterID, difficultyID
    end
    if not (startedAt and encounterID) then
        wipe(pending); wipe(landed)
        return
    end
    local pullDur = endedAt - startedAt

    -- A standing prediction only counts if it would have landed before the pull ended.
    for _, p in pairs(pending) do
        if p.landing <= endedAt then
            landed[#landed + 1] = { sid = p.sid, mod = p.mod, at = p.landing,
                stage = p.stage, stageAt = p.stageAt }
            if #landed >= MAX_BUFFER then break end
        end
    end
    wipe(pending)

    if #landed == 0 then wipe(landed) return end
    table.sort(landed, function(a, b) return a.at < b.at end)

    local o = Root()
    if not o then wipe(landed) return end
    local encKey, diffKey = tostring(encounterID), tostring(difficultyID or 0)
    local enc = o[encKey]
    if type(enc) ~= "table" then enc = {}; o[encKey] = enc end
    local block = enc[diffKey]
    if type(block) ~= "table" then block = { casts = {} }; enc[diffKey] = block end
    if type(block.casts) ~= "table" then block.casts = {} end

    local abilityCount = 0
    for _ in pairs(block.casts) do abilityCount = abilityCount + 1 end

    local occurrence = {}
    for i = 1, #landed do
        local e = landed[i]
        local slotList = block.casts[e.sid]
        if not slotList and abilityCount < MAX_ABILITIES then
            slotList = { mod = e.mod }
            block.casts[e.sid] = slotList
            abilityCount = abilityCount + 1
        end
        if slotList then
            local idx = (occurrence[e.sid] or 0) + 1
            occurrence[e.sid] = idx
            if idx <= MAX_OCCURRENCES then
                local slot = slotList[idx]
                if type(slot) ~= "table" then slot = {}; slotList[idx] = slot end
                -- Engage bars inside the grace window predate the pull start slightly.
                MergeSample(slot, math.max(0, e.at - startedAt), e.stage,
                    e.stageAt and math.max(0, e.at - e.stageAt) or nil)
            end
        end
    end

    block.pulls = (block.pulls or 0) + 1
    block.at = time()
    if pullDur > (block.longest or 0) then block.longest = pullDur end
    wipe(landed)
end
